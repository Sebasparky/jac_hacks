const path = require("path");
const fs = require("fs");
const { pathToFileURL } = require("url");
const { execFile, execFileSync } = require("child_process");
const { app, BrowserWindow, ipcMain, screen } = require("electron");

const APP_DISPLAY_NAME = "Jac Browser";
app.commandLine.appendSwitch("class", APP_DISPLAY_NAME);
const JAC_SCRIPT_PATH = path.join(__dirname, "jac", "browser_core.jac");
const WEBVIEW_PRELOAD_URL = pathToFileURL(path.join(__dirname, "webview_preload.js")).toString();
const OBSERVATION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "observation.jac");
const COMPILATION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "compilation.jac");
const EXECUTION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "execution.jac");
const HELPERS_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "helpers.jac");
const LLM_RUNTIME_SCRIPT_PATH = path.join(__dirname, "jac", "llm", "runtime.jac");
const CLIENT_INDEX_PATH = path.join(__dirname, ".jac", "client", "dist", "index.html");
const APP_ICON_PATH = path.join(
  __dirname,
  "assets",
  process.platform === "win32" ? "jac-browser-icon.ico" : "jac-browser-icon.png"
);
const DEFAULT_URL = "https://www.google.com";
const RESTORE_BOUNDS = new WeakMap();
const URL_CACHE_TTL_MS = 5 * 60 * 1000;
const URL_CACHE_LIMIT = 160;
const NORMALIZED_URL_CACHE = new Map();
const NORMALIZED_URL_INFLIGHT = new Map();
let llmRuntimeState = {
  active: false,
  provider: "",
  transport: "",
  model: "",
  thinking_mode: "",
  reason: "LLM runtime has not started yet"
};
let llmRuntimeStopped = false;

/**
 * R: Build a stable cache key for URL normalization requests.
 * M: Trims free-form input so visually identical requests share one entry.
 * E: Empty and null-like values collapse to the empty-string home key.
 */
function getNormalizedUrlCacheKey(rawInput = "") {
  return String(rawInput || "").trim();
}

/**
 * R: Read one cached normalized URL if it is still fresh.
 * M: Checks expiry, refreshes insertion order for hot entries, and returns the URL.
 * E: Expired or missing entries return null and are removed eagerly.
 */
function readNormalizedUrlCache(cacheKey) {
  const cached = NORMALIZED_URL_CACHE.get(cacheKey);
  if (!cached) {
    return null;
  }

  if (Date.now() - cached.createdAt > URL_CACHE_TTL_MS) {
    NORMALIZED_URL_CACHE.delete(cacheKey);
    return null;
  }

  NORMALIZED_URL_CACHE.delete(cacheKey);
  NORMALIZED_URL_CACHE.set(cacheKey, cached);
  return cached.url;
}

/**
 * R: Store a normalized URL in the bounded in-memory cache.
 * M: Inserts the newest entry, refreshes duplicates, then trims oldest items.
 * E: Empty URLs are still cached so fallback resolutions stay cheap.
 */
function rememberNormalizedUrl(cacheKey, url) {
  if (NORMALIZED_URL_CACHE.has(cacheKey)) {
    NORMALIZED_URL_CACHE.delete(cacheKey);
  }

  NORMALIZED_URL_CACHE.set(cacheKey, {
    url: String(url || DEFAULT_URL),
    createdAt: Date.now()
  });

  while (NORMALIZED_URL_CACHE.size > URL_CACHE_LIMIT) {
    const oldestKey = NORMALIZED_URL_CACHE.keys().next().value;
    NORMALIZED_URL_CACHE.delete(oldestKey);
  }
}

/**
 * R: Resolve the usable screen work area for the target window.
 * M: Matches the window against the nearest display and returns its work area bounds.
 * E: Falls back to current window bounds when display lookup is unavailable.
 */
function getWorkAreaBounds(win, referenceBounds = null) {
  if (!win || win.isDestroyed()) {
    return null;
  }

  const bounds = referenceBounds || win.getBounds();
  const display = screen.getDisplayMatching(bounds);
  if (!display || !display.workArea) {
    return bounds;
  }

  const { x, y, width, height } = display.workArea;
  return { x, y, width, height };
}

/**
 * R: Correct native maximized bounds for frameless windows.
 * M: Reapplies the display work area after maximize so content aligns to the top-left corner.
 * E: No-ops for destroyed windows and skips platforms that do not need the workaround.
 */
function alignNativeMaximize(win) {
  if (!win || win.isDestroyed() || process.platform !== "win32") {
    return;
  }

  const workAreaBounds = getWorkAreaBounds(win);
  if (!workAreaBounds) {
    return;
  }

  setTimeout(() => {
    if (!win.isDestroyed() && win.isMaximized()) {
      win.setBounds(workAreaBounds);
    }
  }, 0);
}

/**
 * R: Get a normalized URL from Jac so renderer input stays deterministic.
 * M: Executes `jac run` with optional raw user text and parses JSON output.
 * E: Rejects on process errors, timeouts, or malformed JSON.
 */
