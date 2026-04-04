"""Jac-authored browser shell runtime for the Electron renderer."""

cl {
    """R: Boot the browser shell behavior against the rendered Jac DOM.
    M: Queries shell nodes, wires browser controls, and drives webview tabs through the Electron bridge.
    E: Missing bridge methods degrade gracefully and leave a static shell instead of crashing.
    """
    def:pub bootstrapBrowserShell() -> any {
        shellRoot = document.querySelector(".app-shell");
        if not shellRoot {
            return lambda {};
        }
        if shellRoot.getAttribute("data-jac-booted") == "true" {
            return lambda {};
        }
        shellRoot.setAttribute("data-jac-booted", "true");

        DEFAULT_URL = "https://example.com";
        SEARCH_URL = "https://duckduckgo.com/?q=";

        state = {
            "viewport": document.getElementById("viewport"),
            "tabList": document.getElementById("tabList"),
            "newTabBtn": document.getElementById("newTabBtn"),
            "navForm": document.getElementById("navForm"),
            "addressInput": document.getElementById("addressInput"),
            "homeBtn": document.getElementById("homeBtn"),
            "backBtn": document.getElementById("backBtn"),
            "forwardBtn": document.getElementById("forwardBtn"),
            "reloadBtn": document.getElementById("reloadBtn"),
            "siteBadge": document.getElementById("siteBadge"),
            "progressBar": document.getElementById("progressBar"),
            "minBtn": document.getElementById("minBtn"),
            "maxBtn": document.getElementById("maxBtn"),
            "closeBtn": document.getElementById("closeBtn"),
            "goBtn": document.getElementById("goBtn"),
            "toggleLayersBtn": document.getElementById("toggleLayersBtn"),
            "startTraceBtn": document.getElementById("startTraceBtn"),
            "stopTraceBtn": document.getElementById("stopTraceBtn"),
            "compileTraceBtn": document.getElementById("compileTraceBtn"),
            "planWorkflowBtn": document.getElementById("planWorkflowBtn"),
            "sessionIdLabel": document.getElementById("sessionIdLabel"),
            "workflowIdLabel": document.getElementById("workflowIdLabel"),
            "layerLog": document.getElementById("layerLog"),
            "layerPanel": document.getElementById("layerPanel"),
            "progressInterval": None,
            "progressGuardTimeout": None,
            "activeSessionId": "",
            "activeWorkflowId": "",
            "webviewPreloadUrl": "",
            "homeUrlCache": "",
            "homeUrlPromise": None,
            "tabSeed": 0,
            "chromeSyncFrame": None,
            "renderedActiveTabId": "",
            "tabs": [],
            "activeTabId": ""
        };

        if not state["viewport"] or not state["tabList"] or not state["navForm"] {
            return lambda {};
        }

        def browserAPI() -> any {
            return window["browserAPI"];
        }

        def objectValue(record: any, key: any, fallback: any = None) -> any {
            if not record or typeof(record) != "object" {
                return fallback;
            }
            value = record[key];
            if typeof(value) == "undefined" or value == None {
                return fallback;
            }
            return value;
        }

        def setProgress(value: any) -> None {
            clamped = value;
            if clamped < 0 {
                clamped = 0;
            }
            if clamped > 100 {
                clamped = 100;
            }
            if state["progressBar"] {
                state["progressBar"].style.width = str(clamped) + "%";
            }
        }

        def finishProgress() -> None {
            if state["progressInterval"] {
                clearInterval(state["progressInterval"]);
                state["progressInterval"] = None;
            }
            if state["progressGuardTimeout"] {
                clearTimeout(state["progressGuardTimeout"]);
                state["progressGuardTimeout"] = None;
            }
            setProgress(100);
            setTimeout(lambda { setProgress(0); }, 220);
        }

        def startProgress() -> None {
            if state["progressInterval"] {
                return;
            }

            setProgress(8);
            state["progressInterval"] = setInterval(lambda {
                current = 0;
                if state["progressBar"] and state["progressBar"].style.width {
                    current = Number.parseFloat(state["progressBar"].style.width);
                }
                if current < 85 {
                    setProgress(current + 6);
                }
            }, 120);

            if state["progressGuardTimeout"] {
                clearTimeout(state["progressGuardTimeout"]);
            }
            state["progressGuardTimeout"] = setTimeout(lambda { finishProgress(); }, 15000);
        }

        def appendLayerLog(message: any) -> None {
            if not state["layerLog"] {
                return;
            }
            stamp = Reflect.construct(Date, []).toLocaleTimeString();
            nextText = "[" + stamp + "] " + str(message) + "\n" + str(state["layerLog"].textContent or "");
            state["layerLog"].textContent = nextText.slice(0, 7000);
        }

        def syncLayerStateLabels() -> None {
            if state["sessionIdLabel"] {
                state["sessionIdLabel"].textContent = state["activeSessionId"] or "none";
            }
            if state["workflowIdLabel"] {
                state["workflowIdLabel"].textContent = state["activeWorkflowId"] or "none";
            }
        }

        def setSiteBadgeState(label: any, stateKey: any = "secure") -> None {
            if not state["siteBadge"] {
                return;
            }
            state["siteBadge"].textContent = str(label or "").trim() or "Secure";
            state["siteBadge"].dataset.state = str(stateKey or "secure");
        }

        def nextTabId() -> str {
            state["tabSeed"] = state["tabSeed"] + 1;
            return "tab_" + str(Date.now()) + "_" + str(state["tabSeed"]);
        }

        def getTabById(tabId: any) -> any {
            for tab in state["tabs"] {
                if tab["id"] == tabId {
                    return tab;
                }
            }
            return None;
        }

        def getActiveTab() -> any {
            return getTabById(state["activeTabId"]);
        }

        def getActiveWebview() -> any {
            tab = getActiveTab();
            if tab {
                return tab["webview"];
            }
            return None;
        }

        def normalizeClientSide(rawValue: any) -> str {
            cleaned = str(rawValue or "").trim();
            if not cleaned {
                return DEFAULT_URL;
            }

            lowered = cleaned.toLowerCase();
            if lowered.startsWith("http://") or lowered.startsWith("https://") {
                return cleaned;
            }

            looksLikeDomain = cleaned.includes(".") and not cleaned.includes(" ");
            if looksLikeDomain {
                return "https://" + cleaned;
            }

            return SEARCH_URL + encodeURIComponent(cleaned);
        }

        async def safeNormalizeUrl(rawValue: any) -> str {
            api = browserAPI();
            if api and api.normalizeUrl {
                try {
                    viaJac = await api.normalizeUrl(rawValue);
                    if viaJac {
                        return viaJac;
                    }
                } except Exception {
                }
            }
            return normalizeClientSide(rawValue);
        }

        async def safeGetHomeUrl() -> str {
            if state["homeUrlCache"] {
                return state["homeUrlCache"];
            }
            if state["homeUrlPromise"] {
                return await state["homeUrlPromise"];
            }

            async def resolveHomeUrl() -> str {
                resolvedHome = DEFAULT_URL;
                api = browserAPI();
                if api and api.getHomeUrl {
                    try {
                        home = await api.getHomeUrl();
                        if home {
                            resolvedHome = home;
                        }
                    } except Exception {
                    }
                }
                state["homeUrlCache"] = resolvedHome;
                return resolvedHome;
            }

            state["homeUrlPromise"] = resolveHomeUrl();
            try {
                return await state["homeUrlPromise"];
            } finally {
                state["homeUrlPromise"] = None;
            }
        }

        async def safeGetWebviewPreloadUrl() -> str {
            api = browserAPI();
            if api and api.getWebviewPreloadUrl {
                try {
                    value = await api.getWebviewPreloadUrl();
                    return str(value or "");
                } except Exception {
                }
            }
            return "";
        }

        async def recordObservationEvent(eventPayload: any) -> None {
            if not state["activeSessionId"] {
                return;
            }

            api = browserAPI();
            if not api or not api.layersEvent {
                return;
            }

            payload = {
                "type": str(eventPayload["type"] or "unknown"),
                "url": str(eventPayload["url"] or ""),
                "target": eventPayload["target"] or {},
                "value": str(eventPayload["value"] or "") if "value" in eventPayload else "",
                "meta": eventPayload["meta"] or {}
            };
            if not objectValue(payload["meta"], "tab_id", "") {
                payload["meta"]["tab_id"] = state["activeTabId"] or "";
            }

            try {
                result = await api.layersEvent({
                    "session_id": state["activeSessionId"],
                    "event": payload
                });
                if result and objectValue(result, "ok", True) == False {
                    appendLayerLog("Observation append failed: " + str(objectValue(result, "error", "unknown error")));
                }
            } except Exception as err {
                appendLayerLog("Observation append threw: " + str(err.message or err));
            }
        }

        def setTabTitle(tab: any, titleText: any) -> None {
            finalTitle = str(titleText or "").trim() or "New Tab";
            tab["title"] = finalTitle;
            tab["titleNode"].textContent = finalTitle;
            tab["tabNode"].title = finalTitle;
        }

        def scheduleChromeStateSync() -> None {
            if state["chromeSyncFrame"] {
                return;
            }
            state["chromeSyncFrame"] = requestAnimationFrame(lambda {
                state["chromeSyncFrame"] = None;
                syncChromeState();
            });
        }

        def ensureTabVisible(tabNode: any) -> None {
            if not tabNode or not state["tabList"] {
                return;
            }

            tabLeft = tabNode.offsetLeft;
            tabRight = tabLeft + tabNode.offsetWidth;
            visibleLeft = state["tabList"].scrollLeft;
            visibleRight = visibleLeft + state["tabList"].clientWidth;

            if tabLeft < visibleLeft {
                state["tabList"].scrollLeft = Math.max(0, tabLeft - 16);
                return;
            }

            if tabRight > visibleRight {
                state["tabList"].scrollLeft = Math.max(0, tabRight - state["tabList"].clientWidth + 16);
            }
        }

        def syncChromeState() -> None {
            webview = getActiveWebview();
            if not webview {
                if state["addressInput"] {
                    state["addressInput"].value = "";
                }
                if state["backBtn"] {
                    state["backBtn"].disabled = True;
                }
                if state["forwardBtn"] {
                    state["forwardBtn"].disabled = True;
                }
                if state["reloadBtn"] {
                    state["reloadBtn"].disabled = True;
                }
                setSiteBadgeState("Secure", "secure");
                return;
            }

            currentUrl = webview.getURL();
            if currentUrl and state["addressInput"] {
                state["addressInput"].value = currentUrl;
            }
            if currentUrl {
                if currentUrl.startsWith("https://") {
                    setSiteBadgeState("Secure", "secure");
                } else {
                    setSiteBadgeState("Open", "open");
                }
            }

            activeTab = getActiveTab();
            if activeTab {
                title = webview.getTitle() or activeTab["title"] or "New Tab";
                setTabTitle(activeTab, title);
                activeTab["url"] = currentUrl or activeTab["url"];
            }

            if state["backBtn"] {
                state["backBtn"].disabled = not webview.canGoBack();
            }
            if state["forwardBtn"] {
                state["forwardBtn"].disabled = not webview.canGoForward();
            }
            if state["reloadBtn"] {
                state["reloadBtn"].disabled = False;
            }
        }

        def renderActiveTabState(activeId: any) -> None {
            if state["renderedActiveTabId"] == activeId {
                return;
            }

            previousTab = None;
            if state["renderedActiveTabId"] {
                previousTab = getTabById(state["renderedActiveTabId"]);
            }
            if previousTab {
                previousTab["tabNode"].classList.remove("active");
                previousTab["webview"].classList.remove("active");
            }

            nextTab = None;
            if activeId {
                nextTab = getTabById(activeId);
            }
            if nextTab {
                nextTab["tabNode"].classList.add("active");
                nextTab["webview"].classList.add("active");
            }

            state["renderedActiveTabId"] = activeId;
        }

        def activateTab(tabId: any, emitObservation: any = True) -> None {
            nextTab = getTabById(tabId);
            if not nextTab {
                return;
            }

            changed = state["activeTabId"] != tabId;
            state["activeTabId"] = tabId;
            renderActiveTabState(state["activeTabId"]);
            ensureTabVisible(nextTab["tabNode"]);
            scheduleChromeStateSync();

            if changed and emitObservation {
                recordObservationEvent({
                    "type": "tab_switched",
                    "url": nextTab["webview"].getURL() or nextTab["url"] or "",
                    "target": {"role": "tab", "text": nextTab["title"] or "New Tab", "label": "tab_switch"},
                    "meta": {"source": "chrome_tab", "tab_id": nextTab["id"]}
                });
            }
        }

        def closeTab(tabId: any, emitObservation: any = True) -> None {
            index = -1;
            position = 0;
            for tab in state["tabs"] {
                if tab["id"] == tabId {
                    index = position;
                    break;
                }
                position = position + 1;
            }
            if index < 0 {
                return;
            }

            tab = state["tabs"][index];
            wasActive = tab["id"] == state["activeTabId"];
            finalUrl = tab["webview"].getURL() or tab["url"] or "";

            tab["webview"].remove();
            tab["tabNode"].remove();
            state["tabs"].splice(index, 1);

            if emitObservation {
                recordObservationEvent({
                    "type": "tab_closed",
                    "url": finalUrl,
                    "target": {"role": "tab", "text": tab["title"] or "New Tab", "label": "tab_close"},
                    "meta": {"source": "chrome_tab", "tab_id": tab["id"]}
                });
            }

            if len(state["tabs"]) == 0 {
                addTab(DEFAULT_URL, {"activate": True, "emitObservation": False});
                return;
            }

            if wasActive {
                fallbackIndex = index - 1;
                if fallbackIndex < 0 {
                    fallbackIndex = 0;
                }
                activateTab(state["tabs"][fallbackIndex]["id"], False);
            }
        }

        def attachWebviewEvents(tab: any) -> None {
            webview = tab["webview"];

            webview.addEventListener("did-start-loading", lambda {
                tab["tabNode"].classList.add("loading");
                if state["activeTabId"] == tab["id"] {
                    startProgress();
                }
            });

            webview.addEventListener("did-stop-loading", lambda {
                tab["tabNode"].classList.remove("loading");
                if state["activeTabId"] == tab["id"] {
                    finishProgress();
                    scheduleChromeStateSync();
                }
            });

            webview.addEventListener("did-fail-load", lambda event, code, description {
                if code == -3 {
                    return;
                }
                tab["tabNode"].classList.remove("loading");
                if state["activeTabId"] == tab["id"] {
                    finishProgress();
                    setSiteBadgeState("Error", "error");
                    if description and state["addressInput"] {
                        state["addressInput"].value = "Failed: " + str(description);
                    }
                }
            });

            webview.addEventListener("did-navigate", lambda {
                tab["url"] = webview.getURL() or tab["url"];
                if state["activeTabId"] == tab["id"] {
                    scheduleChromeStateSync();
                }
                recordObservationEvent({
                    "type": "navigate",
                    "url": webview.getURL() or "",
                    "target": {"role": "document", "label": "page_navigation", "text": tab["title"] or ""},
                    "meta": {"source": "webview", "tab_id": tab["id"]}
                });
            });

            webview.addEventListener("did-navigate-in-page", lambda {
                tab["url"] = webview.getURL() or tab["url"];
                if state["activeTabId"] == tab["id"] {
                    scheduleChromeStateSync();
                }
            });

            webview.addEventListener("page-title-updated", lambda {
                setTabTitle(tab, webview.getTitle() or "New Tab");
                if state["activeTabId"] == tab["id"] {
                    scheduleChromeStateSync();
                }
            });

            webview.addEventListener("dom-ready", lambda {
                if state["activeTabId"] == tab["id"] {
                    scheduleChromeStateSync();
                }
            });

            webview.addEventListener("ipc-message", lambda event {
                if event.channel != "observation:event" {
                    return;
                }
                payload = {};
                if event.args and len(event.args) > 0 {
                    payload = event.args[0] or {};
                }
                if not payload or typeof(payload) != "object" {
                    return;
                }
                meta = payload["meta"] or {};
                if not objectValue(meta, "source", "") {
                    meta["source"] = "page";
                }
                meta["tab_id"] = tab["id"];
                recordObservationEvent({
                    "type": payload["type"] or "unknown",
                    "url": payload["url"] or webview.getURL() or tab["url"] or "",
                    "target": payload["target"] or {},
                    "value": payload["value"] if "value" in payload else "",
                    "meta": meta
                });
            });
        }

        def addTab(initialUrl: any, options: any = {}) -> any {
            activateNew = objectValue(options, "activate", True);
            emitObservation = objectValue(options, "emitObservation", True);
            url = str(initialUrl or "").trim() or DEFAULT_URL;

            tab = {
                "id": nextTabId(),
                "title": "New Tab",
                "url": url,
                "tabNode": document.createElement("div"),
                "titleNode": document.createElement("span"),
                "closeNode": document.createElement("button"),
                "webview": document.createElement("webview")
            };

            tab["tabNode"].className = "tab";
            tab["tabNode"].dataset.tabId = tab["id"];

            dotNode = document.createElement("span");
            dotNode.className = "tab-dot";

            tab["titleNode"].className = "tab-title";
            tab["titleNode"].textContent = "New Tab";
            tab["tabNode"].title = "New Tab";

            tab["closeNode"].className = "tab-close";
            tab["closeNode"].type = "button";
            tab["closeNode"].title = "Close Tab";
            tab["closeNode"].textContent = "X";

            tab["tabNode"].appendChild(dotNode);
            tab["tabNode"].appendChild(tab["titleNode"]);
            tab["tabNode"].appendChild(tab["closeNode"]);

            tab["webview"].className = "browser-view";
            tab["webview"].dataset.tabId = tab["id"];
            tab["webview"].setAttribute("allowpopups", "");
            tab["webview"].setAttribute("src", url);
            if state["webviewPreloadUrl"] {
                tab["webview"].setAttribute("preload", state["webviewPreloadUrl"]);
            }

            tab["tabNode"].addEventListener("click", lambda {
                activateTab(tab["id"], True);
            });

            tab["closeNode"].addEventListener("click", lambda event {
                event.stopPropagation();
                closeTab(tab["id"], True);
            });

            attachWebviewEvents(tab);

            state["tabs"].push(tab);
            state["tabList"].appendChild(tab["tabNode"]);
            state["viewport"].appendChild(tab["webview"]);

            if activateNew {
                activateTab(tab["id"], False);
            }

            if emitObservation {
                recordObservationEvent({
                    "type": "tab_created",
                    "url": url,
                    "target": {"role": "tab", "text": "New Tab", "label": "new_tab"},
                    "meta": {"source": "chrome_tab", "tab_id": tab["id"]}
                });
            }

            return tab;
        }

        def loadInActiveTab(url: any) -> None {
            webview = getActiveWebview();
            tab = getActiveTab();
            if not webview or not tab or not url {
                return;
            }
            tab["url"] = url;
            webview.setAttribute("src", url);
        }

        async def navigateFromInput(rawValue: any) -> None {
            webview = getActiveWebview();
            if not webview {
                return;
            }

            try {
                startProgress();
                fallback = webview.getURL() or DEFAULT_URL;
                normalized = await safeNormalizeUrl(rawValue);
                recordObservationEvent({
                    "type": "input",
                    "url": fallback,
                    "target": {"label": "address_bar", "name": "address", "role": "textbox", "type": "text"},
                    "value": str(rawValue or ""),
                    "meta": {"source": "omnibox", "tab_id": state["activeTabId"]}
                });
                loadInActiveTab(normalized or fallback);
            } except Exception {
                finishProgress();
                appendLayerLog("Navigation failed for active tab.");
            }
        }

        state["navForm"].addEventListener("submit", lambda event {
            event.preventDefault();
            navigateFromInput(state["addressInput"].value);
        });

        state["goBtn"].addEventListener("click", lambda event {
            event.preventDefault();
            navigateFromInput(state["addressInput"].value);
        });

        state["homeBtn"].addEventListener("click", lambda {
            async def handle {
                webview = getActiveWebview();
                if not webview {
                    return;
                }
                homeUrl = await safeGetHomeUrl();
                recordObservationEvent({
                    "type": "click",
                    "url": webview.getURL() or "",
                    "target": {"text": "Home", "label": "home_button", "role": "button"},
                    "meta": {"source": "chrome_button", "tab_id": state["activeTabId"], "request_url": homeUrl}
                });
                startProgress();
                loadInActiveTab(homeUrl);
            }
            handle();
        });

        state["backBtn"].addEventListener("click", lambda {
            webview = getActiveWebview();
            if not webview or not webview.canGoBack() {
                return;
            }
            recordObservationEvent({
                "type": "click",
                "url": webview.getURL() or "",
                "target": {"text": "Back", "label": "back_button", "role": "button"},
                "meta": {"source": "chrome_button", "tab_id": state["activeTabId"]}
            });
            startProgress();
            webview.goBack();
        });

        state["forwardBtn"].addEventListener("click", lambda {
            webview = getActiveWebview();
            if not webview or not webview.canGoForward() {
                return;
            }
            recordObservationEvent({
                "type": "click",
                "url": webview.getURL() or "",
                "target": {"text": "Forward", "label": "forward_button", "role": "button"},
                "meta": {"source": "chrome_button", "tab_id": state["activeTabId"]}
            });
            startProgress();
            webview.goForward();
        });

        state["reloadBtn"].addEventListener("click", lambda {
            webview = getActiveWebview();
            if not webview {
                return;
            }
            recordObservationEvent({
                "type": "click",
                "url": webview.getURL() or "",
                "target": {"text": "Reload", "label": "reload_button", "role": "button"},
                "meta": {"source": "chrome_button", "tab_id": state["activeTabId"]}
            });
            startProgress();
            webview.reload();
        });

        state["newTabBtn"].addEventListener("click", lambda {
            async def openTab {
                homeUrl = await safeGetHomeUrl();
                addTab(homeUrl, {"activate": True, "emitObservation": True});
            }
            openTab();
        });

        state["minBtn"].addEventListener("click", lambda {
            async def handle {
                api = browserAPI();
                if api and api.minimizeWindow {
                    await api.minimizeWindow();
                }
            }
            handle();
        });

        state["maxBtn"].addEventListener("click", lambda {
            async def handle {
                api = browserAPI();
                if api and api.toggleMaximizeWindow {
                    await api.toggleMaximizeWindow();
                }
            }
            handle();
        });

        state["closeBtn"].addEventListener("click", lambda {
            async def handle {
                api = browserAPI();
                if api and api.closeWindow {
                    await api.closeWindow();
                }
            }
            handle();
        });

        state["toggleLayersBtn"].addEventListener("click", lambda {
            if not state["layerPanel"] {
                return;
            }
            collapsed = state["layerPanel"].classList.toggle("collapsed");
            state["toggleLayersBtn"].setAttribute("aria-pressed", str(not collapsed));
        });

        bookmarkButtons = document.querySelectorAll(".bookmark-item[data-nav-url]");
        for bookmarkButton in bookmarkButtons {
            bookmarkButton.addEventListener("click", lambda event {
                button = event.currentTarget;
                url = button.dataset.navUrl or "";
                webview = getActiveWebview();
                if not url or not webview {
                    return;
                }
                recordObservationEvent({
                    "type": "click",
                    "url": webview.getURL() or "",
                    "target": {"text": str(button.textContent or "").trim() or "Shortcut", "label": "bookmark_shortcut", "role": "link"},
                    "meta": {"source": "bookmark_bar", "tab_id": state["activeTabId"], "request_url": url}
                });
                startProgress();
                loadInActiveTab(url);
            });
        }

        state["startTraceBtn"].addEventListener("click", lambda {
            async def handle {
                webview = getActiveWebview();
                url = DEFAULT_URL;
                if webview and webview.getURL() {
                    url = webview.getURL();
                } elif state["addressInput"] and state["addressInput"].value {
                    url = state["addressInput"].value;
                }

                api = browserAPI();
                if not api or not api.layersStart {
                    appendLayerLog("Start trace failed: browser bridge unavailable.");
                    return;
                }

                try {
                    result = await api.layersStart({"title": "Manual Trace", "url": url});
                    if not result or objectValue(result, "ok", True) == False {
                        appendLayerLog("Start trace failed: " + str(objectValue(result, "error", "unknown error")));
                        return;
                    }
                    state["activeSessionId"] = objectValue(result, "session_id", "") or "";
                    state["activeWorkflowId"] = "";
                    syncLayerStateLabels();
                    appendLayerLog("Started trace " + state["activeSessionId"]);
                } except Exception as err {
                    appendLayerLog("Start trace threw: " + str(err.message or err));
                }
            }
            handle();
        });

        state["stopTraceBtn"].addEventListener("click", lambda {
            async def handle {
                if not state["activeSessionId"] {
                    appendLayerLog("Stop trace skipped: no active session.");
                    return;
                }
                api = browserAPI();
                if not api or not api.layersStop {
                    appendLayerLog("Stop trace failed: browser bridge unavailable.");
                    return;
                }
                try {
                    result = await api.layersStop({"session_id": state["activeSessionId"]});
                    if not result or objectValue(result, "ok", True) == False {
                        appendLayerLog("Stop trace failed: " + str(objectValue(result, "error", "unknown error")));
                        return;
                    }
                    appendLayerLog("Stopped trace " + state["activeSessionId"] + " (" + str(objectValue(result, "event_count", 0)) + " events)");
                } except Exception as err {
                    appendLayerLog("Stop trace threw: " + str(err.message or err));
                }
            }
            handle();
        });

        state["compileTraceBtn"].addEventListener("click", lambda {
            async def handle {
                if not state["activeSessionId"] {
                    appendLayerLog("Compile skipped: no session id.");
                    return;
                }
                api = browserAPI();
                if not api or not api.layersCompile {
                    appendLayerLog("Compile failed: browser bridge unavailable.");
                    return;
                }
                try {
                    result = await api.layersCompile({"session_id": state["activeSessionId"]});
                    if not result or objectValue(result, "ok", True) == False {
                        appendLayerLog("Compile failed: " + str(objectValue(result, "error", "unknown error")));
                        return;
                    }
                    state["activeWorkflowId"] = objectValue(result, "workflow_id", "") or "";
                    syncLayerStateLabels();
                    appendLayerLog("Compiled workflow " + state["activeWorkflowId"] + " (" + str(objectValue(result, "step_count", 0)) + " steps)");
                } except Exception as err {
                    appendLayerLog("Compile threw: " + str(err.message or err));
                }
            }
            handle();
        });

        state["planWorkflowBtn"].addEventListener("click", lambda {
            async def handle {
                if not state["activeWorkflowId"] {
                    appendLayerLog("Plan skipped: no workflow id.");
                    return;
                }
                api = browserAPI();
                if not api or not api.layersPlan {
                    appendLayerLog("Plan failed: browser bridge unavailable.");
                    return;
                }
                try {
                    result = await api.layersPlan({"workflow_id": state["activeWorkflowId"], "inputs": {}});
                    if not result or objectValue(result, "ok", True) == False {
                        appendLayerLog("Plan failed: " + str(objectValue(result, "error", "unknown error")));
                        return;
                    }
                    unresolved = objectValue(result, "unresolved_inputs", []) or [];
                    appendLayerLog("Planned " + str(objectValue(result, "workflow_id", "")) + ": " + str(objectValue(result, "step_count", 0)) + " steps, unresolved: " + str(len(unresolved)));
                } except Exception as err {
                    appendLayerLog("Plan threw: " + str(err.message or err));
                }
            }
            handle();
        });

        async def initialize() -> None {
            syncLayerStateLabels();
            state["webviewPreloadUrl"] = await safeGetWebviewPreloadUrl();
            if not state["webviewPreloadUrl"] {
                appendLayerLog("Warning: webview preload not resolved; in-page telemetry disabled.");
            }
            homeUrl = await safeGetHomeUrl();
            addTab(homeUrl, {"activate": True, "emitObservation": False});
            scheduleChromeStateSync();
        }

        initialize();
        return lambda {};
    }
}
