const browserView = document.getElementById("browserView");
const navForm = document.getElementById("navForm");
const addressInput = document.getElementById("addressInput");
const backBtn = document.getElementById("backBtn");
const forwardBtn = document.getElementById("forwardBtn");
const reloadBtn = document.getElementById("reloadBtn");
const tabTitle = document.getElementById("tabTitle");
const siteBadge = document.getElementById("siteBadge");
const progressBar = document.getElementById("progressBar");
const minBtn = document.getElementById("minBtn");
const maxBtn = document.getElementById("maxBtn");
const closeBtn = document.getElementById("closeBtn");
const goBtn = document.getElementById("goBtn");
const startTraceBtn = document.getElementById("startTraceBtn");
const stopTraceBtn = document.getElementById("stopTraceBtn");
const compileTraceBtn = document.getElementById("compileTraceBtn");
const planWorkflowBtn = document.getElementById("planWorkflowBtn");
const sessionIdLabel = document.getElementById("sessionIdLabel");
const workflowIdLabel = document.getElementById("workflowIdLabel");
const layerLog = document.getElementById("layerLog");

let progressInterval = null;
let progressGuardTimeout = null;
let isWebviewReady = false;
let pendingUrl = "";
const DEFAULT_URL = "https://example.com";
const SEARCH_URL = "https://duckduckgo.com/?q=";
let activeSessionId = "";
let activeWorkflowId = "";

/**
 * R: Set the top loading bar to a fixed percentage.
 * M: Updates inline width style with clamped value.
 * E: Values outside 0-100 are clamped safely.
 */
function setProgress(value) {
  const clamped = Math.max(0, Math.min(100, value));
  progressBar.style.width = `${clamped}%`;
}

/**
 * R: Run a subtle loading animation while page is navigating.
 * M: Increments bar toward 85% until navigation finishes.
 * E: Does nothing if an animation is already active.
 */
function startProgress() {
  if (progressInterval) {
    return;
  }
  setProgress(8);
  progressInterval = setInterval(() => {
    const current = Number.parseFloat(progressBar.style.width || "0");
    if (current < 85) {
      setProgress(current + 6);
    }
  }, 120);

  if (progressGuardTimeout) {
    clearTimeout(progressGuardTimeout);
  }
  progressGuardTimeout = setTimeout(() => {
    finishProgress();
  }, 15000);
}

/**
 * R: End loading animation with a clean completion transition.
 * M: Jumps to 100%, then resets to 0 shortly after.
 * E: Clears pending interval regardless of navigation outcome.
 */
function finishProgress() {
  if (progressInterval) {
    clearInterval(progressInterval);
    progressInterval = null;
  }
  if (progressGuardTimeout) {
    clearTimeout(progressGuardTimeout);
    progressGuardTimeout = null;
  }
  setProgress(100);
  setTimeout(() => setProgress(0), 220);
}

/**
 * R: Add a timestamped line to the layer development panel log.
 * M: Prefixes each message with local time and appends to log element.
 * E: If panel is unavailable, function exits silently.
 */
function appendLayerLog(message) {
  if (!layerLog) {
    return;
  }
  const stamp = new Date().toLocaleTimeString();
  layerLog.textContent = `[${stamp}] ${message}\n${layerLog.textContent}`.slice(0, 5000);
}

/**
 * R: Sync visible session/workflow ids in the layer panel.
 * M: Writes current in-memory IDs to state labels.
 * E: Shows `none` when ids are unset.
 */
function syncLayerStateLabels() {
  if (sessionIdLabel) {
    sessionIdLabel.textContent = activeSessionId || "none";
  }
  if (workflowIdLabel) {
    workflowIdLabel.textContent = activeWorkflowId || "none";
  }
}

/**
 * R: Send one observation event to Jac layer API when recording is active.
 * M: Calls preload bridge with session id plus normalized event payload.
 * E: No-op when recording session is not active.
 */
async function recordObservationEvent(eventPayload) {
  if (!activeSessionId) {
    return;
  }
  try {
    const result = await window.browserAPI.layersEvent({
      session_id: activeSessionId,
      event: eventPayload
    });
    if (!result.ok) {
      appendLayerLog(`Observation append failed: ${result.error || "unknown error"}`);
    }
  } catch (err) {
    appendLayerLog(`Observation append threw: ${err.message}`);
  }
}

/**
 * R: Normalize free-form text into a URL when preload/IPC is unavailable.
 * M: Applies scheme/domain detection, then URL-encoded search fallback.
 * E: Empty input resolves to DEFAULT_URL.
 */
