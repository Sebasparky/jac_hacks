const path = require("path");
const fs = require("fs");
const { pathToFileURL } = require("url");
const { execFile } = require("child_process");
const { app, BrowserWindow, ipcMain, screen } = require("electron");

const JAC_SCRIPT_PATH = path.join(__dirname, "jac", "browser_core.jac");
const WEBVIEW_PRELOAD_URL = pathToFileURL(path.join(__dirname, "webview_preload.js")).toString();
const OBSERVATION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "observation.jac");
const COMPILATION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "compilation.jac");
const EXECUTION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "execution.jac");
const CLIENT_INDEX_PATH = path.join(__dirname, ".jac", "client", "dist", "index.html");
const DEFAULT_URL = "https://example.com";
const RESTORE_BOUNDS = new WeakMap();
const URL_CACHE_TTL_MS = 5 * 60 * 1000;
const URL_CACHE_LIMIT = 160;
const NORMALIZED_URL_CACHE = new Map();
const NORMALIZED_URL_INFLIGHT = new Map();

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
function runJacLayerCommand(scriptPath, command, payload = {}) {
  return new Promise((resolve, reject) => {
    const args = ["run", scriptPath, command, JSON.stringify(payload || {})];
    execFile("jac", args, { timeout: 6000, maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => {
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
 * R: Build the desktop browser shell window.
 * M: Creates BrowserWindow with preload bridge and enabled webview tag.
 * E: Renderer owns navigation behavior; this only boots shell.
 */
function createWindow() {
  const win = new BrowserWindow({
    width: 1480,
    height: 940,
    minWidth: 980,
    minHeight: 700,
    frame: false,
    show: false,
    backgroundColor: "#edf4e3",
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

app.whenReady().then(() => {
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
