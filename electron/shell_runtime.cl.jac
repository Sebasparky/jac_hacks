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
            "clawTranscript": document.getElementById("clawTranscript"),
            "clawDraftInput": document.getElementById("clawDraftInput"),
            "clawPlanBtn": document.getElementById("clawPlanBtn"),
            "clawSaveDraftBtn": document.getElementById("clawSaveDraftBtn"),
            "clawStatus": document.getElementById("clawStatus"),
            "progressInterval": None,
            "progressGuardTimeout": None,
            "activeSessionId": "",
            "activeWorkflowId": "",
            "clawDraft": "",
            "clawTranscriptMessages": [],
            "clawIsPlanning": False,
            "clawStatusText": "",
            "clawLastPlanResult": None,
            "clawLastSavedMessage": "",
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

        def trimmedText(rawValue: any) -> str {
            return str(rawValue or "").trim();
        }

        def commaList(values: any) -> str {
            if not values or len(values) == 0 {
                return "none";
            }

            joined = "";
            for value in values {
                if joined {
                    joined = joined + ", ";
                }
                joined = joined + str(value);
            }
            return joined or "none";
        }

        def hasClawDraft() -> bool {
            return trimmedText(state["clawDraft"]) != "";
        }

        def defaultClawStatus() -> str {
            if not hasClawDraft() and not state["activeSessionId"] {
                return "Add a task. Plan now also needs an active live trace.";
            }
            if not hasClawDraft() {
                return "Add a task to use Plan now or Save draft.";
            }
            if not state["activeSessionId"] {
                return "Draft ready. Start Trace to use Plan now.";
            }
            return "Draft ready. Plan now uses the active live trace.";
        }

        """R: Keep the Claw transcript area readable from renderer-local state.
        M: Formats user/system entries into compact text blocks and keeps the newest message visible.
        E: Missing transcript DOM or empty message lists fall back to a truthful default description.
        """;
        def renderClawTranscript() -> None {
            if not state["clawTranscript"] {
                return;
            }

            rendered = "";
            for entry in state["clawTranscriptMessages"] {
                role = str(objectValue(entry, "role", "system"));
                prefix = "Claw";
                if role == "user" {
                    prefix = "You";
                } elif role == "error" {
                    prefix = "Claw error";
                }

                entry_text = trimmedText(objectValue(entry, "text", ""));
                if not entry_text {
                    continue;
                }

                stamp = trimmedText(objectValue(entry, "stamp", ""));
                if rendered {
                    rendered = rendered + "\n\n";
                }

                header = prefix;
                if stamp {
                    header = header + " | " + stamp;
                }
                rendered = rendered + header + "\n" + entry_text;
            }

            if not rendered {
                rendered = (
                    "Claw is ready.\n" +
                    "\n" +
                    "Type the task below.\n" +
                    "Plan now uses the active live trace.\n" +
                    "Save draft keeps the text in this browser shell only."
                );
            }

            state["clawTranscript"].textContent = rendered;
            state["clawTranscript"].scrollTop = state["clawTranscript"].scrollHeight;
        }

        """R: Sync the Claw controls with renderer-local draft and loading state.
        M: Updates status text, button labels, disabled states, and draft textarea contents.
        E: Missing DOM nodes are ignored so the shell can still boot without the Claw block.
        """;
        def syncClawUi() -> None {
            if state["clawDraftInput"] and state["clawDraftInput"].value != state["clawDraft"] {
                state["clawDraftInput"].value = state["clawDraft"];
            }
            if state["clawPlanBtn"] {
                state["clawPlanBtn"].disabled = state["clawIsPlanning"] or not hasClawDraft();
                state["clawPlanBtn"].textContent = "Planning..." if state["clawIsPlanning"] else "Plan now";
                state["clawPlanBtn"].title = "Planning from the active live trace." if state["clawIsPlanning"] else (
                    "Enter a task first." if not hasClawDraft() else (
                        "Start Trace, then use Plan now." if not state["activeSessionId"] else "Compile and plan from the active live trace."
                    )
                );
            }
            if state["clawSaveDraftBtn"] {
                state["clawSaveDraftBtn"].disabled = state["clawIsPlanning"] or not hasClawDraft();
                state["clawSaveDraftBtn"].title = "Planning is in progress." if state["clawIsPlanning"] else (
                    "Enter a task first." if not hasClawDraft() else "Save this draft in the current browser shell session."
                );
            }
            if state["clawStatus"] {
                state["clawStatus"].textContent = str(trimmedText(state["clawStatusText"]) or defaultClawStatus());
            }
            renderClawTranscript();
        }

        def setClawStatus(message: any) -> None {
            state["clawStatusText"] = trimmedText(message);
            syncClawUi();
        }

        """R: Append a bounded Claw transcript history inside renderer memory.
        M: Records role-tagged entries with a local timestamp and trims the transcript to recent messages.
        E: Blank messages are skipped so the panel never fills with empty transcript items.
        """;
        def appendClawTranscript(role: any, message: any) -> None {
            text = trimmedText(message);
            if not text {
                return;
            }

            state["clawTranscriptMessages"].push({
                "role": str(role or "system"),
                "text": text,
                "stamp": Reflect.construct(Date, []).toLocaleTimeString()
            });

            if len(state["clawTranscriptMessages"]) > 32 {
                state["clawTranscriptMessages"] = state["clawTranscriptMessages"].slice(len(state["clawTranscriptMessages"]) - 32);
            }
            renderClawTranscript();
        }

        def clawPlanInputs(draftText: str) -> any {
            if not draftText {
                return {};
            }
            return {"query": draftText};
        }

        """R: Turn a successful planner payload into an honest, readable transcript entry.
        M: Pulls the current workflow id, step count, and unresolved inputs into a short plain-language summary.
        E: Missing fields degrade to stable placeholders instead of leaving the transcript blank.
        """;
        def formatClawPlanSummary(result: any) -> str {
            unresolved = objectValue(result, "unresolved_inputs", []) or [];
            workflow_id = trimmedText(objectValue(result, "workflow_id", "")) or "unknown";
            step_count = str(objectValue(result, "step_count", 0));
            return (
                "Plan ready from the active live trace.\n" +
                "Workflow: " + workflow_id + "\n" +
                "Steps: " + step_count + "\n" +
                "Needs input: " + commaList(unresolved)
            );
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

        """R: Compile the current live trace into the active workflow slot.
        M: Validates the active session, calls the existing compile IPC path, updates workflow labels, and logs outcomes.
        E: Missing sessions, bridge methods, or thrown errors return `{ ok: false, error }` instead of crashing handlers.
        """;
        async def compileActiveTrace() -> any {
            if not state["activeSessionId"] {
                message = "Compile skipped: no session id.";
                appendLayerLog(message);
                return {"ok": False, "error": message};
            }

            api = browserAPI();
            if not api or not api.layersCompile {
                message = "Compile failed: browser bridge unavailable.";
                appendLayerLog(message);
                return {"ok": False, "error": message};
            }

            try {
                result = await api.layersCompile({"session_id": state["activeSessionId"]});
                if not result or objectValue(result, "ok", True) == False {
                    message = "Compile failed: " + str(objectValue(result, "error", "unknown error"));
                    appendLayerLog(message);
                    return result or {"ok": False, "error": message};
                }

                state["activeWorkflowId"] = objectValue(result, "workflow_id", "") or "";
                syncLayerStateLabels();
                appendLayerLog("Compiled workflow " + state["activeWorkflowId"] + " (" + str(objectValue(result, "step_count", 0)) + " steps)");
                return result;
            } except Exception as err {
                message = "Compile threw: " + str(err.message or err);
                appendLayerLog(message);
                return {"ok": False, "error": message};
            }
        }

        """R: Plan the currently compiled workflow through the existing live layer bridge.
        M: Calls the existing planner IPC route with optional runtime inputs and returns the raw planner payload.
        E: Missing workflow ids, bridge failures, or planner exceptions become structured `{ ok: false, error }` results.
        """;
        async def planActiveWorkflow(runInputs: any = {}) -> any {
            if not state["activeWorkflowId"] {
                message = "Plan skipped: no workflow id.";
                appendLayerLog(message);
                return {"ok": False, "error": message};
            }

            payload_inputs = {};
            if runInputs and typeof(runInputs) == "object" {
                payload_inputs = runInputs;
            }

            api = browserAPI();
            if not api or not api.layersPlan {
                message = "Plan failed: browser bridge unavailable.";
                appendLayerLog(message);
                return {"ok": False, "error": message};
            }

            try {
                result = await api.layersPlan({"workflow_id": state["activeWorkflowId"], "inputs": payload_inputs});
                if not result or objectValue(result, "ok", True) == False {
                    message = "Plan failed: " + str(objectValue(result, "error", "unknown error"));
                    appendLayerLog(message);
                    return result or {"ok": False, "error": message};
                }

                unresolved = objectValue(result, "unresolved_inputs", []) or [];
                planned_id = str(objectValue(result, "workflow_id", ""));
                planned_steps = str(objectValue(result, "step_count", 0));
                unresolved_count = str(len(unresolved));
                planned_msg = "Planned " + planned_id + ": " + planned_steps + " steps, unresolved: " + unresolved_count;
                appendLayerLog(planned_msg);
                return result;
            } except Exception as err {
                message = "Plan threw: " + str(err.message or err);
                appendLayerLog(message);
                return {"ok": False, "error": message};
            }
        }

        """R: Drive the Claw primary action without inventing backend behavior.
        M: Records the user draft locally, compiles the active live trace, and plans the compiled workflow with the draft as `query` when applicable.
        E: Empty drafts are ignored and missing live trace state is surfaced as an honest panel error.
        """;
        async def handleClawPlanNow() -> None {
            draft_text = trimmedText(state["clawDraft"]);
            if state["clawIsPlanning"] {
                return;
            }
            if not draft_text {
                appendClawTranscript("system", "Add a task before using Plan now.");
                setClawStatus("Add a task before using Plan now.");
                return;
            }

            appendClawTranscript("user", draft_text);
            state["clawLastSavedMessage"] = "";
            state["clawIsPlanning"] = True;
            state["clawLastPlanResult"] = None;
            setClawStatus("Planning from the active live trace...");

            try {
                if not state["activeSessionId"] {
                    appendClawTranscript("error", "No active live trace yet. Start Trace, interact with the page, and then use Plan now again. Your draft is still here.");
                    setClawStatus("No active trace. Start Trace, interact, then use Plan now.");
                    return;
                }

                compile_result = await compileActiveTrace();
                if not compile_result or objectValue(compile_result, "ok", True) == False {
                    appendClawTranscript("error", "Plan could not continue because compile failed: " + str(objectValue(compile_result, "error", "unknown error")));
                    setClawStatus("Plan blocked because compile failed.");
                    return;
                }

                plan_result = await planActiveWorkflow(clawPlanInputs(draft_text));
                if not plan_result or objectValue(plan_result, "ok", True) == False {
                    appendClawTranscript("error", "Plan failed: " + str(objectValue(plan_result, "error", "unknown error")));
                    setClawStatus("Plan failed. Check the transcript for details.");
                    return;
                }

                state["clawLastPlanResult"] = {
                    "workflow_id": trimmedText(objectValue(plan_result, "workflow_id", "")),
                    "step_count": objectValue(plan_result, "step_count", 0),
                    "unresolved_inputs": objectValue(plan_result, "unresolved_inputs", []) or []
                };
                appendClawTranscript("system", formatClawPlanSummary(plan_result));
                setClawStatus("Plan ready from the live trace: " + (state["clawLastPlanResult"]["workflow_id"] or "workflow available"));
            } finally {
                state["clawIsPlanning"] = False;
                syncClawUi();
            }
        }

        """R: Confirm a draft save without claiming persistence that does not exist yet.
        M: Keeps the draft in renderer memory, records a local confirmation, and surfaces it in the transcript/status.
        E: Empty drafts are ignored so the save affordance does not generate fake confirmations.
        """;
        def handleClawSaveDraft() -> None {
            draft_text = trimmedText(state["clawDraft"]);
            if state["clawIsPlanning"] {
                return;
            }
            if not draft_text {
                appendClawTranscript("system", "Add a task before using Save draft.");
                setClawStatus("Add a task before using Save draft.");
                return;
            }

            state["clawLastSavedMessage"] = "Draft saved in this browser shell at " + Reflect.construct(Date, []).toLocaleTimeString();
            appendClawTranscript("system", "Draft saved in this browser shell only for the current renderer session.");
            setClawStatus(state["clawLastSavedMessage"]);
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
                    setClawStatus("");
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
                    state["activeWorkflowId"] = "";
                    syncLayerStateLabels();
                    setClawStatus("Trace stopped. Start Trace again before using Plan now.");
                } except Exception as err {
                    appendLayerLog("Stop trace threw: " + str(err.message or err));
                }
            }
            handle();
        });

        state["compileTraceBtn"].addEventListener("click", lambda {
            async def handle {
                await compileActiveTrace();
            }
            handle();
        });

        state["planWorkflowBtn"].addEventListener("click", lambda {
            async def handle {
                await planActiveWorkflow();
            }
            handle();
        });

        if state["clawDraftInput"] {
            state["clawDraftInput"].addEventListener("input", lambda event {
                target = event.currentTarget or event.target;
                state["clawDraft"] = str(target.value or "");
                if not state["clawIsPlanning"] {
                    state["clawStatusText"] = "";
                    syncClawUi();
                }
            });
        }

        if state["clawPlanBtn"] {
            state["clawPlanBtn"].addEventListener("click", lambda {
                async def handle {
                    await handleClawPlanNow();
                }
                handle();
            });
        }

        if state["clawSaveDraftBtn"] {
            state["clawSaveDraftBtn"].addEventListener("click", lambda {
                handleClawSaveDraft();
            });
        }

        async def initialize() -> None {
            syncLayerStateLabels();
            appendClawTranscript("system", "Claw is ready. Type the task below. Plan now uses the active live trace. Save draft keeps the text in this browser shell only.");
            syncClawUi();
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