function normalizeClientSide(rawValue) {
  const cleaned = String(rawValue || "").trim();
  if (!cleaned) {
    return DEFAULT_URL;
  }
  const lowered = cleaned.toLowerCase();
  if (lowered.startsWith("http://") || lowered.startsWith("https://")) {
    return cleaned;
  }
  const looksLikeDomain = cleaned.includes(".") && !cleaned.includes(" ");
  if (looksLikeDomain) {
    return `https://${cleaned}`;
  }
  return `${SEARCH_URL}${encodeURIComponent(cleaned)}`;
}

/**
 * R: Get a normalized URL from preload bridge if available, else local fallback.
 * M: Uses IPC normalization primarily, then client-side normalization on error.
 * E: Never throws; always returns a navigable URL.
 */
async function safeNormalizeUrl(rawValue) {
  try {
    if (window.browserAPI && typeof window.browserAPI.normalizeUrl === "function") {
      const viaJac = await window.browserAPI.normalizeUrl(rawValue);
      if (viaJac) {
        return viaJac;
      }
    }
  } catch (_err) {
    // Fall through to local normalization.
  }
  return normalizeClientSide(rawValue);
}

/**
 * R: Resolve home URL for initial load in a fault-tolerant way.
 * M: Reads from preload bridge if available, otherwise uses default URL.
 * E: Never throws.
 */
async function safeGetHomeUrl() {
  try {
    if (window.browserAPI && typeof window.browserAPI.getHomeUrl === "function") {
      const home = await window.browserAPI.getHomeUrl();
      if (home) {
        return home;
      }
    }
  } catch (_err) {
    // Ignore and use default.
  }
  return DEFAULT_URL;
}

/**
 * R: Load a URL in webview with readiness-safe fallback behavior.
 * M: Queues navigation until dom-ready, then prefers loadURL and falls back to src.
 * E: Invalid or empty URLs are ignored to avoid runtime exceptions.
 */
function loadInWebview(url) {
  if (!url || typeof url !== "string") {
    return;
  }

  pendingUrl = url;
  browserView.setAttribute("src", url);
}

/**
 * R: Update chrome UI state from current webview page.
 * M: Syncs URL, tab title, secure badge, and nav button enabled states.
 * E: Uses defaults when title or URL are unavailable.
 */
function syncChromeState() {
  const currentUrl = browserView.getURL();
  if (currentUrl) {
    addressInput.value = currentUrl;
    const isSecure = currentUrl.startsWith("https://");
    siteBadge.textContent = isSecure ? "Secure" : "Open";
  }

  const title = browserView.getTitle() || "New Tab";
  tabTitle.textContent = title;

  backBtn.disabled = !browserView.canGoBack();
  forwardBtn.disabled = !browserView.canGoForward();
}

/**
 * R: Navigate using Jac-normalized input from omnibox.
 * M: Sends text through preload bridge and loads returned URL.
 * E: Falls back to current URL/default URL if normalization is empty.
 */
async function navigateFromInput(rawValue) {
  try {
    startProgress();
    const fallback = browserView.getURL() || DEFAULT_URL;
    const normalized = await safeNormalizeUrl(rawValue);
    await recordObservationEvent({
      type: "input",
      url: fallback,
      target: { label: "address_bar", name: "address" },
      value: String(rawValue || ""),
      meta: { source: "omnibox" }
    });
    loadInWebview(normalized || fallback);
  } catch (_err) {
    finishProgress();
    tabTitle.textContent = "Navigation error";
  }
}

navForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  await navigateFromInput(addressInput.value);
});

goBtn.addEventListener("click", async (event) => {
  event.preventDefault();
  await navigateFromInput(addressInput.value);
});

backBtn.addEventListener("click", () => {
  if (browserView.canGoBack()) {
    recordObservationEvent({
      type: "click",
      url: browserView.getURL() || "",
      target: { text: "Back", label: "back_button", role: "button" },
      meta: { source: "chrome_button" }
    });
    startProgress();
    browserView.goBack();
  }
});

forwardBtn.addEventListener("click", () => {
  if (browserView.canGoForward()) {
    recordObservationEvent({
      type: "click",
      url: browserView.getURL() || "",
      target: { text: "Forward", label: "forward_button", role: "button" },
      meta: { source: "chrome_button" }
    });
    startProgress();
    browserView.goForward();
  }
});

reloadBtn.addEventListener("click", () => {
  recordObservationEvent({
    type: "click",
    url: browserView.getURL() || "",
    target: { text: "Reload", label: "reload_button", role: "button" },
    meta: { source: "chrome_button" }
  });
  startProgress();
  browserView.reload();
});

