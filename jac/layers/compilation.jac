"""
Jac-native compilation layer.

Pipeline:  RecordingSession  →  clean_trace  →  heuristic_compile
           →  (optional model hook)  →  validate_workflow  →  Workflow IR

Behavioral reference: src/compilation/ TypeScript implementation.
Compiler version: 0.2.0
"""

import os;
import sys;
import json;
import re;
import time;
import uuid;
import from typing { Any }
import from urllib.parse { urlparse }

# ============================================================
# CONSTANTS
# ============================================================

glob DATA_ROOT: str = "./jac/layer_data";
glob TRACE_DIR: str = DATA_ROOT + "/traces";
glob WORKFLOW_DIR: str = DATA_ROOT + "/workflows";
glob COMPILER_VERSION: str = "0.2.0";
glob SAFETY_PATTERNS: list[str] = [
    "submit", "confirm", "place order", "pay", "delete", "remove"
];

# ============================================================
# UTILITIES
# ============================================================

"""Generate a prefixed random ID from a UUID v4."""
def new_id(prefix: str) -> str {
    uid: str = str(uuid.uuid4()).replace("-", "");
    return prefix + uid[:16];
}

def new_workflow_id() -> str { return new_id("wf_"); }
def new_step_id() -> str { return new_id("step_"); }
def new_input_id() -> str { return new_id("inp_"); }
def new_rule_id() -> str { return new_id("rule_"); }

"""Return current UTC time as ISO-8601 string (seconds precision)."""
def timestamp_now() -> str {
    t: Any = time.gmtime();
    result: str = time.strftime("%Y-%m-%dT%H:%M:%SZ", t);
    return result;
}

"""Parse ISO-8601 timestamp to approximate Unix milliseconds.
Uses time.mktime (local time) — only used for within-session delta comparisons,
so the local-time offset is constant and cancels out.
"""
def parse_ts(iso: str) -> float {
    try {
        if re.match(r"^\d+(\.\d+)?$", iso) {
            return float(iso) * 1000.0;
        }
        s: str = iso.replace("Z", "").replace("+00:00", "");
        ms_part: float = 0.0;
        if "." in s {
            dot: int = s.rfind(".");
            ms_str: str = "0." + s[dot + 1:];
            ms_part = float(ms_str);
            s = s[:dot];
        }
        t: Any = time.strptime(s, "%Y-%m-%dT%H:%M:%S");
        base: float = float(time.mktime(t));
        return base * 1000.0 + ms_part * 1000.0;
    } except Exception {
        return 0.0;
    }
}

"""Extract the hostname from a URL string, or empty string on failure."""
def extract_hostname(url: str) -> str {
    try {
        parsed: Any = urlparse(url);
        host: str = str(parsed.hostname or "");
        return host;
    } except Exception {
        return "";
    }
}

"""Extract the path component from a URL string, or '/' on failure."""
def extract_pathname(url: str) -> str {
    try {
        parsed: Any = urlparse(url);
        path: str = str(parsed.path);
        return path if path else "/";
    } except Exception {
        return "/";
    }
}

"""Convert a human label into a stable snake_case input key."""
def to_snake_case(s: str) -> str {
    s = s.lower().strip();
    s = re.sub(r"[^a-z0-9]+", "_", s);
    s = s.strip("_");
    if not s {
        return "value";
    }
    return s;
}

"""Return a stable event id for normalized trace events."""
def new_event_id() -> str { return new_id("evt_"); }

"""Select the best available element identity key for input correlation."""
def element_identity_key(el: dict[str, Any]) -> str {
    return str(
        el.get("name", "") or
        el.get("label", "") or
        el.get("id", "") or
        el.get("placeholder", "")
    );
}

"""Map browser observation target fields into the richer compiler element shape."""
def target_to_element(target: Any) -> dict[str, Any] {
    if not isinstance(target, dict) {
        return {};
    }

    text_value: str = str(target.get("text", ""));
    role_value: str = str(target.get("role", ""));
    tag_value: str = str(target.get("tag", ""));

    return {
        "id": str(target.get("id", "")),
        "name": str(target.get("name", "")),
        "label": str(target.get("label", "")),
        "type": str(target.get("type", "")),
        "placeholder": str(target.get("placeholder", "")),
        "innerText": text_value,
        "role": role_value,
        "tag": tag_value,
        "cssSelector": "",
        "testId": "",
        "nearbyText": [],
        "sectionHeading": "",
        "formName": "",
        "className": str(target.get("class_name", ""))
    };
}