function normalizeUrlWithJac(rawInput = "") {
  const cacheKey = getNormalizedUrlCacheKey(rawInput);
  const cached = readNormalizedUrlCache(cacheKey);
  if (cached) {
    return Promise.resolve(cached);
  }

  if (NORMALIZED_URL_INFLIGHT.has(cacheKey)) {
    return NORMALIZED_URL_INFLIGHT.get(cacheKey);
  }

  const pending = new Promise((resolve, reject) => {
    const args = ["run", JAC_SCRIPT_PATH];
    if (cacheKey) {
      args.push(cacheKey);
    }

    execFile("jac", args, { timeout: 4000 }, (error, stdout, stderr) => {
      if (error) {
        reject(
          new Error(
            `jac run failed: ${error.message}${stderr ? `\n${stderr}` : ""}`
          )
        );
        return;
      }

      try {
        const parsed = JSON.parse(stdout.trim());
        const finalUrl = parsed.url || DEFAULT_URL;
        rememberNormalizedUrl(cacheKey, finalUrl);
        resolve(finalUrl);
      } catch (parseError) {
        reject(
          new Error(
            `invalid jac JSON output: ${parseError.message}${
              stdout ? `\nstdout: ${stdout}` : ""
            }`
          )
        );
      }
    });
  }).finally(() => {
    NORMALIZED_URL_INFLIGHT.delete(cacheKey);
  });

  NORMALIZED_URL_INFLIGHT.set(cacheKey, pending);
  return pending;
}

/**
 * R: Execute a Jac layer command and return parsed JSON output.
 * M: Runs `jac run <script> <command> <payload_json>` through execFile.
 * E: Converts runtime and parse failures into rejected errors.
 */
function runJacLayerCommand(scriptPath, command, payload = {}, options = {}) {
  return new Promise((resolve, reject) => {
    const args = ["run", scriptPath, command, JSON.stringify(payload || {})];
    const timeout = Number(options.timeoutMs || 6000);
    execFile("jac", args, { timeout, maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        reject(
          new Error(
            `jac layer command failed: ${error.message}${stderr ? `\n${stderr}` : ""}`
          )
        );
        return;
      }

      try {
        const parsed = JSON.parse(stdout.trim() || "{}");
        resolve(parsed);
      } catch (parseError) {
        reject(
          new Error(
            `invalid jac layer JSON output: ${parseError.message}${
              stdout ? `\nstdout: ${stdout}` : ""
            }`
          )
        );
      }
    });
  });
}

/**
 * R: Normalize one runtime lifecycle response into a stable renderer-facing shape.
 * M: Extracts the nested runtime payload when present and falls back to an inactive record.
 * E: Unexpected responses produce a safe inactive status instead of throwing.
 */
function runtimeStateFromResult(result, fallbackReason = "LLM runtime unavailable") {
  const runtime = result && typeof result === "object" && result.runtime && typeof result.runtime === "object"
    ? result.runtime
    : {};

  return {
    active: Boolean(runtime.active),
    provider: String(runtime.provider || ""),
    transport: String(runtime.transport || ""),
    model: String(runtime.model || ""),
    thinking_mode: String(runtime.thinking_mode || ""),
    started_at: String(runtime.started_at || ""),
    stopped_at: String(runtime.stopped_at || ""),
    updated_at: String(runtime.updated_at || ""),
    source: String(runtime.source || ""),
    reason: String(runtime.reason || fallbackReason)
  };
}

/**
 * R: Activate the browser-owned compile runtime before windows are created.
 * M: Calls the Jac runtime lifecycle module and caches its status in memory.
 * E: Failures degrade to an inactive state so the browser still opens normally.
 */
async function startLlmRuntime() {
  llmRuntimeStopped = false;
  try {
    const result = await runJacLayerCommand(LLM_RUNTIME_SCRIPT_PATH, "start", {
      source: "browser_startup"
    });
    llmRuntimeState = runtimeStateFromResult(result, "LLM runtime failed to start");
  } catch (err) {
    llmRuntimeState = {
      active: false,
      provider: "",
      transport: "",
      model: "",
      thinking_mode: "",
      started_at: "",
      stopped_at: "",
      updated_at: "",
      source: "browser_startup",
      reason: err.message || "LLM runtime failed to start"
    };
  }

  return llmRuntimeState;
}

/**
 * R: Deactivate the browser-owned compile runtime during shutdown.
 * M: Uses a synchronous Jac invocation so the state file is updated before process exit.
 * E: Errors are swallowed after logging because shutdown should continue.
 */
function stopLlmRuntimeSync() {
  if (llmRuntimeStopped) {
    return llmRuntimeState;
  }
  llmRuntimeStopped = true;

  try {
    const stdout = execFileSync(
      "jac",
      ["run", LLM_RUNTIME_SCRIPT_PATH, "stop", JSON.stringify({ source: "browser_close" })],
      { timeout: 4000, maxBuffer: 1024 * 1024 }
    );
    const parsed = JSON.parse(String(stdout || "").trim() || "{}");
    llmRuntimeState = runtimeStateFromResult(parsed, "LLM runtime stopped");
  } catch (err) {
    console.warn("[llm:stop]", err.message || err);
  }

  return llmRuntimeState;
}

