"""
Jac-native Kimi runtime state helpers.

Purpose:
- Keep browser-owned Kimi lifecycle state in one small JSON file.
- Expose pure functions that other Jac modules can import safely.
- Avoid CLI side effects when compilation imports runtime status.
"""

import os;
import json;
import time;
import from typing { Any }
import from jac.llm.kimi_client { resolve_kimi_compile_config }

glob DATA_ROOT: str = "./jac/layer_data";
glob LLM_DIR: str = DATA_ROOT + "/llm";
glob LLM_RUNTIME_FILE: str = LLM_DIR + "/runtime.json";

"""R: Return a simple string timestamp for runtime state transitions.
M: Uses `time.time()` for compatibility with the rest of the Jac layer files.
E: Precision is sufficient for startup/shutdown tracing.
"""
def timestamp_now() -> str {
    return str(time.time());
}

"""R: Ensure the LLM runtime storage directory exists.
M: Creates `jac/layer_data/llm` recursively.
E: Safe to call multiple times.
"""
def ensure_llm_dir() {
    os.makedirs(LLM_DIR, exist_ok=True);
}

"""R: Build the default inactive runtime state payload.
M: Returns a consistent shape even before the browser has started once.
E: `reason` is caller-controlled so status messages remain explicit.
"""
def default_runtime_state(reason: str = "Kimi runtime inactive") -> dict[str, Any] {
    return {
        "active": False,
        "provider": "kimi",
        "model": "",
        "thinking_mode": "",
        "started_at": "",
        "stopped_at": "",
        "updated_at": timestamp_now(),
        "reason": reason,
        "source": ""
    };
}

"""R: Read the persisted browser-owned Kimi runtime state from disk.
M: Loads JSON when present and falls back to a normalized inactive shape otherwise.
E: Invalid files degrade to inactive state rather than failing callers.
"""
def read_runtime_state() -> dict[str, Any] {
    if not os.path.exists(LLM_RUNTIME_FILE) {
        return default_runtime_state("Kimi runtime has not started yet");
    }

    try {
        with open(LLM_RUNTIME_FILE, "r") as file {
            parsed = json.load(file);
            if isinstance(parsed, dict) {
                return {
                    "active": bool(parsed.get("active", False)),
                    "provider": str(parsed.get("provider", "kimi")),
                    "model": str(parsed.get("model", "")),
                    "thinking_mode": str(parsed.get("thinking_mode", "")),
                    "started_at": str(parsed.get("started_at", "")),
                    "stopped_at": str(parsed.get("stopped_at", "")),
                    "updated_at": str(parsed.get("updated_at", timestamp_now())),
                    "reason": str(parsed.get("reason", "")),
                    "source": str(parsed.get("source", ""))
                };
            }
        }
    } except json.JSONDecodeError {
        return default_runtime_state("Kimi runtime state was unreadable");
    } except OSError {
        return default_runtime_state("Kimi runtime state could not be read");
    }

    return default_runtime_state("Kimi runtime state was invalid");
}

"""R: Persist one normalized runtime state record.
M: Writes formatted JSON to the browser-owned runtime state path.
E: Filesystem errors are surfaced to the caller.
"""
def write_runtime_state(state: dict[str, Any]) {
    ensure_llm_dir();
    with open(LLM_RUNTIME_FILE, "w") as file {
        json.dump(state, file, indent=2);
    }
}

"""R: Return the current browser-owned runtime status for Kimi.
M: Reads the persisted state file and normalizes its fields.
E: Missing state yields an inactive status payload.
"""
def current_runtime_state() -> dict[str, Any] {
    return read_runtime_state();
}

"""R: Activate Kimi compile enrichment for the current browser lifecycle.
M: Resolves config, writes an active state when credentials are valid, and returns status.
E: Missing or placeholder credentials produce an inactive status with a clear reason.
"""
def start_runtime(payload: dict[str, Any]) -> dict[str, Any] {
    source: str = str(payload.get("source", "browser_startup"));
    config: dict[str, Any] = resolve_kimi_compile_config();

    state: dict[str, Any] = default_runtime_state("Kimi runtime inactive");
    state["provider"] = "kimi";
    state["model"] = str(config.get("model", ""));
    state["thinking_mode"] = str(config.get("thinking_mode", ""));
    state["source"] = source;
    state["updated_at"] = timestamp_now();

    if bool(config.get("enabled", False)) {
        state["active"] = True;
        state["started_at"] = timestamp_now();
        state["stopped_at"] = "";
        state["reason"] = "Kimi runtime ready for compile-time enrichment";
    } else {
        state["active"] = False;
        state["reason"] = "Kimi config missing, placeholder, or compile use disabled";
    }

    write_runtime_state(state);
    return {"ok": True, "runtime": state};
}

"""R: Deactivate the browser-owned Kimi runtime.
M: Preserves provider/model info while marking the runtime inactive and timestamping shutdown.
E: Safe to call even if the runtime was never activated.
"""
def stop_runtime(payload: dict[str, Any]) -> dict[str, Any] {
    source: str = str(payload.get("source", "browser_close"));
    state: dict[str, Any] = current_runtime_state();
    state["active"] = False;
    state["updated_at"] = timestamp_now();
    state["stopped_at"] = timestamp_now();
    state["source"] = source;
    state["reason"] = "Kimi runtime stopped on browser shutdown";

    write_runtime_state(state);
    return {"ok": True, "runtime": state};
}