"""Normalize observation event names and payload fields into compiler-ready events."""
def normalize_observation_event(raw_event: Any) -> dict[str, Any] | None {
    if not isinstance(raw_event, dict) {
        return None;
    }

    raw_type: str = str(raw_event.get("type", ""));
    event_type: str = raw_type;
    if raw_type == "navigate" {
        event_type = "navigation";
    }

    target: Any = raw_event.get("target", {});
    value_text: str = str(raw_event.get("value", ""));

    normalized: dict[str, Any] = {
        "id": str(raw_event.get("id", "")) or new_event_id(),
        "type": event_type,
        "url": str(raw_event.get("url", "")),
        "timestamp": str(raw_event.get("timestamp", "") or raw_event.get("recorded_at", "")),
        "value": value_text,
        "masked": value_text == "__redacted__",
        "meta": raw_event.get("meta", {}) if isinstance(raw_event.get("meta", {}), dict) else {},
        "target": target if isinstance(target, dict) else {},
        "element": target_to_element(target)
    };

    return normalized;
}

"""Adapt persisted browser observation traces into the compiler session schema."""
def normalize_session(session: dict[str, Any]) -> dict[str, Any] {
    if not isinstance(session, dict) {
        return {};
    }

    normalized_events: list[Any] = [];
    candidate_events: Any = session.get("events", []);
    if isinstance(candidate_events, list) {
        for raw_event in candidate_events {
            normalized_event: dict[str, Any] | None = normalize_observation_event(raw_event);
            if normalized_event is not None {
                normalized_events.append(normalized_event);
            }
        }
    }

    goal_context: str = str(session.get("goalContext", "") or session.get("title", ""));
    start_url: str = str(session.get("startUrl", "") or session.get("source_url", ""));

    return {
        "id": str(session.get("id", "") or session.get("session_id", "")),
        "goalContext": goal_context,
        "startUrl": start_url,
        "status": str(session.get("status", "")),
        "events": normalized_events
    };
}

# ============================================================
# FILE I/O
# ============================================================

"""Ensure the workflow output directory exists."""
def ensure_workflow_dir() {
    os.makedirs(WORKFLOW_DIR, exist_ok=True);
}

"""Read a JSON object from disk; return empty dict on any failure."""
def read_json(path: str) -> dict[str, Any] {
    if not os.path.exists(path) {
        return {};
    }
    try {
        with open(path, "r") as f {
            parsed: Any = json.load(f);
            if isinstance(parsed, dict) {
                return parsed;
            }
        }
    } except Exception {
        return {};
    }
    return {};
}

"""Write a JSON object to disk with pretty-printing."""
def write_json(path: str, data: dict[str, Any]) {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    with open(path, "w") as f {
        json.dump(data, f, indent=2);
    }
}

"""Parse JSON payload from CLI args (position 2+)."""
def parse_payload() -> dict[str, Any] {
    if len(sys.argv) > 2 {
        raw: str = " ".join(sys.argv[2:]);
        try {
            parsed: Any = json.loads(raw);
            if isinstance(parsed, dict) {
                return parsed;
            }
        } except Exception {
            return {};
        }
    }
    return {};
}

"""Build absolute trace file path from session id."""
def trace_file(session_id: str) -> str {
    return TRACE_DIR + "/" + session_id + ".json";
}

"""Build absolute workflow file path from workflow id."""
def workflow_file(workflow_id: str) -> str {
    return WORKFLOW_DIR + "/" + workflow_id + ".json";
}

# ============================================================
# CLEANER PIPELINE
# ============================================================

