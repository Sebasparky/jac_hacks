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
            "helpersPage": document.getElementById("helpersPage"),
            "tabList": document.getElementById("tabList"),
            "newTabBtn": document.getElementById("newTabBtn"),
            "navForm": document.getElementById("navForm"),
            "addressInput": document.getElementById("addressInput"),
            "homeBtn": document.getElementById("homeBtn"),
            "backBtn": document.getElementById("backBtn"),
            "forwardBtn": document.getElementById("forwardBtn"),
            "reloadBtn": document.getElementById("reloadBtn"),
            "showBrowserViewBtn": document.getElementById("showBrowserViewBtn"),
            "showHelpersViewBtn": document.getElementById("showHelpersViewBtn"),
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
            "createHelperBtn": document.getElementById("createHelperBtn"),
            "helperList": document.getElementById("helperList"),
            "helperBuilderPanel": document.getElementById("helperBuilderPanel"),
            "helperNameInput": document.getElementById("helperNameInput"),
            "helperGoalInput": document.getElementById("helperGoalInput"),
            "helperFrequencySelect": document.getElementById("helperFrequencySelect"),
            "helperCreateBtn": document.getElementById("helperCreateBtn"),
            "helperCancelBtn": document.getElementById("helperCancelBtn"),
            "helpersPageCreateBtn": document.getElementById("helpersPageCreateBtn"),
            "helpersPageList": document.getElementById("helpersPageList"),
            "helpersPageDetail": document.getElementById("helpersPageDetail"),
            "helpersPageResults": document.getElementById("helpersPageResults"),
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
            "activeShellView": "browser",
            "helperBuilderOpen": False,
            "helperDraftName": "",
            "helperDraftGoal": "",
            "helperDraftFrequency": "once",
            "selectedHelperId": "",
            "helperEditMode": False,
            "helperEditGoalDraft": "",
            "helpers": [],
            "helperResults": [],
            "helperSeed": 0,
            "helperResultSeed": 0,
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

        def normalizedHelperFrequency(rawValue: any) -> str {
            frequency = trimmedText(rawValue).toLowerCase();
            if frequency == "browser_open" or frequency == "daily" or frequency == "weekly" {
                return frequency;
            }
            return "once";
        }

        def helperFrequencyLabel(rawValue: any) -> str {
            frequency = normalizedHelperFrequency(rawValue);
            if frequency == "browser_open" {
                return "On browser open";
            }
            if frequency == "daily" {
                return "Daily";
            }
            if frequency == "weekly" {
                return "Weekly";
            }
            return "Just once";
        }

        def helperFormReady() -> bool {
            return trimmedText(state["helperDraftName"]) != "" and trimmedText(state["helperDraftGoal"]) != "";
        }

        def localTimestamp() -> str {
            return Reflect.construct(Date, []).toLocaleString();
        }

        def helperGoalPreview(goalText: any, maxLength: any = 88) -> str {
            preview = trimmedText(goalText).replace("\n", " ").replace("\r", " ");
            limit = Number(maxLength or 88);
            if len(preview) <= limit {
                return preview or "No goal yet.";
            }
            return preview.slice(0, limit - 3) + "...";
        }

        def nextHelperId() -> str {
            state["helperSeed"] = state["helperSeed"] + 1;
            return "helper_" + str(Date.now()) + "_" + str(state["helperSeed"]);
        }

        def nextHelperResultId() -> str {
            state["helperResultSeed"] = state["helperResultSeed"] + 1;
            return "helper_result_" + str(Date.now()) + "_" + str(state["helperResultSeed"]);
        }

        """R: Infer a lightweight helper type from the user's goal without surfacing backend jargon.
        M: Matches a few product-approved keywords in priority order and falls back to a general helper when none apply.
        E: Empty or mixed-intent goals still produce a stable type so local helper creation never blocks on inference.
        """;
        def inferHelperType(goalText: any) -> str {
            lowered = trimmedText(goalText).toLowerCase();
            if not lowered {
                return "general";
            }
            if lowered.includes("summarize") or lowered.includes("summary") or lowered.includes("brief") or lowered.includes("digest") {
                return "summary";
            }
            if lowered.includes("watch") or lowered.includes("monitor") or lowered.includes("track") {
                return "monitor";
            }
            if lowered.includes("research") or lowered.includes("find") or lowered.includes("look up") or lowered.includes("lookup") {
                return "research";
            }
            return "general";
        }

        """R: Hide the first-pass helper spec behind the simple builder inputs.
        M: Converts the user's name, goal, and cadence into a renderer-local read-only object with trigger and intent metadata.
        E: Unknown frequencies are normalized to `once`, and the spec remains local-only so it never claims real execution.
        """;
        def buildHelperSpec(nameText: any, goalText: any, rawFrequency: any) -> any {
            frequency = normalizedHelperFrequency(rawFrequency);
            helper_type = inferHelperType(goalText);
            return {
                "type": helper_type,
                "intent": {
                    "name": trimmedText(nameText),
                    "goal": trimmedText(goalText)
                },
                "trigger": {
                    "frequency": frequency,
                    "label": helperFrequencyLabel(frequency)
                },
                "permissions": {
                    "read_only": True
                },
                "runtime": {
                    "mode": "renderer_local_demo"
                }
            };
        }

        def resetHelperDraft() -> None {
            state["helperDraftName"] = "";
            state["helperDraftGoal"] = "";
            state["helperDraftFrequency"] = "once";
        }

        def expandLayerPanel() -> None {
            if state["layerPanel"] and state["layerPanel"].classList.contains("collapsed") {
                state["layerPanel"].classList.remove("collapsed");
            }
            if state["toggleLayersBtn"] {
                state["toggleLayersBtn"].setAttribute("aria-pressed", "true");
            }
        }

        """R: Keep the browser shell focused on either the live webview or the Helpers workspace.
        M: Switches the active page flag, mirrors it into the existing chrome buttons, and toggles the two root content panes.
        E: Unknown view names fall back to `browser`, and missing page nodes simply skip the visibility updates.
        """;
        def syncShellViewUi() -> None {
            active_view = "helpers" if state["activeShellView"] == "helpers" else "browser";
            if state["showBrowserViewBtn"] {
                state["showBrowserViewBtn"].setAttribute("aria-pressed", "true" if active_view == "browser" else "false");
            }
            if state["showHelpersViewBtn"] {
                state["showHelpersViewBtn"].setAttribute("aria-pressed", "true" if active_view == "helpers" else "false");
            }
            if state["viewport"] {
                state["viewport"].style.display = "block" if active_view == "browser" else "none";
            }
            if state["helpersPage"] {
                state["helpersPage"].style.display = "flex" if active_view == "helpers" else "none";
            }
        }

        def setShellView(nextView: any) -> None {
            state["activeShellView"] = "helpers" if str(nextView or "") == "helpers" else "browser";
            syncClawUi();
        }

        """R: Keep the larger helper-builder panel aligned with local renderer state.
        M: Mirrors the draft fields into the DOM, toggles the expanded card, and updates builder action labels and disabled states.
        E: Missing builder nodes are ignored so the browser shell still works when helper UI is absent.
        """;
        def syncHelperBuilderUi() -> None {
            if state["createHelperBtn"] {
                state["createHelperBtn"].textContent = "Close Helper" if state["helperBuilderOpen"] else "Create Helper";
                state["createHelperBtn"].setAttribute("aria-expanded", str(state["helperBuilderOpen"]));
                state["createHelperBtn"].title = "Hide the helper builder." if state["helperBuilderOpen"] else "Open the larger helper builder.";
            }
            if state["helperBuilderPanel"] {
                state["helperBuilderPanel"].style.display = "flex" if state["helperBuilderOpen"] else "none";
            }
            if state["helperNameInput"] and state["helperNameInput"].value != state["helperDraftName"] {
                state["helperNameInput"].value = state["helperDraftName"];
            }
            if state["helperGoalInput"] and state["helperGoalInput"].value != state["helperDraftGoal"] {
                state["helperGoalInput"].value = state["helperDraftGoal"];
            }
            if state["helperFrequencySelect"] and state["helperFrequencySelect"].value != state["helperDraftFrequency"] {
                state["helperFrequencySelect"].value = state["helperDraftFrequency"];
            }
            if state["helperCreateBtn"] {
                state["helperCreateBtn"].disabled = not helperFormReady();
                state["helperCreateBtn"].title = "Add a name and helper goal first." if not helperFormReady() else "Create this helper in renderer-local state.";
            }
            if state["helperCancelBtn"] {
                state["helperCancelBtn"].textContent = "Close" if state["helperBuilderOpen"] else "Cancel";
            }
        }

        """R: Render the small helper list inside the regular Claw panel without switching to framework state.
        M: Rebuilds compact helper cards from renderer memory and wires local run-now buttons for demo feedback.
        E: An empty helper list falls back to a truthful placeholder, and missing DOM nodes simply skip rendering work.
        """;
        def renderHelperList() -> None {
            if not state["helperList"] {
                return;
            }

            state["helperList"].textContent = "";
            if len(state["helpers"]) == 0 {
                state["helperList"].textContent = "No helpers yet. Create one to keep a lightweight assistant brief in this browser shell.";
                return;
            }

            for helper in state["helpers"] {
                helper_id = str(objectValue(helper, "id", ""));
                card = document.createElement("div");
                card.style.display = "flex";
                card.style.flexDirection = "column";
                card.style.gap = "6px";
                card.style.padding = "10px 12px";
                card.style.borderRadius = "12px";
                card.style.background = "#ffffff";
                card.style.border = "1px solid rgba(88, 116, 173, 0.12)";
                card.style.cursor = "pointer";
                card.title = "Open this helper in the Helpers page.";
                card.addEventListener("click", lambda {
                    selectHelper(helper_id);
                    setShellView("helpers");
                });

                title = document.createElement("div");
                title.style.color = "#183154";
                title.style.fontSize = "12px";
                title.style.fontWeight = "800";
                title.textContent = str(objectValue(helper, "name", "Untitled helper"));

                meta = document.createElement("div");
                meta.style.color = "#526885";
                meta.style.fontSize = "11px";
                meta.style.lineHeight = "1.5";
                meta.textContent = (
                    helperFrequencyLabel(objectValue(helper, "frequency", "once")) +
                    " | " +
                    str(objectValue(helper, "kind", "general")) +
                    " | local demo"
                );

                goal = document.createElement("div");
                goal.style.color = "#324b70";
                goal.style.fontSize = "11px";
                goal.style.lineHeight = "1.55";
                goal.textContent = helperGoalPreview(objectValue(helper, "goal", ""));

                actions = document.createElement("div");
                actions.style.display = "flex";
                actions.style.justifyContent = "space-between";
                actions.style.alignItems = "center";
                actions.style.gap = "8px";

                stamp = document.createElement("div");
                stamp.style.color = "#6b7f9f";
                stamp.style.fontSize = "10px";
                stamp.textContent = "Created " + trimmedText(objectValue(helper, "createdAt", ""));

                runBtn = document.createElement("button");
                runBtn.className = "layer-btn";
                runBtn.type = "button";
                runBtn.dataset.helperId = helper_id;
                runBtn.textContent = "Run now";
                runBtn.title = "Record a local demo run request for this helper.";
                runBtn.style.padding = "6px 10px";
                runBtn.style.fontSize = "11px";
                runBtn.addEventListener("click", lambda event {
                    event.stopPropagation();
                    button = event.currentTarget or event.target;
                    handleHelperRunNow(button.dataset.helperId or "");
                });

                actions.appendChild(stamp);
                actions.appendChild(runBtn);

                card.appendChild(title);
                card.appendChild(meta);
                card.appendChild(goal);
                card.appendChild(actions);
                state["helperList"].appendChild(card);
            }
        }

        def openHelperBuilder() -> None {
            state["helperBuilderOpen"] = True;
            expandLayerPanel();
            syncClawUi();
            if state["helperNameInput"] {
                setTimeout(lambda { state["helperNameInput"].focus(); }, 10);
            }
        }

        def closeHelperBuilder(clearDraft: any = True) -> None {
            state["helperBuilderOpen"] = False;
            if clearDraft {
                resetHelperDraft();
            }
            syncClawUi();
        }

        def findHelperById(helperId: any) -> any {
            wanted = str(helperId or "");
            if not wanted {
                return None;
            }
            for helper in state["helpers"] {
                if helper["id"] == wanted {
                    return helper;
                }
            }
            return None;
        }

        def helperResultsFor(helperId: any) -> any {
            wanted = str(helperId or "");
            matches = [];
            if not wanted {
                return matches;
            }
            for result in state["helperResults"] {
                if str(objectValue(result, "helperId", "")) == wanted {
                    matches.push(result);
                }
            }
            return matches;
        }

        def ensureSelectedHelper() -> None {
            if findHelperById(state["selectedHelperId"]) {
                return;
            }
            if len(state["helpers"]) > 0 {
                state["selectedHelperId"] = str(objectValue(state["helpers"][0], "id", ""));
                state["helperEditGoalDraft"] = trimmedText(objectValue(state["helpers"][0], "goal", ""));
                return;
            }
            state["selectedHelperId"] = "";
            state["helperEditMode"] = False;
            state["helperEditGoalDraft"] = "";
        }

        def selectHelper(helperId: any, editMode: any = False) -> None {
            helper = findHelperById(helperId);
            if not helper {
                return;
            }
            state["selectedHelperId"] = str(objectValue(helper, "id", ""));
            state["helperEditMode"] = editMode == True;
            state["helperEditGoalDraft"] = trimmedText(objectValue(helper, "goal", ""));
            syncClawUi();
        }

        def selectedHelper() -> any {
            ensureSelectedHelper();
            return findHelperById(state["selectedHelperId"]);
        }

        """R: Capture a demo-safe helper run result without depending on backend execution.
        M: Prepends a renderer-local result object with timestamp, mode, status, summary, and optional notes to the shared helper history.
        E: Unknown helper ids are ignored, and the local history is trimmed so repeated demo runs stay bounded.
        """;
        def recordHelperResult(helperId: any, modeName: any, statusText: any, summaryText: any, notes: any = []) -> None {
            helper = findHelperById(helperId);
            if not helper {
                return;
            }

            result = {
                "id": nextHelperResultId(),
                "helperId": str(objectValue(helper, "id", "")),
                "timestamp": localTimestamp(),
                "mode": trimmedText(modeName) or "renderer_local_demo",
                "status": trimmedText(statusText) or "recorded",
                "summary": trimmedText(summaryText) or "Local helper result recorded.",
                "notes": notes or []
            };
            state["helperResults"].unshift(result);
            if len(state["helperResults"]) > 48 {
                state["helperResults"] = state["helperResults"].slice(0, 48);
            }
        }

        def beginHelperEdit() -> None {
            helper = selectedHelper();
            if not helper {
                return;
            }
            state["helperEditMode"] = True;
            state["helperEditGoalDraft"] = trimmedText(objectValue(helper, "goal", ""));
            syncClawUi();
            setTimeout(lambda {
                detailInput = document.getElementById("helperDetailGoalInput");
                if detailInput {
                    detailInput.focus();
                }
            }, 10);
        }

        def cancelHelperEdit() -> None {
            helper = selectedHelper();
            state["helperEditMode"] = False;
            state["helperEditGoalDraft"] = trimmedText(objectValue(helper, "goal", "")) if helper else "";
            syncClawUi();
        }

        """R: Apply local-only helper instruction edits from the dedicated Helpers page.
        M: Validates the draft, updates the helper goal and inferred local spec in memory, and leaves persistence or scheduling untouched.
        E: Empty drafts keep edit mode open and surface a truthful prompt instead of saving a blank helper brief.
        """;
        def saveHelperEdit() -> None {
            helper = selectedHelper();
            if not helper {
                return;
            }

            updated_goal = trimmedText(state["helperEditGoalDraft"]);
            if not updated_goal {
                setClawStatus("Add helper instructions before saving local edits.");
                return;
            }

            helper["goal"] = updated_goal;
            helper["kind"] = inferHelperType(updated_goal);
            helper["spec"] = buildHelperSpec(helper["name"], updated_goal, helper["frequency"]);
            state["helperEditMode"] = False;
            appendClawTranscript(
                "system",
                "Updated helper instructions locally for " + str(objectValue(helper, "name", "Helper")) + ".\n" +
                "This changes the renderer-only demo copy and does not persist or schedule anything yet."
            );
            setClawStatus("Saved local helper edits for " + str(objectValue(helper, "name", "Helper")) + ".");
        }

        """R: Render the dedicated Helpers page from the same local helper state used by the side panel.
        M: Rebuilds the helper list, selected-helper detail, and recent results areas whenever local helper state changes.
        E: Empty helper sets and missing containers fall back to truthful placeholders instead of blocking the shell.
        """;
        def renderHelpersWorkspace() -> None {
            if not state["helpersPageList"] or not state["helpersPageDetail"] or not state["helpersPageResults"] {
                return;
            }

            ensureSelectedHelper();
            selected_id = str(state["selectedHelperId"] or "");
            selected = findHelperById(selected_id);

            state["helpersPageList"].textContent = "";
            if len(state["helpers"]) == 0 {
                empty_list = document.createElement("div");
                empty_list.style.padding = "14px";
                empty_list.style.borderRadius = "16px";
                empty_list.style.border = "1px dashed rgba(88, 116, 173, 0.22)";
                empty_list.style.background = "rgba(244, 247, 255, 0.76)";
                empty_list.style.color = "#526885";
                empty_list.style.fontSize = "13px";
                empty_list.style.lineHeight = "1.6";
                empty_list.textContent = "No helpers yet. Use Create Helper to open the local builder in the side panel.";
                state["helpersPageList"].appendChild(empty_list);
            } else {
                for helper in state["helpers"] {
                    helper_id = str(objectValue(helper, "id", ""));
                    card = document.createElement("button");
                    card.type = "button";
                    card.style.display = "flex";
                    card.style.flexDirection = "column";
                    card.style.alignItems = "stretch";
                    card.style.gap = "10px";
                    card.style.width = "100%";
                    card.style.padding = "14px";
                    card.style.borderRadius = "18px";
                    card.style.border = "1px solid rgba(88, 116, 173, 0.14)";
                    card.style.background = "#ffffff" if helper_id != selected_id else "linear-gradient(180deg, rgba(234, 241, 255, 0.98) 0%, rgba(255, 255, 255, 0.98) 100%)";
                    card.style.boxSizing = "border-box";
                    card.style.cursor = "pointer";
                    card.style.textAlign = "left";
                    card.addEventListener("click", lambda {
                        selectHelper(helper_id);
                    });

                    top_row = document.createElement("div");
                    top_row.style.display = "flex";
                    top_row.style.justifyContent = "space-between";
                    top_row.style.alignItems = "flex-start";
                    top_row.style.gap = "10px";

                    title_wrap = document.createElement("div");
                    title_wrap.style.display = "flex";
                    title_wrap.style.flexDirection = "column";
                    title_wrap.style.gap = "4px";

                    title = document.createElement("div");
                    title.style.color = "#183154";
                    title.style.fontSize = "14px";
                    title.style.fontWeight = "800";
                    title.textContent = str(objectValue(helper, "name", "Untitled helper"));

                    preview = document.createElement("div");
                    preview.style.color = "#526885";
                    preview.style.fontSize = "12px";
                    preview.style.lineHeight = "1.55";
                    preview.textContent = helperGoalPreview(objectValue(helper, "goal", ""), 112);

                    title_wrap.appendChild(title);
                    title_wrap.appendChild(preview);

                    run_btn = document.createElement("button");
                    run_btn.className = "layer-btn";
                    run_btn.type = "button";
                    run_btn.textContent = "Run now";
                    run_btn.style.flex = "0 0 auto";
                    run_btn.style.padding = "0 12px";
                    run_btn.style.minWidth = "92px";
                    run_btn.addEventListener("click", lambda event {
                        event.stopPropagation();
                        handleHelperRunNow(helper_id);
                    });

                    top_row.appendChild(title_wrap);
                    top_row.appendChild(run_btn);

                    meta = document.createElement("div");
                    meta.style.display = "flex";
                    meta.style.flexWrap = "wrap";
                    meta.style.gap = "8px";
                    meta.style.color = "#38557f";
                    meta.style.fontSize = "11px";
                    meta.style.fontWeight = "700";
                    meta.textContent = (
                        "Frequency: " + helperFrequencyLabel(objectValue(helper, "frequency", "once")) +
                        " | Type: " + str(objectValue(helper, "kind", "general"))
                    );

                    card.appendChild(top_row);
                    card.appendChild(meta);
                    state["helpersPageList"].appendChild(card);
                }
            }

            state["helpersPageDetail"].textContent = "";
            if not selected {
                empty_detail = document.createElement("div");
                empty_detail.style.color = "#526885";
                empty_detail.style.fontSize = "13px";
                empty_detail.style.lineHeight = "1.6";
                empty_detail.textContent = "Select a helper to inspect its local instructions, edit them, or run it now.";
                state["helpersPageDetail"].appendChild(empty_detail);
            } else {
                heading_row = document.createElement("div");
                heading_row.style.display = "flex";
                heading_row.style.justifyContent = "space-between";
                heading_row.style.alignItems = "flex-start";
                heading_row.style.gap = "12px";

                title_wrap = document.createElement("div");
                title_wrap.style.display = "flex";
                title_wrap.style.flexDirection = "column";
                title_wrap.style.gap = "4px";

                title = document.createElement("div");
                title.style.color = "#183154";
                title.style.fontSize = "24px";
                title.style.fontWeight = "800";
                title.style.letterSpacing = "-0.03em";
                title.textContent = str(objectValue(selected, "name", "Untitled helper"));

                subtitle = document.createElement("div");
                subtitle.style.color = "#526885";
                subtitle.style.fontSize = "13px";
                subtitle.style.lineHeight = "1.55";
                subtitle.textContent = "Local demo helper stored in renderer memory only.";

                title_wrap.appendChild(title);
                title_wrap.appendChild(subtitle);

                actions = document.createElement("div");
                actions.style.display = "flex";
                actions.style.flexWrap = "wrap";
                actions.style.justifyContent = "flex-end";
                actions.style.gap = "8px";

                run_btn = document.createElement("button");
                run_btn.className = "layer-btn";
                run_btn.type = "button";
                run_btn.textContent = "Run now";
                run_btn.addEventListener("click", lambda {
                    handleHelperRunNow(objectValue(selected, "id", ""));
                });
                actions.appendChild(run_btn);

                if state["helperEditMode"] {
                    save_btn = document.createElement("button");
                    save_btn.className = "layer-btn";
                    save_btn.type = "button";
                    save_btn.textContent = "Save";
                    save_btn.addEventListener("click", lambda {
                        saveHelperEdit();
                    });

                    cancel_btn = document.createElement("button");
                    cancel_btn.className = "layer-btn";
                    cancel_btn.type = "button";
                    cancel_btn.textContent = "Cancel";
                    cancel_btn.addEventListener("click", lambda {
                        cancelHelperEdit();
                    });

                    actions.appendChild(save_btn);
                    actions.appendChild(cancel_btn);
                } else {
                    edit_btn = document.createElement("button");
                    edit_btn.className = "layer-btn";
                    edit_btn.type = "button";
                    edit_btn.textContent = "Edit";
                    edit_btn.addEventListener("click", lambda {
                        beginHelperEdit();
                    });
                    actions.appendChild(edit_btn);
                }

                heading_row.appendChild(title_wrap);
                heading_row.appendChild(actions);
                state["helpersPageDetail"].appendChild(heading_row);

                meta = document.createElement("div");
                meta.style.display = "flex";
                meta.style.flexWrap = "wrap";
                meta.style.gap = "8px";
                meta.style.marginTop = "2px";
                meta.style.color = "#38557f";
                meta.style.fontSize = "11px";
                meta.style.fontWeight = "700";
                meta.textContent = (
                    "Frequency: " + helperFrequencyLabel(objectValue(selected, "frequency", "once")) +
                    " | Type: " + str(objectValue(selected, "kind", "general")) +
                    " | Created: " + str(objectValue(selected, "createdAt", "local session"))
                );
                state["helpersPageDetail"].appendChild(meta);

                label = document.createElement("div");
                label.style.color = "#6b7b95";
                label.style.fontSize = "11px";
                label.style.fontWeight = "800";
                label.style.letterSpacing = "0.08em";
                label.style.textTransform = "uppercase";
                label.textContent = "Instructions";
                state["helpersPageDetail"].appendChild(label);

                if state["helperEditMode"] {
                    textarea = document.createElement("textarea");
                    textarea.id = "helperDetailGoalInput";
                    textarea.rows = 8;
                    textarea.spellcheck = False;
                    textarea.value = state["helperEditGoalDraft"];
                    textarea.style.width = "100%";
                    textarea.style.minHeight = "180px";
                    textarea.style.padding = "14px 16px";
                    textarea.style.borderRadius = "18px";
                    textarea.style.border = "1px solid rgba(88, 116, 173, 0.16)";
                    textarea.style.background = "#ffffff";
                    textarea.style.boxSizing = "border-box";
                    textarea.style.color = "#1f345a";
                    textarea.style.fontSize = "14px";
                    textarea.style.fontWeight = "600";
                    textarea.style.lineHeight = "1.65";
                    textarea.style.resize = "vertical";
                    textarea.addEventListener("input", lambda event {
                        target = event.currentTarget or event.target;
                        state["helperEditGoalDraft"] = str(target.value or "");
                    });
                    state["helpersPageDetail"].appendChild(textarea);
                } else {
                    goal = document.createElement("div");
                    goal.style.padding = "16px 18px";
                    goal.style.borderRadius = "18px";
                    goal.style.border = "1px solid rgba(88, 116, 173, 0.12)";
                    goal.style.background = "rgba(244, 247, 255, 0.84)";
                    goal.style.color = "#1f345a";
                    goal.style.fontSize = "14px";
                    goal.style.fontWeight = "600";
                    goal.style.lineHeight = "1.7";
                    goal.textContent = trimmedText(objectValue(selected, "goal", "")) or "No instructions yet.";
                    state["helpersPageDetail"].appendChild(goal);
                }
            }

            state["helpersPageResults"].textContent = "";
            if not selected {
                empty_results = document.createElement("div");
                empty_results.style.color = "#526885";
                empty_results.style.fontSize = "13px";
                empty_results.style.lineHeight = "1.6";
                empty_results.textContent = "Select a helper to see its recent local run results.";
                state["helpersPageResults"].appendChild(empty_results);
                return;
            }

            results = helperResultsFor(objectValue(selected, "id", ""));
            if len(results) == 0 {
                empty_results = document.createElement("div");
                empty_results.style.padding = "14px";
                empty_results.style.borderRadius = "16px";
                empty_results.style.border = "1px dashed rgba(88, 116, 173, 0.22)";
                empty_results.style.background = "rgba(244, 247, 255, 0.76)";
                empty_results.style.color = "#526885";
                empty_results.style.fontSize = "13px";
                empty_results.style.lineHeight = "1.6";
                empty_results.textContent = "No local results yet. Use Run now to capture a renderer-only demo result for this helper.";
                state["helpersPageResults"].appendChild(empty_results);
                return;
            }

            for result in results.slice(0, 6) {
                card = document.createElement("div");
                card.style.display = "flex";
                card.style.flexDirection = "column";
                card.style.gap = "10px";
                card.style.padding = "14px";
                card.style.borderRadius = "18px";
                card.style.border = "1px solid rgba(88, 116, 173, 0.12)";
                card.style.background = "#ffffff";

                top_row = document.createElement("div");
                top_row.style.display = "flex";
                top_row.style.justifyContent = "space-between";
                top_row.style.alignItems = "center";
                top_row.style.gap = "10px";

                timestamp = document.createElement("div");
                timestamp.style.color = "#183154";
                timestamp.style.fontSize = "12px";
                timestamp.style.fontWeight = "800";
                timestamp.textContent = str(objectValue(result, "timestamp", ""));

                status = document.createElement("div");
                status.style.color = "#355ca3";
                status.style.fontSize = "11px";
                status.style.fontWeight = "800";
                status.style.letterSpacing = "0.03em";
                status.style.textTransform = "uppercase";
                status.textContent = str(objectValue(result, "status", "recorded"));

                top_row.appendChild(timestamp);
                top_row.appendChild(status);

                mode = document.createElement("div");
                mode.style.color = "#526885";
                mode.style.fontSize = "12px";
                mode.style.fontWeight = "700";
                mode.textContent = "Mode: " + str(objectValue(result, "mode", "renderer_local_demo"));

                summary = document.createElement("div");
                summary.style.color = "#1f345a";
                summary.style.fontSize = "13px";
                summary.style.lineHeight = "1.6";
                summary.textContent = str(objectValue(result, "summary", ""));

                card.appendChild(top_row);
                card.appendChild(mode);
                card.appendChild(summary);

                note_items = objectValue(result, "notes", []) or [];
                if len(note_items) > 0 {
                    notes_list = document.createElement("ul");
                    notes_list.style.margin = "0";
                    notes_list.style.paddingLeft = "18px";
                    notes_list.style.color = "#526885";
                    notes_list.style.fontSize = "12px";
                    notes_list.style.lineHeight = "1.6";
                    for note in note_items {
                        note_item = document.createElement("li");
                        note_item.textContent = str(note or "");
                        notes_list.appendChild(note_item);
                    }
                    card.appendChild(notes_list);
                }

                state["helpersPageResults"].appendChild(card);
            }
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
            syncShellViewUi();
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
            syncHelperBuilderUi();
            renderHelperList();
            renderHelpersWorkspace();
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

        """R: Create a lightweight local helper without exposing internal spec details in the UI.
        M: Validates the simple builder fields, infers a helper type, stores a renderer-local read-only helper record, and posts a confirmation to Claw.
        E: Missing name or goal keeps the builder open and reports an honest prompt instead of creating a partial helper.
        """;
        def handleHelperCreate() -> None {
            helper_name = trimmedText(state["helperDraftName"]);
            helper_goal = trimmedText(state["helperDraftGoal"]);
            helper_frequency = normalizedHelperFrequency(state["helperDraftFrequency"]);
            if not helper_name or not helper_goal {
                appendClawTranscript("system", "Add both a helper name and a helper goal before creating a helper.");
                setClawStatus("Add a helper name and goal to create a helper.");
                syncClawUi();
                return;
            }

            helper_spec = buildHelperSpec(helper_name, helper_goal, helper_frequency);
            helper = {
                "id": nextHelperId(),
                "name": helper_name,
                "goal": helper_goal,
                "frequency": helper_frequency,
                "frequencyLabel": helperFrequencyLabel(helper_frequency),
                "kind": objectValue(helper_spec, "type", "general"),
                "readOnly": True,
                "createdAt": localTimestamp(),
                "spec": helper_spec
            };
            state["helpers"].push(helper);
            state["selectedHelperId"] = helper["id"];
            state["helperEditMode"] = False;
            state["helperEditGoalDraft"] = helper_goal;

            appendClawTranscript(
                "system",
                "Helper created: " + helper_name + "\n" +
                "Type: " + str(helper["kind"]) + "\n" +
                "How often: " + helper["frequencyLabel"] + "\n" +
                "Stored locally in this renderer session as a demo helper."
            );
            setClawStatus("Helper ready: " + helper_name + " (" + helper["frequencyLabel"] + ")");
            closeHelperBuilder(True);
        }

        """R: Let the small helper list acknowledge a run request without pretending backend execution exists.
        M: Finds the local helper record, writes a transcript/status confirmation, and leaves the helper definition unchanged.
        E: Unknown helper ids are ignored so stale DOM buttons cannot break the renderer.
        """;
        def handleHelperRunNow(helperId: any) -> None {
            helper = findHelperById(helperId);
            if not helper {
                return;
            }

            helper_name = trimmedText(objectValue(helper, "name", "Helper"));
            state["selectedHelperId"] = str(objectValue(helper, "id", ""));
            recordHelperResult(
                objectValue(helper, "id", ""),
                "renderer_local_demo",
                "recorded",
                "Captured a local demo run request for " + helper_name + ".",
                [
                    "Goal snapshot: " + helperGoalPreview(objectValue(helper, "goal", ""), 132),
                    "Execution and scheduling are not wired yet; this result stays in renderer memory only."
                ]
            );
            appendClawTranscript(
                "system",
                "Local run requested for " + helper_name + ".\n" +
                "This demo stores the helper spec in renderer memory only, so execution and scheduling are not wired yet."
            );
            setClawStatus("Local helper run noted for " + helper_name + ".");
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

        if state["showBrowserViewBtn"] {
            state["showBrowserViewBtn"].addEventListener("click", lambda {
                setShellView("browser");
            });
        }

        if state["showHelpersViewBtn"] {
            state["showHelpersViewBtn"].addEventListener("click", lambda {
                setShellView("helpers");
            });
        }

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

        if state["createHelperBtn"] {
            state["createHelperBtn"].addEventListener("click", lambda {
                if state["helperBuilderOpen"] {
                    closeHelperBuilder(True);
                    return;
                }
                openHelperBuilder();
            });
        }

        if state["helperNameInput"] {
            state["helperNameInput"].addEventListener("input", lambda event {
                target = event.currentTarget or event.target;
                state["helperDraftName"] = str(target.value or "");
                syncClawUi();
            });
        }

        if state["helperGoalInput"] {
            state["helperGoalInput"].addEventListener("input", lambda event {
                target = event.currentTarget or event.target;
                state["helperDraftGoal"] = str(target.value or "");
                syncClawUi();
            });
        }

        if state["helperFrequencySelect"] {
            state["helperFrequencySelect"].addEventListener("change", lambda event {
                target = event.currentTarget or event.target;
                state["helperDraftFrequency"] = normalizedHelperFrequency(target.value or "once");
                syncClawUi();
            });
        }

        if state["helperCreateBtn"] {
            state["helperCreateBtn"].addEventListener("click", lambda {
                handleHelperCreate();
            });
        }

        if state["helperCancelBtn"] {
            state["helperCancelBtn"].addEventListener("click", lambda {
                closeHelperBuilder(True);
            });
        }

        if state["helpersPageCreateBtn"] {
            state["helpersPageCreateBtn"].addEventListener("click", lambda {
                setShellView("helpers");
                openHelperBuilder();
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