minBtn.addEventListener("click", async () => {
  if (window.browserAPI && typeof window.browserAPI.minimizeWindow === "function") {
    await window.browserAPI.minimizeWindow();
  }
});

maxBtn.addEventListener("click", async () => {
  if (window.browserAPI && typeof window.browserAPI.toggleMaximizeWindow === "function") {
    await window.browserAPI.toggleMaximizeWindow();
  }
});

closeBtn.addEventListener("click", async () => {
  if (window.browserAPI && typeof window.browserAPI.closeWindow === "function") {
    await window.browserAPI.closeWindow();
  }
});

startTraceBtn.addEventListener("click", async () => {
  const url = browserView.getURL() || addressInput.value || DEFAULT_URL;
  try {
    const result = await window.browserAPI.layersStart({
      title: "Manual Trace",
      url
    });
    if (!result.ok) {
      appendLayerLog(`Start trace failed: ${result.error || "unknown error"}`);
      return;
    }
    activeSessionId = result.session_id || "";
    activeWorkflowId = "";
    syncLayerStateLabels();
    appendLayerLog(`Started trace ${activeSessionId}`);
  } catch (err) {
    appendLayerLog(`Start trace threw: ${err.message}`);
  }
});

stopTraceBtn.addEventListener("click", async () => {
  if (!activeSessionId) {
    appendLayerLog("Stop trace skipped: no active session.");
    return;
  }
  try {
    const result = await window.browserAPI.layersStop({
      session_id: activeSessionId
    });
    if (!result.ok) {
      appendLayerLog(`Stop trace failed: ${result.error || "unknown error"}`);
      return;
    }
    appendLayerLog(`Stopped trace ${activeSessionId} (${result.event_count || 0} events)`);
  } catch (err) {
    appendLayerLog(`Stop trace threw: ${err.message}`);
  }
});

compileTraceBtn.addEventListener("click", async () => {
  if (!activeSessionId) {
    appendLayerLog("Compile skipped: no session id.");
    return;
  }
  try {
    const result = await window.browserAPI.layersCompile({
      session_id: activeSessionId
    });
    if (!result.ok) {
      appendLayerLog(`Compile failed: ${result.error || "unknown error"}`);
      return;
    }
    activeWorkflowId = result.workflow_id || "";
    syncLayerStateLabels();
    appendLayerLog(`Compiled workflow ${activeWorkflowId} (${result.step_count || 0} steps)`);
  } catch (err) {
    appendLayerLog(`Compile threw: ${err.message}`);
  }
});

planWorkflowBtn.addEventListener("click", async () => {
  if (!activeWorkflowId) {
    appendLayerLog("Plan skipped: no workflow id.");
    return;
  }
  try {
    const result = await window.browserAPI.layersPlan({
      workflow_id: activeWorkflowId,
      inputs: {}
    });
    if (!result.ok) {
      appendLayerLog(`Plan failed: ${result.error || "unknown error"}`);
      return;
    }
    appendLayerLog(
      `Planned ${result.workflow_id}: ${result.step_count || 0} steps, unresolved inputs: ${(result.unresolved_inputs || []).length}`
    );
  } catch (err) {
    appendLayerLog(`Plan threw: ${err.message}`);
  }
});

browserView.addEventListener("did-start-loading", startProgress);
browserView.addEventListener("did-stop-loading", () => {
  finishProgress();
  syncChromeState();
});
browserView.addEventListener("did-fail-load", (_event, code, description) => {
  if (code === -3) {
    return;
  }
  finishProgress();
  tabTitle.textContent = "Load failed";
  siteBadge.textContent = "Error";
  if (description) {
    addressInput.value = `Failed: ${description}`;
  }
});
browserView.addEventListener("did-navigate", () => {
  syncChromeState();
  recordObservationEvent({
    type: "navigate",
    url: browserView.getURL() || "",
    target: {},
    meta: { source: "webview" }
  });
});
browserView.addEventListener("did-navigate-in-page", syncChromeState);
browserView.addEventListener("page-title-updated", syncChromeState);
browserView.addEventListener("dom-ready", () => {
  isWebviewReady = true;
  if (pendingUrl && browserView.getURL() !== pendingUrl) {
    browserView.setAttribute("src", pendingUrl);
  }
  pendingUrl = "";
});

window.addEventListener("DOMContentLoaded", async () => {
  syncLayerStateLabels();
  const homeUrl = await safeGetHomeUrl();
  startProgress();
  loadInWebview(homeUrl);
  syncChromeState();
});