"""Filter out events that carry no workflow-level meaning.

Removes:
  - focus/blur events whose element has no corresponding input/change event
  - duplicate navigation events to the same URL within 500ms

E: Empty input returns empty results; malformed timestamps yield delta=0.
"""
def remove_noise(events: list[Any]) -> dict[str, Any] {
    removed: list[Any] = [];
    kept: list[Any] = [];

    # Collect element IDs that received at least one input or change event
    inputted_ids: set[str] = set();
    for evt in events {
        if not isinstance(evt, dict) { continue; }
        etype: str = str(evt.get("type", ""));
        if etype == "input" or etype == "change" {
            el: Any = evt.get("element", {});
            if isinstance(el, dict) {
                eid: str = str(el.get("id", ""));
                if eid { inputted_ids.add(eid); }
            }
        }
    }

    for evt in events {
        if not isinstance(evt, dict) { continue; }
        etype = str(evt.get("type", ""));
        evt_id: str = str(evt.get("id", ""));

        # Drop orphan focus/blur (no accompanying input on same element)
        if etype == "focus" or etype == "blur" {
            el = evt.get("element", {});
            if isinstance(el, dict) {
                eid = str(el.get("id", ""));
                if eid and eid not in inputted_ids {
                    removed.append({
                        "id": evt_id,
                        "reason": etype + " with no input on element " + eid
                    });
                    continue;
                }
            }
        }

        # Drop duplicate navigation to the same URL within 500ms
        if etype == "navigation" {
            nav_url: str = str(evt.get("url", ""));
            prev_nav: Any = None;
            for k in reversed(kept) {
                if isinstance(k, dict) and str(k.get("type", "")) == "navigation" {
                    prev_nav = k;
                    break;
                }
            }
            if prev_nav is not None {
                prev_url: str = str(prev_nav.get("url", ""));
                if prev_url == nav_url {
                    prev_ts: float = parse_ts(str(prev_nav.get("timestamp", "0")));
                    curr_ts: float = parse_ts(str(evt.get("timestamp", "0")));
                    if (curr_ts - prev_ts) < 500.0 {
                        removed.append({
                            "id": evt_id,
                            "reason": "duplicate navigation within 500ms"
                        });
                        continue;
                    }
                }
            }
        }

        kept.append(evt);
    }

    return {"events": kept, "removed": removed};
}

"""True when two input events target the same DOM element.
Matches by element id, then name, then cssSelector.
"""
def same_input_element(a: dict[str, Any], b: dict[str, Any]) -> bool {
    el_a: Any = a.get("element", {});
    el_b: Any = b.get("element", {});
    if not isinstance(el_a, dict) or not isinstance(el_b, dict) { return False; }
    id_a: str = str(el_a.get("id", ""));
    id_b: str = str(el_b.get("id", ""));
    if id_a and id_a == id_b { return True; }
    name_a: str = str(el_a.get("name", ""));
    name_b: str = str(el_b.get("name", ""));
    if name_a and name_a == name_b { return True; }
    css_a: str = str(el_a.get("cssSelector", ""));
    css_b: str = str(el_b.get("cssSelector", ""));
    if css_a and css_a == css_b { return True; }
    return False;
}

"""Collapse consecutive input events on the same element into one event.
Keeps the last event in each run, which carries the final typed value.
E: Non-input events pass through unchanged; runs on different elements stay separate.
"""
def merge_typing_events(events: list[Any]) -> list[Any] {
    result: list[Any] = [];
    i: int = 0;
    while i < len(events) {
        evt: Any = events[i];
        if not isinstance(evt, dict) {
            i += 1;
            continue;
        }
        if str(evt.get("type", "")) != "input" {
            result.append(evt);
            i += 1;
            continue;
        }
        # Look ahead for consecutive input events on the same element
        group: list[Any] = [evt];
        while i + 1 < len(events) {
            next_evt: Any = events[i + 1];
            if (isinstance(next_evt, dict) and
                str(next_evt.get("type", "")) == "input" and
                same_input_element(evt, next_evt)) {
                i += 1;
                group.append(events[i]);
            } else {
                break;
            }
        }
        result.append(group[-1]);
        i += 1;
    }
    return result;
}

"""True when two click events target the same DOM element.
Matches by element id, then cssSelector.
"""
def same_click_target(a: dict[str, Any], b: dict[str, Any]) -> bool {
    el_a: Any = a.get("element", {});
    el_b: Any = b.get("element", {});
    if not isinstance(el_a, dict) or not isinstance(el_b, dict) { return False; }
    id_a: str = str(el_a.get("id", ""));
    id_b: str = str(el_b.get("id", ""));
    if id_a and id_a == id_b { return True; }
    css_a: str = str(el_a.get("cssSelector", ""));
    css_b: str = str(el_b.get("cssSelector", ""));
    if css_a and css_a == css_b { return True; }
    return False;
}

"""Remove accidental double-clicks: same target within 300ms, keep the first.
Searches backward through the running result for the last click on the same target;
intervening non-click events do not reset the dedup window.
"""
def collapse_duplicate_clicks(events: list[Any]) -> list[Any] {
    result: list[Any] = [];
    for evt in events {
        if not isinstance(evt, dict) or str(evt.get("type", "")) != "click" {
            result.append(evt);
            continue;
        }
        prev_click: Any = None;
        for k in reversed(result) {
            if isinstance(k, dict) and str(k.get("type", "")) == "click" {
                if same_click_target(k, evt) {
                    prev_click = k;
                    break;
                }
            }
        }
        if prev_click is not None {
            prev_ts: float = parse_ts(str(prev_click.get("timestamp", "0")));
            curr_ts: float = parse_ts(str(evt.get("timestamp", "0")));
            if (curr_ts - prev_ts) < 300.0 {
                continue;  # drop duplicate
            }
        }
        result.append(evt);
    }
    return result;
}

