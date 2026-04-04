import os;
import sys;
import json;
import time;
import from typing { Any }

glob DATA_ROOT: str = "./jac/layer_data";
glob TRACE_DIR: str = DATA_ROOT + "/traces";

"""R: Return a simple timestamp string for persisted layer records.
M: Uses `time.time()` and string-casts for broad Jac compatibility.
E: Resolution is seconds with fractional precision.
"""
def timestamp_now() -> str {
    return str(time.time());
}

"""R: Ensure observation trace storage path exists.
M: Creates `jac/layer_data/traces` recursively.
E: Safe to call repeatedly.
"""
def ensure_trace_dir() {
    os.makedirs(TRACE_DIR, exist_ok=True);
}

"""R: Parse JSON payload passed via CLI args.
M: Joins argv entries from index 2 and decodes JSON.
E: Invalid JSON returns an empty dict.
"""
def parse_payload() -> dict[str, Any] {
    raw_payload: str = "{}";
    if len(sys.argv) > 2 {
        raw_payload = " ".join(sys.argv[2:]);
    }

    try {
        parsed = json.loads(raw_payload);
        if isinstance(parsed, dict) {
            return parsed;
        }
        return {};
    } except json.JSONDecodeError {
        return {};
    }
}

"""R: Build trace file path for one observation session.
M: Joins trace dir with `<session_id>.json`.
E: Caller validates session id shape.
"""
def trace_file(session_id: str) -> str {
    return TRACE_DIR + "/" + session_id + ".json";
}

"""R: Read one persisted observation trace from disk.
M: Loads JSON and returns dict payload when valid.
E: Missing/invalid files map to empty dict.
"""
def read_trace(session_id: str) -> dict[str, Any] {
    path = trace_file(session_id);
    if not os.path.exists(path) {
        return {};
    }

    try {
        with open(path, "r") as file {
            parsed = json.load(file);
            if isinstance(parsed, dict) {
                return parsed;
            }
        }
    } except json.JSONDecodeError {
        return {};
    } except OSError {
        return {};
    }

    return {};
}

"""R: Persist one observation trace JSON record.
M: Writes formatted JSON to the session file path.
E: Propagates filesystem errors to caller.
"""
def write_trace(session_id: str, trace_data: dict[str, Any]) {
    ensure_trace_dir();
    with open(trace_file(session_id), "w") as file {
        json.dump(trace_data, file, indent=2);
    }
}

"""R: Create deterministic session ids for trace files.
M: Prefixes a time-derived numeric stamp with `sess_`.
E: Collisions are unlikely but possible under extreme concurrency.
"""
def new_session_id() -> str {
    return "sess_" + str(time.time()).replace(".", "");
}

"""R: Convert untyped event payloads into normalized observation events.
M: Copies only supported fields and enforces string/dict defaults.
E: Unknown event types are preserved as `unknown`.
"""
def normalize_event(raw_event: Any, default_url: str) -> dict[str, Any] {
    event_type: str = "unknown";
    event_url: str = default_url;
    event_value: str = "";
    target: dict[str, Any] = {};
    meta: dict[str, Any] = {};

    if isinstance(raw_event, dict) {
        if raw_event.get("type", "") {
            event_type = str(raw_event.get("type", ""));
        }
        if raw_event.get("url", "") {
            event_url = str(raw_event.get("url", ""));
        }
        if "value" in raw_event {
            event_value = str(raw_event.get("value", ""));
        }

        raw_target = raw_event.get("target", {});
        if isinstance(raw_target, dict) {
            target = raw_target;
        }

        raw_meta = raw_event.get("meta", {});
        if isinstance(raw_meta, dict) {
            meta = raw_meta;
        }
    }

    return {
        "type": event_type,
        "url": event_url,
        "value": event_value,
        "target": target,
        "meta": meta,
        "recorded_at": timestamp_now()
    };
}

