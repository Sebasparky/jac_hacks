const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("browserAPI", {
  getHomeUrl: () => ipcRenderer.invoke("browser:get-home-url"),
  normalizeUrl: (rawInput) => ipcRenderer.invoke("browser:normalize-url", rawInput),
  minimizeWindow: () => ipcRenderer.invoke("window:minimize"),
  toggleMaximizeWindow: () => ipcRenderer.invoke("window:toggle-maximize"),
  closeWindow: () => ipcRenderer.invoke("window:close"),
  layersStart: (payload) => ipcRenderer.invoke("layers:start", payload),
  layersEvent: (payload) => ipcRenderer.invoke("layers:event", payload),
  layersStop: (payload) => ipcRenderer.invoke("layers:stop", payload),
  layersGetTrace: (payload) => ipcRenderer.invoke("layers:get-trace", payload),
  layersCompile: (payload) => ipcRenderer.invoke("layers:compile", payload),
  layersPlan: (payload) => ipcRenderer.invoke("layers:plan", payload)
});