"""Apply the full three-pass cleaning pipeline to a session.
Order: removeNoise → mergeTypingEvents → collapseDuplicateClicks
"""
def clean_trace(session: dict[str, Any]) -> dict[str, Any] {
    raw_events: list[Any] = [];
    candidate: Any = session.get("events", []);
    if isinstance(candidate, list) { raw_events = candidate; }

    noise_result: dict[str, Any] = remove_noise(raw_events);
    events: list[Any] = noise_result["events"];
    events = merge_typing_events(events);
    events = collapse_duplicate_clicks(events);

    return {
        "sessionId": str(session.get("id", "")),
        "cleanedAt": timestamp_now(),
        "removedEventIds": noise_result["removed"],
        "events": events
    };
}

# ============================================================
# INFERENCE
# ============================================================

"""Determine the semantic WorkflowInput type from element metadata and value.
Returns empty string if the field should NOT become a runtime input.
Priority: element.type → label/name pattern → value pattern.
"""
def infer_input_type(el: dict[str, Any], value: str) -> str {
    el_type: str = str(el.get("type", "")).lower();
    label: str = str(el.get("label", "")).lower();
    name: str = str(el.get("name", "")).lower();

    if el_type == "password" { return "password"; }
    if el_type == "email" or re.search(r"email", label) or re.search(r"email", name) {
        return "email";
    }
    if el_type == "date" or re.search(r"date", label) or re.search(r"\d{4}-\d{2}-\d{2}", value) {
        return "date";
    }
    if el_type == "number" or re.search(r"amount|price|qty|quantity", label) {
        return "number";
    }
    if el_type == "file" { return "file"; }
    if re.match(r"^\d+(\.\d+)?$", value) { return "number"; }
    if re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", value) { return "email"; }
    if len(value) > 3 { return "string"; }
    return "";
}

"""Identify input/change events that should become parameterized workflow inputs.
A field becomes an input when its type inference returns a non-empty type.
Deduplicates by element key (name > label > id).
"""
def infer_inputs(events: list[Any]) -> list[Any] {
    inputs: list[Any] = [];
    seen: set[str] = set();

    for evt in events {
        if not isinstance(evt, dict) { continue; }
        etype: str = str(evt.get("type", ""));
        if etype != "input" and etype != "change" { continue; }
        el: Any = evt.get("element", {});
        if not isinstance(el, dict) { continue; }
        key: str = element_identity_key(el);
        if not key or key in seen { continue; }
        value: str = str(evt.get("value", ""));
        input_type: str = infer_input_type(el, value);
        if not input_type { continue; }
        seen.add(key);
        label_str: str = str(el.get("label", "") or key);
        is_secret: bool = str(el.get("type", "")) == "password";
        preview: str = value[:30] if len(value) > 30 else value;
        inputs.append({
            "id": new_input_id(),
            "name": to_snake_case(key),
            "label": label_str,
            "type": input_type,
            "required": True,
            "secret": is_secret,
            "sourceHint": {
                "elementIdentityKey": key,
                "inferredFromStepIds": [],
                "inferenceReason": "value \"" + preview + "\" appears dynamic"
            }
        });
    }
    return inputs;
}

"""Build a lookup from element identity to generated workflow input name."""
def input_name_lookup(inputs: list[Any]) -> dict[str, Any] {
    lookup: dict[str, Any] = {};

    for item in inputs {
        if not isinstance(item, dict) {
            continue;
        }
        source_hint: Any = item.get("sourceHint", {});
        if not isinstance(source_hint, dict) {
            continue;
        }
        identity_key: str = str(source_hint.get("elementIdentityKey", ""));
        if not identity_key {
            continue;
        }
        lookup[identity_key] = str(item.get("name", ""));
    }

    return lookup;
}

"""Inject postcondition assert steps after navigation and submit events.
After navigation: url_includes with confidence 0.6.
After submit: text_present 'success' with confidence 0.4 (conservative — user should refine).
"""
def infer_assertions(events: list[Any]) -> list[Any] {
    assertions: list[Any] = [];
    for evt in events {
        if not isinstance(evt, dict) { continue; }
        etype: str = str(evt.get("type", ""));
        if etype == "navigation" {
            pathname: str = extract_pathname(str(evt.get("url", "")));
            assertions.append({
                "id": new_step_id(),
                "type": "assert",
                "name": "Assert URL after navigation",
                "confidence": 0.6,
                "signal": {"kind": "url_includes", "value": pathname}
            });
        }
        if etype == "submit" {
            assertions.append({
                "id": new_step_id(),
                "type": "assert",
                "name": "Assert success after form submit",
                "confidence": 0.4,
                "signal": {"kind": "text_present", "text": "success"}
            });
        }
    }
    return assertions;
}

