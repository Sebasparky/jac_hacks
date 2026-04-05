"""Jac-authored browser shell that boots the Electron browser runtime."""

cl import from 'react' { useEffect as reactUseEffect }
cl import from '../generated/shell_runtime.mjs' { bootstrapBrowserShell }

cl {
    def:pub BrowserShell() -> JsxElement {
        reactUseEffect(lambda {
            bootstrapBrowserShell();
        }, []);

        return <div className="app-shell">
            <header className="browser-chrome">
                <div className="drag-region" aria-hidden="true"></div>
                <div className="tab-strip">
                    <div className="chrome-brand" aria-hidden="true">
                        <span className="brand-mark"></span>
                        <span className="brand-copy">JacHacks</span>
                    </div>
                    <div id="tabList" className="tab-list"></div>
                    <button id="newTabBtn" className="new-tab-btn" type="button" title="New Tab" aria-label="New Tab">
                        <svg viewBox="0 0 20 20" aria-hidden="true">
                            <path
                                d="M10 4.25a.75.75 0 0 1 .75.75v4.25H15a.75.75 0 0 1 0 1.5h-4.25V15a.75.75 0 0 1-1.5 0v-4.25H5a.75.75 0 0 1 0-1.5h4.25V5a.75.75 0 0 1 .75-.75Z"
                                fill="currentColor"
                            />
                        </svg>
                    </button>
                    <div className="window-controls">
                        <button id="minBtn" className="window-btn" type="button" title="Minimize">-</button>
                        <button id="maxBtn" className="window-btn" type="button" title="Maximize">[]</button>
                        <button id="closeBtn" className="window-btn danger" type="button" title="Close">X</button>
                    </div>
                </div>

                <div className="toolbar">
                    <div className="nav-group">
                        <button id="homeBtn" className="icon-btn" type="button" title="Home" aria-label="Home">
                            <svg viewBox="0 0 20 20" aria-hidden="true">
                                <path
                                    d="M10 3.5 3.75 8.8v6.45c0 .41.34.75.75.75h3.5v-4.4c0-.41.34-.75.75-.75h2.5c.41 0 .75.34.75.75V16h3.5c.41 0 .75-.34.75-.75V8.8L10 3.5Z"
                                    fill="currentColor"
                                />
                            </svg>
                        </button>
                        <button id="backBtn" className="icon-btn" type="button" title="Back" aria-label="Back">
                            <svg viewBox="0 0 20 20" aria-hidden="true">
                                <path d="M11.75 4.75 6.5 10l5.25 5.25 1.06-1.06L8.62 10l4.19-4.19-1.06-1.06Z" fill="currentColor" />
                            </svg>
                        </button>
                        <button id="forwardBtn" className="icon-btn" type="button" title="Forward" aria-label="Forward">
                            <svg viewBox="0 0 20 20" aria-hidden="true">
                                <path d="M8.25 15.25 13.5 10 8.25 4.75 7.19 5.81 11.38 10l-4.19 4.19 1.06 1.06Z" fill="currentColor" />
                            </svg>
                        </button>
                        <button id="reloadBtn" className="icon-btn" type="button" title="Reload" aria-label="Reload">
                            <svg viewBox="0 0 20 20" aria-hidden="true">
                                <path d="M14.96 8A5 5 0 1 0 15 12h-1.6A3.5 3.5 0 1 1 12.94 8H10V6.5h5V11h-1.5V8Z" fill="currentColor" />
                            </svg>
                        </button>
                    </div>

                    <form id="navForm" className="omnibox-wrap">
                        <span id="siteBadge" className="site-badge" data-state="secure">Secure</span>
                        <input
                            id="addressInput"
                            className="address-input"
                            type="text"
                            placeholder="Search or enter address"
                            autocomplete="off"
                            spellcheck="false"
                        />
                        <button id="goBtn" className="go-btn" type="submit" aria-label="Go">
                            <svg viewBox="0 0 20 20" aria-hidden="true">
                                <path d="M5 10h8.19l-3.1 3.1 1.06 1.06L16.06 9.25 11.15 4.34 10.09 5.4l3.1 3.1H5V10Z" fill="currentColor" />
                            </svg>
                        </button>
                    </form>

                    <div className="toolbar-actions">
                        <button id="showBrowserViewBtn" className="toolbar-pill" type="button" title="Show Browser View" aria-pressed="true">
                            Browser
                        </button>
                        <button id="showHelpersViewBtn" className="toolbar-pill" type="button" title="Show Helpers View" aria-pressed="false">
                            Helpers
                        </button>
                        <button id="toggleLayersBtn" className="toolbar-pill" type="button" title="Toggle Layer Panel" aria-pressed="true">
                            Layers
                        </button>
                        <div className="profile-chip" aria-hidden="true">
                            <span className="profile-avatar">J</span>
                            <span className="profile-name">Workspace</span>
                        </div>
                    </div>
                </div>

                <div className="bookmark-bar">
                    <button className="bookmark-item" type="button" data-nav-url="https://jaclang.org/">
                        <span className="bookmark-favicon jac"></span>
                        <span>Jac Lang</span>
                    </button>
                    <button className="bookmark-item" type="button" data-nav-url="https://docs.jac-lang.org/">
                        <span className="bookmark-favicon docs"></span>
                        <span>Docs</span>
                    </button>
                    <button className="bookmark-item" type="button" data-nav-url="https://github.com/">
                        <span className="bookmark-favicon github"></span>
                        <span>GitHub</span>
                    </button>
                    <button className="bookmark-item" type="button" data-nav-url="https://platform.openai.com/docs/overview">
                        <span className="bookmark-favicon openai"></span>
                        <span>OpenAI</span>
                    </button>
                    <button className="bookmark-item" type="button" data-nav-url="https://www.electronjs.org/docs/latest/">
                        <span className="bookmark-favicon electron"></span>
                        <span>Electron</span>
                    </button>
                    <button className="bookmark-item" type="button" data-nav-url="https://duckduckgo.com/">
                        <span className="bookmark-favicon search"></span>
                        <span>Search</span>
                    </button>
                    <div className="bookmark-spacer"></div>
                    <button className="bookmark-folder" type="button">All Bookmarks</button>
                </div>

                <div className="progress-track">
                    <div id="progressBar" className="progress-bar"></div>
                </div>
            </header>

            <main id="viewport" className="viewport"></main>
            <section
                id="helpersPage"
                aria-label="Helpers"
                style={{
                    "display": "none",
                    "flex": "1 1 auto",
                    "minHeight": "0",
                    "padding": "20px 18px 18px",
                    "boxSizing": "border-box",
                    "background": "linear-gradient(180deg, #f8fbff 0%, #eef4ff 100%)",
                    "overflow": "auto"
                }}
            >
                <div
                    style={{
                        "display": "flex",
                        "flexDirection": "column",
                        "gap": "16px",
                        "minHeight": "100%"
                    }}
                >
                    <div
                        style={{
                            "display": "flex",
                            "alignItems": "center",
                            "justifyContent": "space-between",
                            "gap": "16px",
                            "padding": "20px 22px",
                            "borderRadius": "24px",
                            "border": "1px solid rgba(88, 116, 173, 0.12)",
                            "background": "rgba(255, 255, 255, 0.92)",
                            "boxShadow": "0 14px 34px rgba(52, 81, 126, 0.08)"
                        }}
                    >
                        <div style={{"display": "flex", "flexDirection": "column", "gap": "6px"}}>
                            <div className="layer-state-label" style={{"fontSize": "11px"}}>Local demo workspace</div>
                            <div style={{"color": "#183154", "fontSize": "28px", "fontWeight": "800", "letterSpacing": "-0.03em"}}>
                                Helpers
                            </div>
                            <div style={{"color": "#526885", "fontSize": "13px", "lineHeight": "1.6", "maxWidth": "720px"}}>
                                Review helper briefs, edit local instructions, and capture demo runs without leaving the live browser shell.
                            </div>
                        </div>
                        <button id="helpersPageCreateBtn" className="layer-btn" type="button" style={{"minWidth": "148px"}}>
                            Create Helper
                        </button>
                    </div>

                    <div
                        style={{
                            "display": "grid",
                            "gridTemplateColumns": "minmax(260px, 320px) minmax(0, 1fr)",
                            "gap": "16px",
                            "alignItems": "stretch",
                            "minHeight": "0",
                            "flex": "1 1 auto"
                        }}
                    >
                        <section
                            style={{
                                "display": "flex",
                                "flexDirection": "column",
                                "gap": "12px",
                                "minHeight": "0",
                                "padding": "18px",
                                "borderRadius": "24px",
                                "border": "1px solid rgba(88, 116, 173, 0.12)",
                                "background": "rgba(255, 255, 255, 0.94)",
                                "boxShadow": "0 14px 30px rgba(52, 81, 126, 0.07)"
                            }}
                        >
                            <div>
                                <div className="layer-state-label" style={{"fontSize": "11px"}}>All helpers</div>
                                <div style={{"marginTop": "4px", "color": "#1d2a3e", "fontSize": "18px", "fontWeight": "800"}}>Helper List</div>
                            </div>
                            <div
                                id="helpersPageList"
                                style={{
                                    "display": "flex",
                                    "flexDirection": "column",
                                    "gap": "10px",
                                    "minHeight": "0"
                                }}
                            >
                                No helpers yet. Create one to populate this local workspace.
                            </div>
                        </section>

                        <div
                            style={{
                                "display": "flex",
                                "flexDirection": "column",
                                "gap": "16px",
                                "minHeight": "0"
                            }}
                        >
                            <section
                                style={{
                                    "display": "flex",
                                    "flexDirection": "column",
                                    "gap": "12px",
                                    "padding": "18px",
                                    "borderRadius": "24px",
                                    "border": "1px solid rgba(88, 116, 173, 0.12)",
                                    "background": "rgba(255, 255, 255, 0.94)",
                                    "boxShadow": "0 14px 30px rgba(52, 81, 126, 0.07)"
                                }}
                            >
                                <div>
                                    <div className="layer-state-label" style={{"fontSize": "11px"}}>Selected helper</div>
                                    <div style={{"marginTop": "4px", "color": "#1d2a3e", "fontSize": "18px", "fontWeight": "800"}}>Detail</div>
                                </div>
                                <div
                                    id="helpersPageDetail"
                                    style={{
                                        "display": "flex",
                                        "flexDirection": "column",
                                        "gap": "12px"
                                    }}
                                >
                                    Select a helper to inspect its local instructions and run state.
                                </div>
                            </section>

                            <section
                                style={{
                                    "display": "flex",
                                    "flexDirection": "column",
                                    "gap": "12px",
                                    "padding": "18px",
                                    "borderRadius": "24px",
                                    "border": "1px solid rgba(88, 116, 173, 0.12)",
                                    "background": "rgba(255, 255, 255, 0.94)",
                                    "boxShadow": "0 14px 30px rgba(52, 81, 126, 0.07)"
                                }}
                            >
                                <div>
                                    <div className="layer-state-label" style={{"fontSize": "11px"}}>Recent runs</div>
                                    <div style={{"marginTop": "4px", "color": "#1d2a3e", "fontSize": "18px", "fontWeight": "800"}}>Results</div>
                                </div>
                                <div
                                    id="helpersPageResults"
                                    style={{
                                        "display": "flex",
                                        "flexDirection": "column",
                                        "gap": "10px"
                                    }}
                                >
                                    Run a helper to capture a local demo result history here.
                                </div>
                            </section>
                        </div>
                    </div>
                </div>
            </section>

            <aside id="layerPanel" className="layer-panel">
                <div className="layer-panel-header">
                    <div>
                        <div className="layer-panel-kicker">Layer Dev</div>
                        <div className="layer-panel-title">Automation Studio</div>
                    </div>
                    <span className="layer-status-pill">Ready</span>
                </div>
                <div className="layer-panel-actions">
                    <button id="startTraceBtn" className="layer-btn" type="button">Start Trace</button>
                    <button id="stopTraceBtn" className="layer-btn" type="button">Stop Trace</button>
                    <button id="compileTraceBtn" className="layer-btn" type="button">Compile</button>
                    <button id="planWorkflowBtn" className="layer-btn" type="button">Plan</button>
                </div>
                <div className="layer-panel-state">
                    <div className="layer-state-chip">
                        <span className="layer-state-label">Session</span>
                        <span id="sessionIdLabel">none</span>
                    </div>
                    <div className="layer-state-chip">
                        <span className="layer-state-label">Workflow</span>
                        <span id="workflowIdLabel">none</span>
                    </div>
                </div>
                <div
                    id="clawPanel"
                    className="layer-state-chip"
                    style={{
                        "gap": "8px",
                        "marginBottom": "12px",
                        "padding": "12px"
                    }}
                >
                    <div>
                        <div className="layer-state-label">Claw</div>
                        <div style={{"color": "#1d2a3e", "fontSize": "14px", "fontWeight": "800"}}>Truthful Planner</div>
                    </div>
                    <div
                        id="clawTranscript"
                        className="layer-log"
                        role="log"
                        aria-live="polite"
                        style={{
                            "minHeight": "120px",
                            "maxHeight": "164px",
                            "margin": "0",
                            "fontSize": "12px",
                            "lineHeight": "1.65"
                        }}
                    >
                        Claw is ready. Type the task below. Plan now uses the active live trace. Save draft keeps the text in this browser shell only.
                    </div>
                    <textarea
                        id="clawDraftInput"
                        rows={4}
                        placeholder="Describe the task for Claw. Plan now uses the active live trace."
                        spellcheck="false"
                        style={{
                            "width": "100%",
                            "minHeight": "78px",
                            "padding": "10px 12px",
                            "borderRadius": "14px",
                            "border": "1px solid rgba(88, 116, 173, 0.14)",
                            "background": "#ffffff",
                            "boxSizing": "border-box",
                            "color": "#1f345a",
                            "fontSize": "13px",
                            "fontWeight": "600",
                            "lineHeight": "1.55",
                            "resize": "vertical"
                        }}
                    ></textarea>
                    <div className="layer-panel-actions" style={{"marginBottom": "0"}}>
                        <button id="clawPlanBtn" className="layer-btn" type="button">Plan now</button>
                        <button id="clawSaveDraftBtn" className="layer-btn" type="button">Save draft</button>
                    </div>
                    <div
                        style={{
                            "display": "flex",
                            "flexDirection": "column",
                            "gap": "8px"
                        }}
                    >
                        <button id="createHelperBtn" className="layer-btn" type="button">Create Helper</button>
                        <div
                            style={{
                                "display": "flex",
                                "flexDirection": "column",
                                "gap": "6px",
                                "padding": "10px 12px",
                                "borderRadius": "14px",
                                "border": "1px solid rgba(88, 116, 173, 0.12)",
                                "background": "rgba(244, 247, 255, 0.82)"
                            }}
                        >
                            <div className="layer-state-label" style={{"fontSize": "11px"}}>Helpers</div>
                            <div
                                id="helperList"
                                style={{
                                    "display": "flex",
                                    "flexDirection": "column",
                                    "gap": "8px",
                                    "color": "#445a7d",
                                    "fontSize": "12px",
                                    "lineHeight": "1.55"
                                }}
                            >
                                No helpers yet. Create one to keep a lightweight assistant brief in this browser shell.
                            </div>
                        </div>
                    </div>
                    <div
                        id="clawStatus"
                        className="layer-state-label"
                        style={{
                            "fontSize": "11px",
                            "letterSpacing": "0.02em",
                            "lineHeight": "1.45",
                            "textTransform": "none"
                        }}
                    >
                        Add a task. Plan now also needs an active live trace.
                    </div>
                </div>
                <div
                    id="helperBuilderPanel"
                    className="layer-state-chip"
                    style={{
                        "display": "none",
                        "gap": "12px",
                        "marginBottom": "12px",
                        "padding": "16px",
                        "background": "linear-gradient(180deg, rgba(255, 255, 255, 0.96) 0%, rgba(237, 244, 255, 0.98) 100%)",
                        "border": "1px solid rgba(88, 116, 173, 0.14)",
                        "boxShadow": "0 16px 30px rgba(48, 77, 128, 0.08)"
                    }}
                >
                    <div style={{"display": "flex", "flexDirection": "column", "gap": "4px"}}>
                        <div className="layer-state-label">Create Helper</div>
                        <div style={{"color": "#1d2a3e", "fontSize": "16px", "fontWeight": "800"}}>Assistant Builder</div>
                        <div style={{"color": "#526885", "fontSize": "12px", "lineHeight": "1.55"}}>
                            Describe the helper once. The browser shell keeps the internal spec local and read-only for this demo session.
                        </div>
                    </div>
                    <div style={{"display": "flex", "flexDirection": "column", "gap": "6px"}}>
                        <label className="layer-state-label" htmlFor="helperNameInput" style={{"fontSize": "11px"}}>Name</label>
                        <input
                            id="helperNameInput"
                            type="text"
                            placeholder="Morning Brief"
                            spellcheck="false"
                            style={{
                                "width": "100%",
                                "padding": "11px 12px",
                                "borderRadius": "14px",
                                "border": "1px solid rgba(88, 116, 173, 0.14)",
                                "background": "#ffffff",
                                "boxSizing": "border-box",
                                "color": "#1f345a",
                                "fontSize": "14px",
                                "fontWeight": "600"
                            }}
                        />
                    </div>
                    <div style={{"display": "flex", "flexDirection": "column", "gap": "6px"}}>
                        <label className="layer-state-label" htmlFor="helperGoalInput" style={{"fontSize": "11px"}}>What do you want it to do</label>
                        <textarea
                            id="helperGoalInput"
                            rows={6}
                            placeholder="Summarize the newest Jac and Electron updates I should know before I start work."
                            spellcheck="false"
                            style={{
                                "width": "100%",
                                "minHeight": "136px",
                                "padding": "12px 14px",
                                "borderRadius": "16px",
                                "border": "1px solid rgba(88, 116, 173, 0.14)",
                                "background": "#ffffff",
                                "boxSizing": "border-box",
                                "color": "#1f345a",
                                "fontSize": "14px",
                                "fontWeight": "600",
                                "lineHeight": "1.6",
                                "resize": "vertical"
                            }}
                        ></textarea>
                    </div>
                    <div style={{"display": "flex", "flexDirection": "column", "gap": "6px"}}>
                        <label className="layer-state-label" htmlFor="helperFrequencySelect" style={{"fontSize": "11px"}}>How often</label>
                        <select
                            id="helperFrequencySelect"
                            style={{
                                "width": "100%",
                                "padding": "11px 12px",
                                "borderRadius": "14px",
                                "border": "1px solid rgba(88, 116, 173, 0.14)",
                                "background": "#ffffff",
                                "boxSizing": "border-box",
                                "color": "#1f345a",
                                "fontSize": "14px",
                                "fontWeight": "600"
                            }}
                        >
                            <option value="once">Just once</option>
                            <option value="browser_open">On browser open</option>
                            <option value="daily">Daily</option>
                            <option value="weekly">Weekly</option>
                        </select>
                    </div>
                    <div className="layer-panel-actions" style={{"marginBottom": "0"}}>
                        <button id="helperCreateBtn" className="layer-btn" type="button">Create</button>
                        <button id="helperCancelBtn" className="layer-btn" type="button">Cancel</button>
                    </div>
                </div>
                <pre id="layerLog" className="layer-log">Layer pipeline ready.</pre>
            </aside>
        </div>;
    }
}
