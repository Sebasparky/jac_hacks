// Legacy fallback renderer. The primary Electron frontend now boots from `main.jac`.

const viewport = document.getElementById("viewport");
const tabList = document.getElementById("tabList");
const newTabBtn = document.getElementById("newTabBtn");

const navForm = document.getElementById("navForm");
const addressInput = document.getElementById("addressInput");
const homeBtn = document.getElementById("homeBtn");
const backBtn = document.getElementById("backBtn");
const forwardBtn = document.getElementById("forwardBtn");
const reloadBtn = document.getElementById("reloadBtn");
const siteBadge = document.getElementById("siteBadge");
const progressBar = document.getElementById("progressBar");

const minBtn = document.getElementById("minBtn");
const maxBtn = document.getElementById("maxBtn");
const closeBtn = document.getElementById("closeBtn");
const goBtn = document.getElementById("goBtn");
const toggleLayersBtn = document.getElementById("toggleLayersBtn");

const startTraceBtn = document.getElementById("startTraceBtn");
const stopTraceBtn = document.getElementById("stopTraceBtn");
const compileTraceBtn = document.getElementById("compileTraceBtn");
const planWorkflowBtn = document.getElementById("planWorkflowBtn");
const sessionIdLabel = document.getElementById("sessionIdLabel");
const workflowIdLabel = document.getElementById("workflowIdLabel");
const layerLog = document.getElementById("layerLog");
const layerPanel = document.getElementById("layerPanel");
const bookmarkButtons = Array.from(document.querySelectorAll(".bookmark-item[data-nav-url]"));

let progressInterval = null;
let progressGuardTimeout = null;

const DEFAULT_URL = "https://example.com";
const SEARCH_URL = "https://duckduckgo.com/?q=";

let activeSessionId = "";
let activeWorkflowId = "";
let webviewPreloadUrl = "";
let homeUrlCache = "";
let homeUrlPromise = null;
let tabSeed = 0;
let chromeSyncFrame = 0;
let renderedActiveTabId = "";

const tabs = [];
let activeTabId = "";

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
  layerLog.textContent = `[${stamp}] ${message}\n${layerLog.textContent}`.slice(0, 7000);
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
 * R: Reflect the current page trust state in the omnibox badge.
 * M: Writes compact label text and a `data-state` token for CSS styling.
 * E: Safe no-op when the badge element is unavailable.
 */
function setSiteBadgeState(label, state = "secure") {
  if (!siteBadge) {
    return;
  }

  siteBadge.textContent = String(label || "").trim() || "Secure";
  siteBadge.dataset.state = state;
}

/**
 * R: Build a deterministic id for browser tabs.
 * M: Uses incrementing seed plus epoch milliseconds.
 * E: Ids are unique per renderer session.
 */
function nextTabId() {
  tabSeed += 1;
  return `tab_${Date.now()}_${tabSeed}`;
}

/**
 * R: Get current active tab object.
 * M: Looks up in-memory tab array by active tab id.
 * E: Returns null when no active tab exists.
 */
function getActiveTab() {
  return tabs.find((tab) => tab.id === activeTabId) || null;
}

/**
 * R: Get the active tab webview element.
 * M: Resolves active tab then returns its attached webview.
 * E: Returns null if active tab is missing.
 */
function getActiveWebview() {
  const tab = getActiveTab();
  return tab ? tab.webview : null;
}

/**
 * R: Resolve a tab object by id.
 * M: Performs linear lookup in tab registry.
 * E: Returns null when tab id does not exist.
 */