"""Infer conservative approval-required safety rules from high-stakes click targets.
Scans click steps for SAFETY_PATTERNS in the primary locator's text/label field.
All generated rules require_approval; users can downgrade in the workflow editor.
"""
def infer_safety_rules(steps: list[Any]) -> list[Any] {
    rules: list[Any] = [];
    for step in steps {
        if not isinstance(step, dict) or str(step.get("type", "")) != "click" {
            continue;
        }
        target: Any = step.get("target", {});
        if not isinstance(target, dict) { continue; }
        primary: Any = target.get("primary", {});
        if not isinstance(primary, dict) { continue; }
        kind: str = str(primary.get("kind", ""));
        text: str = "";
        if kind == "text" { text = str(primary.get("text", "")); }
        elif kind == "label" { text = str(primary.get("label", "")); }
        if not text { continue; }
        text_lower: str = text.lower();
        matched: bool = False;
        for pattern in SAFETY_PATTERNS {
            if pattern in text_lower {
                matched = True;
                break;
            }
        }
        if matched {
            rules.append({
                "id": new_rule_id(),
                "description": "Require approval before clicking \"" + text + "\"",
                "condition": {"kind": "target_text_contains", "value": text},
                "action": "require_approval"
            });
        }
    }
    return rules;
}

# ============================================================
# COMPILER CORE
# ============================================================

"""Build a TargetSpec dict from element metadata using semantic locator priority.
Click priority:  label > innerText > placeholder > name > testId > id > css
Fill priority:   label > placeholder > name > id > css  (no innerText)
Returns None if no usable locator is found.
"""
def build_target_spec(el: dict[str, Any], for_click: bool) -> dict[str, Any] | None {
    label: str = str(el.get("label", ""));
    inner_text: str = str(el.get("innerText", ""));
    placeholder: str = str(el.get("placeholder", ""));
    name: str = str(el.get("name", ""));
    test_id: str = str(el.get("testId", ""));
    el_id: str = str(el.get("id", ""));
    css_selector: str = str(el.get("cssSelector", ""));

    primary: dict[str, Any] | None = None;
    if label {
        primary = {"kind": "label", "label": label};
    } elif for_click and inner_text {
        primary = {"kind": "text", "text": inner_text[:60]};
    } elif placeholder {
        primary = {"kind": "placeholder", "placeholder": placeholder};
    } elif name {
        primary = {"kind": "name", "name": name};
    } elif test_id {
        primary = {"kind": "testid", "testId": test_id};
    } elif el_id {
        primary = {"kind": "css", "selector": "#" + el_id};
    } elif css_selector {
        primary = {"kind": "css", "selector": css_selector};
    }

    if primary is None { return None; }

    spec: dict[str, Any] = {"primary": primary};
    hints: dict[str, Any] = {};
    nearby: Any = el.get("nearbyText", None);
    if nearby and isinstance(nearby, list) { hints["nearbyText"] = nearby; }
    heading: str = str(el.get("sectionHeading", ""));
    if heading { hints["sectionHeading"] = heading; }
    form_name: str = str(el.get("formName", ""));
    if form_name { hints["formName"] = form_name; }
    if hints { spec["resolutionHints"] = hints; }
    return spec;
}

"""Map a single cleaned event to its workflow step dict.
navigation → goto | click → click | input/change → fill | annotation → None
Returns None when no valid locator exists or the event type produces no step.
"""
def event_to_step(event: dict[str, Any], input_names: dict[str, Any]) -> dict[str, Any] | None {
    if not isinstance(event, dict) { return None; }
    etype: str = str(event.get("type", ""));
    step_id: str = new_step_id();

    if etype == "navigation" {
        url: str = str(event.get("url", ""));
        if not url { return None; }
        return {"id": step_id, "type": "goto", "url": url};
    }

    if etype == "click" {
        el: Any = event.get("element", {});
        if not isinstance(el, dict) { return None; }
        target: dict[str, Any] | None = build_target_spec(el, True);
        if target is None { return None; }
        return {"id": step_id, "type": "click", "target": target};
    }

    if etype == "input" or etype == "change" {
        el = event.get("element", {});
        if not isinstance(el, dict) { return None; }
        target = build_target_spec(el, False);
        if target is None { return None; }
        masked: bool = bool(event.get("masked", False));
        identity_key: str = element_identity_key(el);
        input_name: str = str(input_names.get(identity_key, ""));

        step: dict[str, Any] = {
            "id": step_id,
            "type": "fill",
            "target": target
        };

        if input_name {
            step["value_source"] = "input." + input_name;
            if masked {
                step["secret"] = True;
            }
            return step;
        }

        literal_val: str = str(event.get("value", ""));
        if masked {
            step["value"] = "";
            step["secret"] = True;
            return step;
        }

        step["value"] = literal_val;
        return step;
    }

    # annotation and unrecognized types produce no step
    return None;
}

