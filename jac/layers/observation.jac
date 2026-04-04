import os;
import sys;
import json;
import time;
import from typing { Any }

glob DATA_ROOT: str = "./jac/layer_data";
glob TRACE_DIR: str = DATA_ROOT + "/traces";
glob DEDUPE_WINDOW_SECONDS: float = 0.7;

glob ALLOWED_EVENT_TYPES: list[str] = [
    "navigate",
    "click",
    "input",
    "submit",
    "network",
    "page_ready",
    "tab_created",
    "tab_closed",
    "tab_switched",
    "unknown"
];

glob SENSITIVE_HINTS: list[str] = [
    "password",
    "passcode",
    "token",
    "secret",
    "auth",
    "session",
    "cookie",
    "credit",
    "card",
    "ssn"
];

"""R: Return a timestamp string for persisted layer records.
M: Uses `time.time()` and string-casts for broad Jac compatibility.
E: Resolution is seconds with fractional precision.
"""
def timestamp_now() -> str {
    return str(time.time());
}

"""R: Coerce values to bounded strings for safe trace persistence.
M: String-casts, trims, and caps length to avoid oversized events.
E: None maps to empty string.
"""
def safe_str(value: Any, max_len: int) -> str {
    text = str(value or "").strip();
    if len(text) > max_len {
        return text[:max_len];
    }
    return text;
}

"""R: Parse a float from arbitrary input.
M: Attempts `float(raw)` and falls back to zero on invalid values.
E: Invalid numbers return 0.0.
"""
def safe_float(raw: Any) -> float {
    try {
        return float(raw);
    } except ValueError {
        return 0.0;
    }
}

"""R: Ensure observation trace storage path exists.
M: Creates `jac/layer_data/traces` recursively.
E: Safe to call repeatedly.
"""
def ensure_trace_dir() {
    os.makedirs(TRACE_DIR, exist_ok=True);
}

