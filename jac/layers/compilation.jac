import os;
import sys;
import json;
import time;
import from typing { Any }

glob DATA_ROOT: str = "./jac/layer_data";
glob TRACE_DIR: str = DATA_ROOT + "/traces";
glob WORKFLOW_DIR: str = DATA_ROOT + "/workflows";

"""R: Return a simple timestamp string for workflow metadata.
M: Uses `time.time()` and string-casts for compatibility.
E: Timestamp is not formatted as ISO-8601.
"""
def timestamp_now() -> str {
    return str(time.time());
}

"""R: Ensure workflow output directory exists.
M: Creates `jac/layer_data/workflows` recursively.
E: Safe to call repeatedly.
"""
def ensure_workflow_dir() {
    os.makedirs(WORKFLOW_DIR, exist_ok=True);
}

"""R: Parse JSON payload passed from CLI args.
M: Reads args from position 2+, joins, and json-decodes.
E: Invalid/missing payload returns empty dict.
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

"""R: Build absolute trace file path from session id.
M: Joins trace directory and `<session_id>.json`.
E: Caller validates session id.
"""
def trace_file(session_id: str) -> str {
    return TRACE_DIR + "/" + session_id + ".json";
}

"""R: Build absolute workflow file path from workflow id.
M: Joins workflow directory and `<workflow_id>.json`.
E: Caller validates workflow id.
"""
def workflow_file(workflow_id: str) -> str {
    return WORKFLOW_DIR + "/" + workflow_id + ".json";
}

"""R: Read one JSON document from disk.
M: Loads and returns the object when it is a dict.
E: Missing/invalid files return empty dict.
"""
def read_json(path: str) -> dict[str, Any] {
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

"""R: Persist a JSON object to disk.
M: Writes pretty-printed JSON to path after ensuring parent dir.
E: Propagates filesystem failures to caller.
"""
def write_json(path: str, data: dict[str, Any]) {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    with open(path, "w") as file {
        json.dump(data, file, indent=2);
    }
}

"""R: Convert human labels into stable workflow input keys.
M: Lowercases text and keeps only alphanumeric/underscore separators.
E: Empty outputs default to `value`.
"""
def sanitize_key(label: str) -> str {
    cleaned = label.strip().lower();
    if not cleaned {
        return "value";
    }

    out: str = "";
    previous_was_sep: bool = False;

    for char in cleaned {
        is_letter = (char >= "a") and (char <= "z");
        is_digit = (char >= "0") and (char <= "9");
        if is_letter or is_digit {
            out = out + char;
            previous_was_sep = False;
        } elif not previous_was_sep {
            out = out + "_";
            previous_was_sep = True;
        }
    }

    if out.startswith("_") {
        out = out[1:];
    }
    if out.endswith("_") {
        out = out[:-1];
    }
    if not out {
        return "value";
    }
    return out;
}

"""R: Extract a safe target object from raw event fields.
M: Pulls text/label/role/name strings when target is a dict.
E: Missing fields resolve to empty strings.
"""
def normalize_target(raw_target: Any) -> dict[str, str] {
    target: dict[str, str] = {
        "text": "",
        "label": "",
        "role": "",
        "name": ""
    };

    if isinstance(raw_target, dict) {
        target["text"] = str(raw_target.get("text", ""));
        target["label"] = str(raw_target.get("label", ""));
        target["role"] = str(raw_target.get("role", ""));
        target["name"] = str(raw_target.get("name", ""));
    }

    return target;
}

"""R: Add an input key once while preserving insertion order.
M: Checks list membership before append.
E: Empty keys are ignored.
"""
def add_unique_input(keys: list[str], key: str) {
    if not key {
        return;
    }
    if key not in keys {
        keys.append(key);
    }
}

"""R: Compile observation events into basic workflow IR.
M: Maps navigate/click/input events to goto/click/fill steps.
E: Unknown or malformed events are skipped.
"""
def compile_steps(raw_events: list[Any]) -> dict[str, Any] {
    steps: list[Any] = [];
    inputs: list[str] = [];

    for raw_event in raw_events {
        if not isinstance(raw_event, dict) {
            continue;
        }

        event_type = str(raw_event.get("type", ""));

        if event_type == "navigate" {
            url = str(raw_event.get("url", ""));
            if url {
                steps.append({"type": "goto", "url": url});
            }
            continue;
        }

        if event_type == "click" {
            normalized_target = normalize_target(raw_event.get("target", {}));
            steps.append({
                "type": "click",
                "target": {
                    "text": normalized_target["text"],
                    "label": normalized_target["label"],
                    "role": normalized_target["role"]
                }
            });
            continue;
        }

        if event_type == "input" {
            normalized_target = normalize_target(raw_event.get("target", {}));
            label = normalized_target["label"];
            if not label {
                label = normalized_target["name"];
            }
            if not label {
                label = "value";
            }

            input_key = sanitize_key(label);
            add_unique_input(inputs, input_key);

            steps.append({
                "type": "fill",
                "target": {"label": label},
                "value_source": "input." + input_key
            });
        }
    }

    return {
        "inputs": inputs,
        "steps": steps
    };
}

"""R: Compile one persisted observation trace into workflow JSON.
M: Loads trace file, transforms events, writes workflow file.
E: Missing session or trace returns explicit errors.
"""
def build_workflow(payload: dict[str, Any]) -> dict[str, Any] {
    ensure_workflow_dir();

    session_id = str(payload.get("session_id", ""));
    if not session_id {
        return {"ok": False, "error": "session_id is required"};
    }

    trace_data = read_json(trace_file(session_id));
    if not trace_data {
        return {"ok": False, "error": "trace not found", "session_id": session_id};
    }

    raw_events: list[Any] = [];
    candidate_events = trace_data.get("events", []);
    if isinstance(candidate_events, list) {
        raw_events = candidate_events;
    }

    compile_result = compile_steps(raw_events);
    workflow_id = "wf_" + session_id;

    title = str(trace_data.get("title", ""));
    if not title {
        title = "Workflow " + session_id;
    }

    workflow_data = {
        "workflow_id": workflow_id,
        "source_session_id": session_id,
        "created_at": timestamp_now(),
        "title": title,
        "inputs": compile_result["inputs"],
        "steps": compile_result["steps"],
        "meta": {
            "event_count": len(raw_events),
            "step_count": len(compile_result["steps"])
        }
    };

    workflow_path = workflow_file(workflow_id);
    write_json(workflow_path, workflow_data);

    return {
        "ok": True,
        "workflow_id": workflow_id,
        "workflow_file": workflow_path,
        "input_count": len(compile_result["inputs"]),
        "step_count": len(compile_result["steps"])
    };
}

"""R: Fetch one compiled workflow document by id.
M: Reads workflow JSON from disk.
E: Missing workflow id/file returns explicit errors.
"""
def get_workflow(payload: dict[str, Any]) -> dict[str, Any] {
    workflow_id = str(payload.get("workflow_id", ""));
    if not workflow_id {
        return {"ok": False, "error": "workflow_id is required"};
    }

    workflow_data = read_json(workflow_file(workflow_id));
    if not workflow_data {
        return {"ok": False, "error": "workflow not found", "workflow_id": workflow_id};
    }

    return {
        "ok": True,
        "workflow": workflow_data
    };
}

"""R: Route a layer command to compilation handlers.
M: Maps command to build/get operations.
E: Unknown commands return usage metadata.
"""
def dispatch(command: str, payload: dict[str, Any]) -> dict[str, Any] {
    if command == "build" {
        return build_workflow(payload);
    }

    if command == "get" {
        return get_workflow(payload);
    }

    return {
        "ok": False,
        "error": "unknown command",
        "valid_commands": ["build", "get"]
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