"""Collect unique domain hostnames from all event URLs."""
def collect_domains(events: list[Any]) -> list[str] {
    seen: set[str] = set();
    domains: list[str] = [];
    for evt in events {
        if not isinstance(evt, dict) { continue; }
        url: str = str(evt.get("url", ""));
        if url {
            host: str = extract_hostname(url);
            if host and host not in seen {
                seen.add(host);
                domains.append(host);
            }
        }
    }
    return domains;
}

"""Compile a cleaned trace into a partial Workflow IR using heuristics only.
Does not call any model. Assembles steps, asserts, inputs, safety, and metadata.
"""
def heuristic_compile(
    session: dict[str, Any],
    cleaned: dict[str, Any],
    options: dict[str, Any]
) -> dict[str, Any] {
    clean_events: list[Any] = [];
    candidate: Any = cleaned.get("events", []);
    if isinstance(candidate, list) { clean_events = candidate; }

    inferred_inputs: list[Any] = infer_inputs(clean_events);
    known_input_names: dict[str, Any] = input_name_lookup(inferred_inputs);

    step_origins: list[Any] = [];
    steps: list[Any] = [];
    for evt in clean_events {
        step: Any = event_to_step(evt, known_input_names);
        if step is not None {
            steps.append(step);
            step_origins.append({
                "stepId": str(step.get("id", "")),
                "sourceEventIds": [str(evt.get("id", ""))]
            });
        }
    }

    # Append inferred assertion steps after all action steps
    for a in infer_assertions(clean_events) {
        steps.append(a);
    }

    inferred_rules: list[Any] = infer_safety_rules(steps);
    domains: list[str] = collect_domains(clean_events);

    session_id: str = str(session.get("id", ""));
    goal: str = str(session.get("goalContext", ""));
    start_url: str = str(session.get("startUrl", ""));
    created_by: str = str(options.get("createdByUserId", ""));
    privacy: Any = options.get("privacy", {});
    if not isinstance(privacy, dict) { privacy = {}; }
    now: str = timestamp_now();

    safety: dict[str, Any] = {
        "allowedDomains": domains,
        "requireApprovalFor": ["final_submit", "delete", "purchase"],
        "customRules": inferred_rules
    };

    return {
        "version": "1.0",
        "id": new_workflow_id(),
        "name": goal if goal else "Untitled workflow",
        "metadata": {
            "createdAt": now,
            "updatedAt": now,
            "createdByUserId": created_by,
            "source": {
                "recordingSessionId": session_id,
                "origin": "browser-recording",
                "startUrl": start_url,
                "domains": domains
            }
        },
        "context": {
            "goal": goal,
            "userProvidedContext": [goal] if goal else []
        },
        "inputs": inferred_inputs,
        "steps": steps,
        "safety": safety,
        "privacy": privacy,
        "compileInfo": {
            "compilerVersion": COMPILER_VERSION,
            "compiledAt": now,
            "sourceTraceId": session_id,
            "stepOrigins": step_origins
        }
    };
}

"""Merge an optional model-enriched partial workflow into the heuristic result.
Model fills gaps only — it never overwrites heuristic-derived structure.
Enrichment: context.summary, context.successCriteria, step name, step confidence.
"""
def merge_model_result(
    partial: dict[str, Any],
    model_result: dict[str, Any]
) -> dict[str, Any] {
    if not isinstance(model_result, dict) { return partial; }

    ctx: dict[str, Any] = dict(partial.get("context", {}));
    model_ctx: Any = model_result.get("context", {});
    if isinstance(model_ctx, dict) {
        if not ctx.get("summary") and model_ctx.get("summary") {
            ctx["summary"] = str(model_ctx["summary"]);
        }
        if not ctx.get("successCriteria") and model_ctx.get("successCriteria") {
            ctx["successCriteria"] = model_ctx["successCriteria"];
        }
    }

    heuristic_steps: list[Any] = list(partial.get("steps", []));
    model_steps: Any = model_result.get("steps", []);
    merged_steps: list[Any] = [];

    for (i, step) in enumerate(heuristic_steps) {
        if not isinstance(step, dict) {
            merged_steps.append(step);
            continue;
        }
        if isinstance(model_steps, list) and i < len(model_steps) {
            model_step: Any = model_steps[i];
            if (isinstance(model_step, dict) and
                model_step.get("type") == step.get("type")) {
                merged: dict[str, Any] = dict(step);
                if not merged.get("name") and model_step.get("name") {
                    merged["name"] = str(model_step["name"]);
                }
                if (merged.get("confidence") is None and
                    model_step.get("confidence") is not None) {
                    merged["confidence"] = model_step["confidence"];
                }
                merged_steps.append(merged);
                continue;
            }
        }
        merged_steps.append(step);
    }

    return {**partial, "context": ctx, "steps": merged_steps};
}

