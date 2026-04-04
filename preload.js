const path = require("path");
const { pathToFileURL } = require("url");

(async () => {
  const runtimePath = path.join(__dirname, "generated", "preload_runtime.mjs");
  const runtimeModule = await import(pathToFileURL(runtimePath).href);
  if (runtimeModule && typeof runtimeModule.installPreloadBridge === "function") {
    runtimeModule.installPreloadBridge();
  }
})().catch((error) => {
  console.error("[preload] Failed to install Jac bridge:", error);
});
