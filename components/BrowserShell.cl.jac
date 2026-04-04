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
                <pre id="layerLog" className="layer-log">Layer pipeline ready.</pre>
            </aside>
        </div>;
    }
}
