import os;
import sys;
import json;
import time;
import from typing { Any }

glob DATA_ROOT: str = "./jac/layer_data";
glob WORKFLOW_DIR: str = DATA_ROOT + "/workflows";

"""R: Return a simple timestamp string for planner metadata.
M: Uses `time.time()` and string-casts for compatibility.
E: Timestamp format is epoch-like string, not ISO.
"""
def timestamp_now() -> str {
    return str(time.time());
}

"""R: Parse JSON payload passed from CLI command args.
M: Joins args index 2+ and decodes JSON object payload.
E: Invalid/non-dict payload returns empty dict.
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

"""R: Build workflow file path for one workflow id.
M: Joins workflow dir and `<workflow_id>.json`.
E: Caller validates workflow id.
"""
def workflow_file(workflow_id: str) -> str {
    return WORKFLOW_DIR + "/" + workflow_id + ".json";
}

"""R: Read one workflow JSON document from disk.
M: Loads file and returns dict payload if valid.
E: Missing/invalid documents return empty dict.
"""
def read_workflow(workflow_id: str) -> dict[str, Any] {
    path = workflow_file(workflow_id);
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

"""R: Add unresolved input keys once while preserving order.
M: Appends only when key is non-empty and not already present.
E: Mutates list in place for planner efficiency.
"""
def add_unique_key(values: list[str], key: str) {
    if not key {
        return;
    }
    if key not in values {
        values.append(key);
    }
}

"""R: Resolve one workflow step with runtime inputs.
M: Copies step dict and injects `value` for fill steps using `value_source`.
E: Missing runtime values are tracked in unresolved input list.
"""
def resolve_step(step: dict[str, Any], run_inputs: dict[str, Any], unresolved: list[str]) -> dict[str, Any] {
    resolved_step: dict[str, Any] = dict(step);
    step_type = str(step.get("type", ""));

    if step_type != "fill" {
        return resolved_step;
    }

    value_source = str(step.get("value_source", ""));
    if not value_source.startswith("input.") {
        return resolved_step;
    }

    input_key = value_source[6:];
    runtime_value = str(run_inputs.get(input_key, ""));
    resolved_step["value"] = runtime_value;

    if not runtime_value {
        add_unique_key(unresolved, input_key);
    }

    return resolved_step;
}

"""R: Build a dry-run execution plan from a workflow + runtime inputs.
M: Resolves each step deterministically and tracks unresolved input placeholders.
E: Non-dict steps are ignored to avoid planner crashes.
"""
def build_plan(workflow: dict[str, Any], run_inputs: dict[str, Any]) -> dict[str, Any] {
    planned_steps: list[Any] = [];
    unresolved_inputs: list[str] = [];

    raw_steps: list[Any] = [];
    candidate_steps = workflow.get("steps", []);
    if isinstance(candidate_steps, list) {
        raw_steps = candidate_steps;
    }

    for raw_step in raw_steps {
        if not isinstance(raw_step, dict) {
            continue;
        }

        resolved = resolve_step(raw_step, run_inputs, unresolved_inputs);
        planned_steps.append(resolved);
    }

    return {
        "planned_steps": planned_steps,
        "unresolved_inputs": unresolved_inputs
    };
}

"""R: Build execution plan output for one compiled workflow.
M: Loads workflow, resolves input placeholders, and returns planner payload.
E: Missing workflow id/file returns explicit errors.
"""
def plan_workflow(payload: dict[str, Any]) -> dict[str, Any] {
    workflow_id = str(payload.get("workflow_id", ""));
    if not workflow_id {
        return {"ok": False, "error": "workflow_id is required"};
    }

    run_inputs: dict[str, Any] = {};
    candidate_inputs = payload.get("inputs", {});
    if isinstance(candidate_inputs, dict) {
        run_inputs = candidate_inputs;
    }

    workflow = read_workflow(workflow_id);
    if not workflow {
        return {"ok": False, "error": "workflow not found", "workflow_id": workflow_id};
    }

    plan = build_plan(workflow, run_inputs);

    return {
        "ok": True,
        "workflow_id": workflow_id,
        "planned_at": timestamp_now(),
        "step_count": len(plan["planned_steps"]),
        "unresolved_inputs": plan["unresolved_inputs"],
        "planned_steps": plan["planned_steps"]
    };
}

"""R: Route a layer command to execution planner operations.
M: Supports `plan` and alias `dry_run` with shared implementation.
E: Unknown commands return a usage payload.
"""
def dispatch(command: str, payload: dict[str, Any]) -> dict[str, Any] {
    if command == "plan" {
        return plan_workflow(payload);
    }

    if command == "dry_run" {
        return plan_workflow(payload);
    }

    return {
        "ok": False,
        "error": "unknown command",
        "valid_commands": ["plan", "dry_run"]
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