# ============================================================
# VALIDATION
# ============================================================

"""Validate a compiled workflow dict against the required structural contract.
Returns {ok: True, workflow: ...} or {ok: False, errors: [...]}.
Checks: required top-level fields, version string, metadata sub-fields,
context.goal, inputs/steps are lists, compileInfo sub-fields.
"""
def validate_workflow(candidate: dict[str, Any]) -> dict[str, Any] {
    if not isinstance(candidate, dict) {
        return {"ok": False, "errors": ["workflow must be a dict"]};
    }
    errors: list[str] = [];

    required_top: list[str] = [
        "version", "id", "name", "metadata", "context",
        "inputs", "steps", "safety", "privacy", "compileInfo"
    ];
    for field in required_top {
        if field not in candidate {
            errors.append(field + ": required field is missing");
        }
    }

    if candidate.get("version") != "1.0" {
        errors.append("version: must be \"1.0\"");
    }

    metadata: Any = candidate.get("metadata", {});
    if isinstance(metadata, dict) {
        for mf in ["createdAt", "updatedAt", "createdByUserId", "source"] {
            if mf not in metadata {
                errors.append("metadata." + mf + ": required field is missing");
            }
        }
        source: Any = metadata.get("source", {});
        if isinstance(source, dict) {
            for sf in ["recordingSessionId", "origin", "domains"] {
                if sf not in source {
                    errors.append("metadata.source." + sf + ": required field is missing");
                }
            }
        }
    }

    context: Any = candidate.get("context", {});
    if isinstance(context, dict) and "goal" not in context {
        errors.append("context.goal: required field is missing");
    }

    if not isinstance(candidate.get("inputs"), list) {
        errors.append("inputs: must be a list");
    }
    if not isinstance(candidate.get("steps"), list) {
        errors.append("steps: must be a list");
    }

    compile_info: Any = candidate.get("compileInfo", {});
    if isinstance(compile_info, dict) {
        for cf in ["compilerVersion", "compiledAt", "sourceTraceId"] {
            if cf not in compile_info {
                errors.append("compileInfo." + cf + ": required field is missing");
            }
        }
    }

    if errors {
        return {"ok": False, "errors": errors};
    }
    return {"ok": True, "workflow": candidate};
}

# ============================================================
# SESSION ORCHESTRATOR
# ============================================================

"""Compile a recording session dict into a validated Workflow IR.
Pipeline: clean → heuristic compile → optional model hook → validate.
Model hook: set options['model_fn'] = fn(session, cleaned, options) -> dict
           and options['privacy']['llmUsage']['allowDuringCompile'] = True.
Returns {ok, workflow, warnings} or {ok, errors, warnings}.
"""
def compile_session(
    session: dict[str, Any],
    options: dict[str, Any]
) -> dict[str, Any] {
    warnings: list[str] = [];
    normalized_session: dict[str, Any] = normalize_session(session);
    if not normalized_session {
        return {
            "ok": False,
            "errors": ["session normalization failed"],
            "warnings": warnings
        };
    }

    # 1. Clean
    cleaned: dict[str, Any] = clean_trace(normalized_session);
    for r in cleaned.get("removedEventIds", []) {
        if isinstance(r, dict) {
            warnings.append(
                "Removed event " + str(r.get("id", "")) + ": " + str(r.get("reason", ""))
            );
        }
    }

    # 2. Heuristic compile
    partial: dict[str, Any] = heuristic_compile(normalized_session, cleaned, options);

    # 3. Optional model enrichment (caller injects via model_fn)
    model_fn: Any = options.get("model_fn", None);
    privacy: Any = options.get("privacy", {});
    llm_usage: Any = privacy.get("llmUsage", {}) if isinstance(privacy, dict) else {};
    allow_llm: bool = bool(llm_usage.get("allowDuringCompile", False)) if isinstance(llm_usage, dict) else False;

    if model_fn is not None and allow_llm {
        try {
            model_result: Any = model_fn(normalized_session, cleaned, options);
            if isinstance(model_result, dict) {
                partial = merge_model_result(partial, model_result);
            }
        } except Exception as e {
            warnings.append("Model enrichment failed: " + str(e));
        }
    }

    # 4. Validate
    validation: dict[str, Any] = validate_workflow(partial);
    if not bool(validation.get("ok", False)) {
        return {
            "ok": False,
            "errors": validation.get("errors", []),
            "warnings": warnings
        };
    }

    return {"ok": True, "workflow": validation["workflow"], "warnings": warnings};
}