"""R: Start a new observation recording session.
M: Builds initial trace payload and persists it to disk.
E: Optional `session_id` can overwrite an existing session file.
"""
def start_trace(payload: dict[str, Any]) -> dict[str, Any] {
    ensure_trace_dir();

    session_id = str(payload.get("session_id", ""));
    if not session_id {
        session_id = new_session_id();
    }

    title = str(payload.get("title", "Manual Trace"));
    source_url = str(payload.get("url", ""));

    trace_data = {
        "session_id": session_id,
        "title": title,
        "source_url": source_url,
        "status": "recording",
        "started_at": timestamp_now(),
        "updated_at": timestamp_now(),
        "events": []
    };

    write_trace(session_id, trace_data);

    return {
        "ok": True,
        "session_id": session_id,
        "trace_file": trace_file(session_id)
    };
}

"""R: Append one event to an active observation session.
M: Loads trace file, normalizes event payload, and rewrites JSON.
E: Missing session id or trace file returns explicit errors.
"""
def append_trace_event(payload: dict[str, Any]) -> dict[str, Any] {
    session_id = str(payload.get("session_id", ""));
    if not session_id {
        return {"ok": False, "error": "session_id is required"};
    }

    trace_data = read_trace(session_id);
    if not trace_data {
        return {"ok": False, "error": "trace not found", "session_id": session_id};
    }

    events: list[Any] = [];
    raw_events = trace_data.get("events", []);
    if isinstance(raw_events, list) {
        events = raw_events;
    }

    normalized = normalize_event(payload.get("event", {}), str(trace_data.get("source_url", "")));
    events.append(normalized);

    trace_data["events"] = events;
    trace_data["updated_at"] = timestamp_now();
    write_trace(session_id, trace_data);

    return {
        "ok": True,
        "session_id": session_id,
        "event_count": len(events)
    };
}

"""R: Mark an observation session as stopped.
M: Loads trace by id, updates status fields, and saves file.
E: Safe to call more than once for the same session.
"""
def stop_trace(payload: dict[str, Any]) -> dict[str, Any] {
    session_id = str(payload.get("session_id", ""));
    if not session_id {
        return {"ok": False, "error": "session_id is required"};
    }

    trace_data = read_trace(session_id);
    if not trace_data {
        return {"ok": False, "error": "trace not found", "session_id": session_id};
    }

    trace_data["status"] = "stopped";
    trace_data["stopped_at"] = timestamp_now();
    trace_data["updated_at"] = timestamp_now();
    write_trace(session_id, trace_data);

    events: list[Any] = [];
    raw_events = trace_data.get("events", []);
    if isinstance(raw_events, list) {
        events = raw_events;
    }

    return {
        "ok": True,
        "session_id": session_id,
        "event_count": len(events)
    };
}

"""R: Fetch one stored observation trace by session id.
M: Loads trace JSON and returns the parsed dict.
E: Missing sessions return explicit errors.
"""
def get_trace(payload: dict[str, Any]) -> dict[str, Any] {
    session_id = str(payload.get("session_id", ""));
    if not session_id {
        return {"ok": False, "error": "session_id is required"};
    }

    trace_data = read_trace(session_id);
    if not trace_data {
        return {"ok": False, "error": "trace not found", "session_id": session_id};
    }

    return {
        "ok": True,
        "trace": trace_data
    };
}

"""R: Route a layer command to its observation operation.
M: Maps command text to start/append/stop/get handlers.
E: Unknown commands return a usage payload.
"""
def dispatch(command: str, payload: dict[str, Any]) -> dict[str, Any] {
    if command == "start" {
        return start_trace(payload);
    }

    if command == "append" {
        return append_trace_event(payload);
    }

    if command == "stop" {
        return stop_trace(payload);
    }

    if command == "get" {
        return get_trace(payload);
    }

    return {
        "ok": False,
        "error": "unknown command",
        "valid_commands": ["start", "append", "stop", "get"]
    };
}

with entry {
    command: str = "";
    if len(sys.argv) > 1 {
        command = str(sys.argv[1]);
    }

    payload = parse_payload();
    result = dispatch(command, payload);
    print(json.dumps(result));
}
