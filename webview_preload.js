const path = require("path");
const { pathToFileURL } = require("url");

(async () => {
  const runtimePath = path.join(__dirname, "generated", "webview_preload_runtime.mjs");
  const runtimeModule = await import(pathToFileURL(runtimePath).href);
  if (runtimeModule && typeof runtimeModule.installWebviewPreload === "function") {
    runtimeModule.installWebviewPreload();
  }
})().catch((error) => {
  console.error("[webview_preload] Failed to install Jac telemetry:", error);
});