/**
 * R: Build the desktop browser shell window.
 * M: Creates BrowserWindow with preload bridge and enabled webview tag.
 * E: Renderer owns navigation behavior; this only boots shell.
 */
function createWindow() {
  const win = new BrowserWindow({
    title: APP_DISPLAY_NAME,
    width: 1480,
    height: 940,
    minWidth: 980,
    minHeight: 700,
    frame: false,
    show: false,
    backgroundColor: "#edf4e3",
    icon: fs.existsSync(APP_ICON_PATH) ? APP_ICON_PATH : undefined,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true,
      sandbox: false
    }
  });

  win.on("maximize", () => {
    alignNativeMaximize(win);
  });

  win.once("ready-to-show", () => {
    if (!win.isDestroyed()) {
      win.show();
    }
  });

  win.removeMenu();
  if (fs.existsSync(CLIENT_INDEX_PATH)) {
    win.loadFile(CLIENT_INDEX_PATH);
    return;
  }

  console.warn("[window] Jac client bundle missing; falling back to legacy index.html");
  win.loadFile(path.join(__dirname, "index.html"));
}

app.setName(APP_DISPLAY_NAME);
app.name = APP_DISPLAY_NAME;
if (typeof app.setAppUserModelId === "function") {
  app.setAppUserModelId("com.jac.browser");
}
if (process.platform === "linux" && typeof app.setDesktopName === "function") {
  app.setDesktopName("jac-browser.desktop");
}

ipcMain.handle("window:minimize", (event) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (win) {
    win.minimize();
  }
});

ipcMain.handle("window:toggle-maximize", (event) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (!win) {
    return false;
  }

  if (RESTORE_BOUNDS.has(win)) {
    const previousBounds = RESTORE_BOUNDS.get(win);
    RESTORE_BOUNDS.delete(win);
    win.setBounds(previousBounds);
    return false;
  }

  if (win.isMaximized()) {
    win.unmaximize();
    return false;
  }

  const currentBounds = win.getBounds();
  const workAreaBounds = getWorkAreaBounds(win, currentBounds);

  RESTORE_BOUNDS.set(win, currentBounds);
  if (workAreaBounds) {
    win.setBounds(workAreaBounds);
  }
  return true;
});

ipcMain.handle("window:close", (event) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (win) {
    win.close();
  }
});

ipcMain.handle("browser:get-home-url", async () => {
  try {
    return await normalizeUrlWithJac("");
  } catch (err) {
    console.warn("[browser:get-home-url]", err.message);
    return DEFAULT_URL;
  }
});

ipcMain.handle("browser:normalize-url", async (_event, rawInput) => {
  try {
    return await normalizeUrlWithJac(rawInput || "");
  } catch (err) {
    console.warn("[browser:normalize-url]", err.message);
    return DEFAULT_URL;
  }
});

ipcMain.handle("browser:get-webview-preload-url", () => WEBVIEW_PRELOAD_URL);
ipcMain.handle("browser:get-llm-status", async () => llmRuntimeState);

ipcMain.handle("layers:start", async (_event, payload) => {
  try {
    return await runJacLayerCommand(OBSERVATION_SCRIPT_PATH, "start", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("layers:event", async (_event, payload) => {
  try {
    return await runJacLayerCommand(OBSERVATION_SCRIPT_PATH, "append", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("layers:stop", async (_event, payload) => {
  try {
    return await runJacLayerCommand(OBSERVATION_SCRIPT_PATH, "stop", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("layers:get-trace", async (_event, payload) => {
  try {
    return await runJacLayerCommand(OBSERVATION_SCRIPT_PATH, "get", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("layers:compile", async (_event, payload) => {
  try {
    return await runJacLayerCommand(COMPILATION_SCRIPT_PATH, "build", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("layers:plan", async (_event, payload) => {
  try {
    return await runJacLayerCommand(EXECUTION_SCRIPT_PATH, "plan", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("helpers:create", async (_event, payload) => {
  try {
    return await runJacLayerCommand(HELPERS_SCRIPT_PATH, "create_helper", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("helpers:list", async (_event, payload) => {
  try {
    return await runJacLayerCommand(HELPERS_SCRIPT_PATH, "list_helpers", payload, { timeoutMs: 15000 });
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("helpers:get", async (_event, payload) => {
  try {
    return await runJacLayerCommand(HELPERS_SCRIPT_PATH, "get_helper", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("helpers:run-once", async (_event, payload) => {
  try {
    return await runJacLayerCommand(HELPERS_SCRIPT_PATH, "run_helper_once", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("helpers:list-runs", async (_event, payload) => {
  try {
    return await runJacLayerCommand(HELPERS_SCRIPT_PATH, "list_helper_runs", payload, { timeoutMs: 15000 });
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("helpers:get-run", async (_event, payload) => {
  try {
    return await runJacLayerCommand(HELPERS_SCRIPT_PATH, "get_helper_run", payload);
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

app.whenReady().then(async () => {
  await startLlmRuntime();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("before-quit", () => {
  stopLlmRuntimeSync();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
