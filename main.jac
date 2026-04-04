"""Jac client entry point for the browser shell migration."""

cl import ".styles.css";
cl import from .components.BrowserShell { BrowserShell }

cl {
    """R: Mount the Jac-authored browser shell.
    M: Returns the top-level Electron browser shell component.
    E: Keeps the root thin so runtime behavior lives in focused Jac modules.
    """
    def:pub app() -> JsxElement {
        return <BrowserShell />;
    }
}
