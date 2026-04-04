const path = require("path");
const { execFile } = require("child_process");
const { app, BrowserWindow, ipcMain, screen } = require("electron");

const JAC_SCRIPT_PATH = path.join(__dirname, "jac", "browser_core.jac");
const OBSERVATION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "observation.jac");
const COMPILATION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "compilation.jac");
const EXECUTION_SCRIPT_PATH = path.join(__dirname, "jac", "layers", "execution.jac");
const DEFAULT_URL = "https://example.com";
const RESTORE_BOUNDS = new WeakMap();

/**
 * R: Get a normalized URL from Jac so renderer input stays deterministic.
 * M: Executes `jac run` with optional raw user text and parses JSON output.
 * E: Rejects on process errors, timeouts, or malformed JSON.
 */
function normalizeUrlWithJac(rawInput = "") {
  return new Promise((resolve, reject) => {
    const args = ["run", JAC_SCRIPT_PATH];
    if (String(rawInput).trim()) {
      args.push(String(rawInput));
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
        resolve(parsed.url || DEFAULT_URL);
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
  });
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
    backgroundColor: "#f2f5fb",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true,
      sandbox: false
    }
  });

  win.removeMenu();
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

  const currentBounds = win.getBounds();
  const display = screen.getDisplayMatching(currentBounds);
  const { x, y, width, height } = display.workArea;

  RESTORE_BOUNDS.set(win, currentBounds);
  win.setBounds({ x, y, width, height });
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