function getTabById(tabId) {
  return tabs.find((tab) => tab.id === tabId) || null;
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
 * R: Resolve home URL for initial/new-tab loads in a fault-tolerant way.
 * M: Reads from preload bridge if available, otherwise uses default URL.
 * E: Never throws.
 */
async function safeGetHomeUrl() {
  if (homeUrlCache) {
    return homeUrlCache;
  }

  if (homeUrlPromise) {
    return homeUrlPromise;
  }

  homeUrlPromise = (async () => {
    let resolvedHome = DEFAULT_URL;

    try {
      if (window.browserAPI && typeof window.browserAPI.getHomeUrl === "function") {
        const home = await window.browserAPI.getHomeUrl();
        if (home) {
          resolvedHome = home;
        }
      }
    } catch (_err) {
      // Ignore and use default.
    }

    homeUrlCache = resolvedHome;
    return resolvedHome;
  })();

  try {
    return await homeUrlPromise;
  } finally {
    homeUrlPromise = null;
  }
}

/**
 * R: Resolve preload URL used by in-page webview instrumentation.
 * M: Reads from IPC bridge and falls back to empty string when unavailable.
 * E: Empty return means webview instrumentation is disabled.
 */
async function safeGetWebviewPreloadUrl() {
  try {
    if (window.browserAPI && typeof window.browserAPI.getWebviewPreloadUrl === "function") {
      const value = await window.browserAPI.getWebviewPreloadUrl();
      return String(value || "");
    }
  } catch (_err) {
    // Ignore.
  }
  return "";
}

/**
 * R: Send one observation event to Jac layer API when recording is active.
 * M: Adds tab metadata and forwards event via preload bridge.
 * E: No-op when recording session is not active.
 */
async function recordObservationEvent(eventPayload) {
  if (!activeSessionId) {
    return;
  }

  const payload = {
    type: String(eventPayload.type || "unknown"),
    url: String(eventPayload.url || ""),
    target: eventPayload.target || {},
    value: "value" in eventPayload ? String(eventPayload.value || "") : "",
    meta: {
      ...(eventPayload.meta || {}),
      tab_id: (eventPayload.meta && eventPayload.meta.tab_id) || activeTabId || ""
    }
  };

  try {
    const result = await window.browserAPI.layersEvent({
      session_id: activeSessionId,
      event: payload
    });
    if (!result.ok) {
      appendLayerLog(`Observation append failed: ${result.error || "unknown error"}`);
      return;
    }
    if (result.deduped) {
      return;
    }
  } catch (err) {
    appendLayerLog(`Observation append threw: ${err.message}`);
  }
}

/**
 * R: Update the visible title text for one tab UI item.
 * M: Writes compact title text into tab label span and model state.
 * E: Empty titles map to `New Tab`.
 */
function setTabTitle(tab, titleText) {
  const finalTitle = String(titleText || "").trim() || "New Tab";
  tab.title = finalTitle;
  tab.titleNode.textContent = finalTitle;
  tab.tabNode.title = finalTitle;
}

/**
 * R: Coalesce repeated chrome refresh requests into a single animation frame.
 * M: Queues `syncChromeState` through `requestAnimationFrame` and drops duplicates.
 * E: If multiple webview events land together, only one sync runs for that frame.
 */
function scheduleChromeStateSync() {
  if (chromeSyncFrame) {
    return;
  }

  chromeSyncFrame = window.requestAnimationFrame(() => {
    chromeSyncFrame = 0;
    syncChromeState();
  });
}

/**
 * R: Keep the active tab visible without forcing a scroll on every activation.
 * M: Compares tab bounds against the current tab-strip viewport and only adjusts when clipped.
 * E: Missing tab nodes or scroll containers are treated as safe no-ops.
 */
function ensureTabVisible(tabNode) {
  if (!tabNode || !tabList) {
    return;
  }

  const tabLeft = tabNode.offsetLeft;
  const tabRight = tabLeft + tabNode.offsetWidth;
  const visibleLeft = tabList.scrollLeft;
  const visibleRight = visibleLeft + tabList.clientWidth;

  if (tabLeft < visibleLeft) {
    tabList.scrollLeft = Math.max(0, tabLeft - 16);
    return;
  }

  if (tabRight > visibleRight) {
    tabList.scrollLeft = Math.max(0, tabRight - tabList.clientWidth + 16);
  }
}

/**
 * R: Synchronize browser controls with the active tab state.
 * M: Reads active webview URL/title/history and updates chrome controls.
 * E: Disables nav controls when no active webview exists.
 */
function syncChromeState() {
  const webview = getActiveWebview();
  if (!webview) {
    addressInput.value = "";
    backBtn.disabled = true;
    forwardBtn.disabled = true;
    reloadBtn.disabled = true;
    setSiteBadgeState("Secure", "secure");
    return;
  }

  const currentUrl = webview.getURL();
  if (currentUrl) {
    addressInput.value = currentUrl;
    setSiteBadgeState(currentUrl.startsWith("https://") ? "Secure" : "Open", currentUrl.startsWith("https://") ? "secure" : "open");
  }

  const activeTab = getActiveTab();
  if (activeTab) {
    const title = webview.getTitle() || activeTab.title || "New Tab";
    setTabTitle(activeTab, title);
    activeTab.url = currentUrl || activeTab.url;
  }

  backBtn.disabled = !webview.canGoBack();
  forwardBtn.disabled = !webview.canGoForward();
  reloadBtn.disabled = false;
}

/**
 * R: Apply active/inactive classes across tab and webview nodes.
 * M: Loops all tabs and toggles `.active` on matching tab id.
 * E: If tab id is missing, all tabs become inactive.
 */
function renderActiveTabState(activeId) {
  if (renderedActiveTabId === activeId) {
    return;
  }

  const previousTab = renderedActiveTabId ? getTabById(renderedActiveTabId) : null;
  if (previousTab) {
    previousTab.tabNode.classList.remove("active");
    previousTab.webview.classList.remove("active");
  }

  const nextTab = activeId ? getTabById(activeId) : null;
  if (nextTab) {
    nextTab.tabNode.classList.add("active");
    nextTab.webview.classList.add("active");
  }

  renderedActiveTabId = activeId;
}

/**
 * R: Switch current focus to a specific tab.
 * M: Updates active id, re-renders active classes, and syncs controls.
 * E: Unknown tab id is ignored.
 */
function activateTab(tabId, emitObservation = true) {
  const nextTab = getTabById(tabId);
  if (!nextTab) {
    return;
  }

  const changed = activeTabId !== tabId;
  activeTabId = tabId;
  renderActiveTabState(activeTabId);
  ensureTabVisible(nextTab.tabNode);
  scheduleChromeStateSync();

  if (changed && emitObservation) {
    recordObservationEvent({
      type: "tab_switched",
      url: nextTab.webview.getURL() || nextTab.url || "",
      target: { role: "tab", text: nextTab.title || "New Tab", label: "tab_switch" },
      meta: { source: "chrome_tab", tab_id: nextTab.id }
    });
  }
}

/**
 * R: Close one tab and select an adjacent fallback tab.
 * M: Removes tab/webview nodes and updates active tab when needed.
 * E: Keeps at least one tab open by creating a default tab if necessary.
 */
function closeTab(tabId, emitObservation = true) {
  const index = tabs.findIndex((tab) => tab.id === tabId);
  if (index < 0) {
    return;
  }

  const tab = tabs[index];
  const wasActive = tab.id === activeTabId;
  const finalUrl = tab.webview.getURL() || tab.url || "";

  tab.webview.remove();
  tab.tabNode.remove();
  tabs.splice(index, 1);

  if (emitObservation) {
    recordObservationEvent({
      type: "tab_closed",
      url: finalUrl,
      target: { role: "tab", text: tab.title || "New Tab", label: "tab_close" },
      meta: { source: "chrome_tab", tab_id: tab.id }
    });
  }

  if (!tabs.length) {
    addTab(DEFAULT_URL, { activate: true, emitObservation: false });
    return;
  }

  if (wasActive) {
    const fallbackIndex = Math.max(0, index - 1);
    activateTab(tabs[fallbackIndex].id, false);
  }
}

/**
 * R: Register event handlers for one tab webview.
 * M: Wires load/navigation/title/ipc events and routes observation payloads.
 * E: All handlers are safe no-ops when tab is not active.
 */
function attachWebviewEvents(tab) {
  const webview = tab.webview;

  webview.addEventListener("did-start-loading", () => {
    tab.tabNode.classList.add("loading");
    if (activeTabId === tab.id) {
      startProgress();
    }
  });

  webview.addEventListener("did-stop-loading", () => {
    tab.tabNode.classList.remove("loading");
    if (activeTabId === tab.id) {
      finishProgress();
      scheduleChromeStateSync();
    }
  });

  webview.addEventListener("did-fail-load", (_event, code, description) => {
    if (code === -3) {
      return;
    }

    tab.tabNode.classList.remove("loading");
    if (activeTabId === tab.id) {
      finishProgress();
      setSiteBadgeState("Error", "error");
      if (description) {
        addressInput.value = `Failed: ${description}`;
      }
    }
  });

  webview.addEventListener("did-navigate", () => {
    tab.url = webview.getURL() || tab.url;
    if (activeTabId === tab.id) {
      scheduleChromeStateSync();
    }

    recordObservationEvent({
      type: "navigate",
      url: webview.getURL() || "",
      target: { role: "document", label: "page_navigation", text: tab.title || "" },
      meta: { source: "webview", tab_id: tab.id }
    });
  });

  webview.addEventListener("did-navigate-in-page", () => {
    tab.url = webview.getURL() || tab.url;
    if (activeTabId === tab.id) {
      scheduleChromeStateSync();
    }
  });

  webview.addEventListener("page-title-updated", () => {
    setTabTitle(tab, webview.getTitle() || "New Tab");
    if (activeTabId === tab.id) {
      scheduleChromeStateSync();
    }
  });

  webview.addEventListener("dom-ready", () => {
    if (activeTabId === tab.id) {
      scheduleChromeStateSync();
    }
  });

  webview.addEventListener("ipc-message", (event) => {
    if (event.channel !== "observation:event") {
      return;
    }

    const payload = (event.args && event.args[0]) || {};
    if (!payload || typeof payload !== "object") {
      return;
    }

    recordObservationEvent({
      type: payload.type || "unknown",
      url: payload.url || webview.getURL() || tab.url || "",
      target: payload.target || {},
      value: "value" in payload ? payload.value : "",
      meta: {
        ...(payload.meta || {}),
        source: (payload.meta && payload.meta.source) || "page",
        tab_id: tab.id
      }
    });
  });
}

/**
 * R: Build one tab model + DOM nodes and register them into app state.
 * M: Creates tab item, webview, event hooks, then optionally activates tab.
 * E: Tab opens with fallback URL when supplied URL is empty.
 */
function addTab(initialUrl, options = {}) {
  const { activate = true, emitObservation = true } = options;
  const url = String(initialUrl || "").trim() || DEFAULT_URL;

  const tab = {
    id: nextTabId(),
    title: "New Tab",
    url,
    tabNode: document.createElement("div"),
    titleNode: document.createElement("span"),
    closeNode: document.createElement("button"),
    webview: document.createElement("webview")
  };

  tab.tabNode.className = "tab";
  tab.tabNode.dataset.tabId = tab.id;

  const dotNode = document.createElement("span");
  dotNode.className = "tab-dot";

  tab.titleNode.className = "tab-title";
  tab.titleNode.textContent = "New Tab";
  tab.tabNode.title = "New Tab";

  tab.closeNode.className = "tab-close";
  tab.closeNode.type = "button";
  tab.closeNode.title = "Close Tab";
  tab.closeNode.textContent = "\u2715";

  tab.tabNode.appendChild(dotNode);
  tab.tabNode.appendChild(tab.titleNode);
  tab.tabNode.appendChild(tab.closeNode);

  tab.webview.className = "browser-view";
  tab.webview.dataset.tabId = tab.id;
  tab.webview.setAttribute("allowpopups", "");
  tab.webview.setAttribute("src", url);
  if (webviewPreloadUrl) {
    tab.webview.setAttribute("preload", webviewPreloadUrl);
  }

  tab.tabNode.addEventListener("click", () => {
    activateTab(tab.id, true);
  });

  tab.closeNode.addEventListener("click", (event) => {
    event.stopPropagation();
    closeTab(tab.id, true);
  });

  attachWebviewEvents(tab);

  tabs.push(tab);
  tabList.appendChild(tab.tabNode);
  viewport.appendChild(tab.webview);

  if (activate) {
    activateTab(tab.id, false);
  }

  if (emitObservation) {
    recordObservationEvent({
      type: "tab_created",
      url,
      target: { role: "tab", text: "New Tab", label: "new_tab" },
      meta: { source: "chrome_tab", tab_id: tab.id }
    });
  }

  return tab;
}

/**
 * R: Load a URL into the active tab.
 * M: Updates tab model URL and sets active webview `src`.
 * E: Ignores empty URLs or missing active tab.
 */
function loadInActiveTab(url) {
  const webview = getActiveWebview();
  const tab = getActiveTab();
  if (!webview || !tab || !url || typeof url !== "string") {
    return;
  }

  tab.url = url;
  webview.setAttribute("src", url);
}

/**
 * R: Navigate using Jac-normalized input from omnibox.
 * M: Normalizes entered text, records event, then loads active tab URL.
 * E: Falls back to current URL/default URL if normalization is empty.
 */
async function navigateFromInput(rawValue) {
  const webview = getActiveWebview();
  if (!webview) {
    return;
  }

  try {
    startProgress();
    const fallback = webview.getURL() || DEFAULT_URL;
    const normalized = await safeNormalizeUrl(rawValue);

    await recordObservationEvent({
      type: "input",
      url: fallback,
      target: { label: "address_bar", name: "address", role: "textbox", type: "text" },
      value: String(rawValue || ""),
      meta: { source: "omnibox", tab_id: activeTabId }
    });

    loadInActiveTab(normalized || fallback);
  } catch (_err) {
    finishProgress();
    appendLayerLog("Navigation failed for active tab.");
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

homeBtn.addEventListener("click", async () => {
  const webview = getActiveWebview();
  if (!webview) {
    return;
  }

  const homeUrl = await safeGetHomeUrl();
  recordObservationEvent({
    type: "click",
    url: webview.getURL() || "",
    target: { text: "Home", label: "home_button", role: "button" },
    meta: { source: "chrome_button", tab_id: activeTabId, request_url: homeUrl }
  });

  startProgress();
  loadInActiveTab(homeUrl);
});

backBtn.addEventListener("click", () => {
  const webview = getActiveWebview();
  if (!webview || !webview.canGoBack()) {
    return;
  }

  recordObservationEvent({
    type: "click",
    url: webview.getURL() || "",
    target: { text: "Back", label: "back_button", role: "button" },
    meta: { source: "chrome_button", tab_id: activeTabId }
  });

  startProgress();
  webview.goBack();
});

forwardBtn.addEventListener("click", () => {
  const webview = getActiveWebview();
  if (!webview || !webview.canGoForward()) {
    return;
  }

  recordObservationEvent({
    type: "click",
    url: webview.getURL() || "",
    target: { text: "Forward", label: "forward_button", role: "button" },
    meta: { source: "chrome_button", tab_id: activeTabId }
  });

  startProgress();
  webview.goForward();
});

reloadBtn.addEventListener("click", () => {
  const webview = getActiveWebview();
  if (!webview) {
    return;
  }

  recordObservationEvent({
    type: "click",
    url: webview.getURL() || "",
    target: { text: "Reload", label: "reload_button", role: "button" },
    meta: { source: "chrome_button", tab_id: activeTabId }
  });

  startProgress();
  webview.reload();
});

newTabBtn.addEventListener("click", async () => {
  const homeUrl = await safeGetHomeUrl();
  addTab(homeUrl, { activate: true, emitObservation: true });
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

toggleLayersBtn.addEventListener("click", () => {
  if (!layerPanel) {
    return;
  }

  const collapsed = layerPanel.classList.toggle("collapsed");
  toggleLayersBtn.setAttribute("aria-pressed", String(!collapsed));
});

for (const bookmarkBtn of bookmarkButtons) {
  bookmarkBtn.addEventListener("click", () => {
    const url = bookmarkBtn.dataset.navUrl;
    const webview = getActiveWebview();
    if (!url || !webview) {
      return;
    }

    recordObservationEvent({
      type: "click",
      url: webview.getURL() || "",
      target: { text: bookmarkBtn.textContent.trim() || "Shortcut", label: "bookmark_shortcut", role: "link" },
      meta: { source: "bookmark_bar", tab_id: activeTabId, request_url: url }
    });

    startProgress();
    loadInActiveTab(url);
  });
}

startTraceBtn.addEventListener("click", async () => {
  const webview = getActiveWebview();
  const url = (webview && webview.getURL()) || addressInput.value || DEFAULT_URL;

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
    const result = await window.browserAPI.layersStop({ session_id: activeSessionId });
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
    const result = await window.browserAPI.layersCompile({ session_id: activeSessionId });
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
      `Planned ${result.workflow_id}: ${result.step_count || 0} steps, unresolved: ${(result.unresolved_inputs || []).length}`
    );
  } catch (err) {
    appendLayerLog(`Plan threw: ${err.message}`);
  }
});

window.addEventListener("DOMContentLoaded", async () => {
  syncLayerStateLabels();

  webviewPreloadUrl = await safeGetWebviewPreloadUrl();
  if (!webviewPreloadUrl) {
    appendLayerLog("Warning: webview preload not resolved; in-page telemetry disabled.");
  }

  const homeUrl = await safeGetHomeUrl();
  addTab(homeUrl, { activate: true, emitObservation: false });
  scheduleChromeStateSync();
});