# ============================================================
# CLI HANDLERS
# ============================================================

"""Build command: load a trace, compile it, and persist the resulting workflow.
Payload keys: session_id (required), created_by (default: 'cli'),
              privacy_mode (default: 'local').
"""
def build_workflow(payload: dict[str, Any]) -> dict[str, Any] {
    ensure_workflow_dir();

    session_id: str = str(payload.get("session_id", ""));
    if not session_id {
        return {"ok": False, "error": "session_id is required"};
    }

    trace_data: dict[str, Any] = read_json(trace_file(session_id));
    if not trace_data {
        return {"ok": False, "error": "trace not found", "session_id": session_id};
    }

    created_by: str = str(payload.get("created_by", "cli"));
    privacy_mode: str = str(payload.get("privacy_mode", "local"));

    options: dict[str, Any] = {
        "createdByUserId": created_by,
        "privacy": {
            "mode": privacy_mode,
            "llmUsage": {
                "allowDuringCompile": False,
                "allowDuringRepair": False,
                "allowRawDomInRepair": False
            }
        }
    };

    result: dict[str, Any] = compile_session(trace_data, options);
    if not bool(result.get("ok", False)) {
        return {
            "ok": False,
            "error": "compilation failed",
            "errors": result.get("errors", []),
            "warnings": result.get("warnings", [])
        };
    }

    workflow: dict[str, Any] = result["workflow"];
    workflow_id: str = str(workflow.get("id", "wf_unknown"));
    wf_path: str = workflow_file(workflow_id);
    write_json(wf_path, workflow);

    return {
        "ok": True,
        "workflow_id": workflow_id,
        "workflow_file": wf_path,
        "step_count": len(workflow.get("steps", [])),
        "input_count": len(workflow.get("inputs", [])),
        "warnings": result.get("warnings", [])
    };
}

"""Get command: retrieve a compiled workflow JSON by workflow_id."""
def get_workflow(payload: dict[str, Any]) -> dict[str, Any] {
    workflow_id: str = str(payload.get("workflow_id", ""));
    if not workflow_id {
        return {"ok": False, "error": "workflow_id is required"};
    }
    data: dict[str, Any] = read_json(workflow_file(workflow_id));
    if not data {
        return {"ok": False, "error": "workflow not found", "workflow_id": workflow_id};
    }
    return {"ok": True, "workflow": data};
}

"""Dry-run command: compile a session from an inline trace dict without persisting.
Payload key: session (dict with id, events, etc.)
"""
def dry_run_compile(payload: dict[str, Any]) -> dict[str, Any] {
    session: Any = payload.get("session", {});
    if not isinstance(session, dict) or not session.get("id") {
        return {"ok": False, "error": "payload.session with id is required"};
    }

    options: dict[str, Any] = {
        "createdByUserId": str(payload.get("created_by", "dry_run")),
        "privacy": {
            "mode": "local",
            "llmUsage": {
                "allowDuringCompile": False,
                "allowDuringRepair": False,
                "allowRawDomInRepair": False
            }
        }
    };

    result: dict[str, Any] = compile_session(session, options);
    return result;
}

"""Route a CLI command to the appropriate handler."""
def dispatch(command: str, payload: dict[str, Any]) -> dict[str, Any] {
    if command == "build" { return build_workflow(payload); }
    if command == "get" { return get_workflow(payload); }
    if command == "dry_run" { return dry_run_compile(payload); }
    return {
        "ok": False,
        "error": "unknown command",
        "valid_commands": ["build", "get", "dry_run"]
    };
}

# ============================================================
# ENTRY POINT
# ============================================================

with entry {
    command: str = "";
    if len(sys.argv) > 1 {
        command = str(sys.argv[1]);
    }
    payload: dict[str, Any] = parse_payload();
    result: dict[str, Any] = dispatch(command, payload);
    print(json.dumps(result));
}