"""R: Validate session id format for filesystem-safe trace names.
M: Allows letters, digits, `_`, and `-`.
E: Empty ids are invalid.
"""
def is_valid_session_id(session_id: str) -> bool {
    if not session_id {
        return False;
    }

    for char in session_id {
        is_lower = (char >= "a") and (char <= "z");
        is_upper = (char >= "A") and (char <= "Z");
        is_digit = (char >= "0") and (char <= "9");
        if not (is_lower or is_upper or is_digit or char == "_" or char == "-") {
            return False;
        }
    }
    return True;
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

"""R: Check whether an event type is in the allowed schema.
M: Uses fixed allow-list used by the observation layer.
E: Unknown types are treated as invalid.
"""
def is_allowed_event_type(event_type: str) -> bool {
    return event_type in ALLOWED_EVENT_TYPES;
}

"""R: Normalize target payload to stable string fields.
M: Copies supported target keys with bounded string lengths.
E: Missing/non-dict targets produce empty defaults.
"""
def normalize_target(raw_target: Any) -> dict[str, str] {
    target: dict[str, str] = {
        "tag": "",
        "id": "",
        "name": "",
        "role": "",
        "type": "",
        "label": "",
        "text": "",
        "placeholder": "",
        "class_name": ""
    };

    if not isinstance(raw_target, dict) {
        return target;
    }

    target["tag"] = safe_str(raw_target.get("tag", ""), 60).lower();
    target["id"] = safe_str(raw_target.get("id", ""), 120);
    target["name"] = safe_str(raw_target.get("name", ""), 120);
    target["role"] = safe_str(raw_target.get("role", ""), 80).lower();
    target["type"] = safe_str(raw_target.get("type", ""), 40).lower();
    target["label"] = safe_str(raw_target.get("label", ""), 140);
    target["text"] = safe_str(raw_target.get("text", ""), 180);
    target["placeholder"] = safe_str(raw_target.get("placeholder", ""), 140);
    target["class_name"] = safe_str(raw_target.get("class_name", ""), 220);

    return target;
}

"""R: Normalize metadata payload for consistent analytics fields.
M: Copies known metadata keys and string/number coercions.
E: Unknown metadata keys are dropped for schema stability.
"""
def normalize_meta(raw_meta: Any) -> dict[str, Any] {
    normalized: dict[str, Any] = {
        "source": "",
        "trigger": "",
        "tab_id": "",
        "kind": "",
        "method": "",
        "request_url": "",
        "status": 0,
        "ok": False,
        "duration_ms": 0,
        "error": ""
    };

    if not isinstance(raw_meta, dict) {
        return normalized;
    }

    normalized["source"] = safe_str(raw_meta.get("source", ""), 60);
    normalized["trigger"] = safe_str(raw_meta.get("trigger", ""), 60);
    normalized["tab_id"] = safe_str(raw_meta.get("tab_id", ""), 80);
    normalized["kind"] = safe_str(raw_meta.get("kind", ""), 40);
    normalized["method"] = safe_str(raw_meta.get("method", ""), 20).upper();
    normalized["request_url"] = safe_str(raw_meta.get("request_url", ""), 300);
    normalized["status"] = int(raw_meta.get("status", 0));
    normalized["ok"] = bool(raw_meta.get("ok", False));
    normalized["duration_ms"] = int(raw_meta.get("duration_ms", 0));
    normalized["error"] = safe_str(raw_meta.get("error", ""), 160);

    return normalized;
}

"""R: Determine if target hints suggest sensitive field content.
M: Checks target type and common secret-related label/name patterns.
E: Heuristic may over-redact ambiguous fields.
"""
def is_sensitive_target(target: dict[str, str]) -> bool {
    if target["type"] == "password" {
        return True;
    }

    haystack = (
        target["label"] + " " + target["name"] + " " + target["id"] + " " + target["placeholder"]
    ).lower();

    for hint in SENSITIVE_HINTS {
        if hint in haystack {
            return True;
        }
    }

    return False;
}

"""R: Convert untyped payloads into normalized observation events.
M: Enforces schema for type/url/target/meta and redacts sensitive values.
E: Unknown types are stored as `unknown`.
"""
def normalize_event(raw_event: Any, default_url: str) -> dict[str, Any] {
    event_type: str = "unknown";
    event_url: str = safe_str(default_url, 300);
    event_value: str = "";
    target: dict[str, str] = normalize_target({});
    meta: dict[str, Any] = normalize_meta({});

    if isinstance(raw_event, dict) {
        event_type_candidate = safe_str(raw_event.get("type", ""), 40).lower();
        if is_allowed_event_type(event_type_candidate) {
            event_type = event_type_candidate;
        }

        raw_url = safe_str(raw_event.get("url", ""), 300);
        if raw_url {
            event_url = raw_url;
        }

        target = normalize_target(raw_event.get("target", {}));
        meta = normalize_meta(raw_event.get("meta", {}));

        if "value" in raw_event {
            event_value = safe_str(raw_event.get("value", ""), 300);
        }
    }

    if is_sensitive_target(target) {
        event_value = "__redacted__";
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

"""R: Build a stable comparison signature for event dedupe.
M: Concatenates key event fields likely to indicate duplicate actions.
E: Signature intentionally ignores timestamp and minor non-core metadata.
"""
def event_signature(event_data: dict[str, Any]) -> str {
    target = normalize_target(event_data.get("target", {}));
    meta = normalize_meta(event_data.get("meta", {}));

    return (
        safe_str(event_data.get("type", ""), 40) + "|" +
        safe_str(event_data.get("url", ""), 300) + "|" +
        safe_str(event_data.get("value", ""), 300) + "|" +
        target["tag"] + "|" +
        target["id"] + "|" +
        target["name"] + "|" +
        target["role"] + "|" +
        target["type"] + "|" +
        target["label"] + "|" +
        target["text"] + "|" +
        meta["source"] + "|" +
        meta["trigger"] + "|" +
        meta["tab_id"] + "|" +
        meta["kind"] + "|" +
        meta["method"] + "|" +
        meta["request_url"] + "|" +
        str(meta["status"])
    );
}

"""R: Detect near-identical adjacent events to reduce trace noise.
M: Compares normalized signatures and timestamp delta.
E: Returns false when timestamps are missing or unparsable.
"""
def is_duplicate_event(last_event: dict[str, Any], new_event: dict[str, Any]) -> bool {
    last_time = safe_float(last_event.get("recorded_at", "0"));
    new_time = safe_float(new_event.get("recorded_at", "0"));
    if last_time <= 0.0 or new_time <= 0.0 {
        return False;
    }

    if abs(new_time - last_time) > DEDUPE_WINDOW_SECONDS {
        return False;
    }

    return event_signature(last_event) == event_signature(new_event);
}

"""R: Start a new observation recording session.
M: Builds initial trace payload and persists it to disk.
E: Optional `session_id` can overwrite an existing session file.
"""
def start_trace(payload: dict[str, Any]) -> dict[str, Any] {
    ensure_trace_dir();

    session_id = safe_str(payload.get("session_id", ""), 120);
    if not session_id {
        session_id = new_session_id();
    }

    if not is_valid_session_id(session_id) {
        return {"ok": False, "error": "invalid session_id format"};
    }

    title = safe_str(payload.get("title", "Manual Trace"), 140);
    source_url = safe_str(payload.get("url", ""), 300);

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
M: Loads trace file, normalizes payload, dedupes noise, and rewrites JSON.
E: Missing session id or trace file returns explicit errors.
"""
def append_trace_event(payload: dict[str, Any]) -> dict[str, Any] {
    session_id = safe_str(payload.get("session_id", ""), 120);
    if not session_id {
        return {"ok": False, "error": "session_id is required"};
    }
    if not is_valid_session_id(session_id) {
        return {"ok": False, "error": "invalid session_id format"};
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

    normalized = normalize_event(payload.get("event", {}), safe_str(trace_data.get("source_url", ""), 300));

    if events and isinstance(events[-1], dict) and is_duplicate_event(events[-1], normalized) {
        trace_data["updated_at"] = timestamp_now();
        write_trace(session_id, trace_data);
        return {
            "ok": True,
            "session_id": session_id,
            "event_count": len(events),
            "deduped": True
        };
    }

    events.append(normalized);
    trace_data["events"] = events;
    trace_data["updated_at"] = timestamp_now();
    write_trace(session_id, trace_data);

    return {
        "ok": True,
        "session_id": session_id,
        "event_count": len(events),
        "deduped": False
    };
}

"""R: Mark an observation session as stopped.
M: Loads trace by id, updates status fields, and saves file.
E: Safe to call more than once for the same session.
"""
def stop_trace(payload: dict[str, Any]) -> dict[str, Any] {
    session_id = safe_str(payload.get("session_id", ""), 120);
    if not session_id {
        return {"ok": False, "error": "session_id is required"};
    }
    if not is_valid_session_id(session_id) {
        return {"ok": False, "error": "invalid session_id format"};
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
    session_id = safe_str(payload.get("session_id", ""), 120);
    if not session_id {
        return {"ok": False, "error": "session_id is required"};
    }
    if not is_valid_session_id(session_id) {
        return {"ok": False, "error": "invalid session_id format"};
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
