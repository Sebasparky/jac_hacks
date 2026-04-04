"""
Jac compilation layer — manual tests.
Mirrors the semantics verified by src/__tests__/compilation/cleaner.test.ts
and src/__tests__/compilation/compiler.test.ts.

Run with:  jac run jac/compilation_test.jac
All assertions print PASS on success; any failure prints FAIL and halts.
"""

import from jac.layers.compilation {
    remove_noise,
    merge_typing_events,
    collapse_duplicate_clicks,
    infer_inputs,
    infer_assertions,
    infer_safety_rules,
    event_to_step,
    compile_session,
    validate_workflow
}
import from typing { Any }

glob COUNTS: dict[str, int] = {"passed": 0, "failed": 0};

def assert_eq(label: str, got: Any, expected: Any) {
    if got == expected {
        COUNTS["passed"] = COUNTS["passed"] + 1;
        print("PASS  " + label);
    } else {
        COUNTS["failed"] = COUNTS["failed"] + 1;
        print("FAIL  " + label);
        print("      got:      " + str(got));
        print("      expected: " + str(expected));
    }
}

def assert_true(label: str, condition: bool) {
    assert_eq(label, condition, True);
}

glob T0: int = 1000000000000;

def ts(offset: int) -> str {
    sec: int = (T0 + offset) // 1000;
    ms: int = (T0 + offset) % 1000;
    # Approximate: use epoch + sec as a rough ISO string (good enough for deltas)
    import time;
    import from typing { Any }
    t: Any = time.gmtime(sec);
    base: str = time.strftime("%Y-%m-%dT%H:%M:%S", t);
    ms_str: str = str(ms).zfill(3);
    return base + "." + ms_str + "Z";
}

def mk_input(name: str, value: str, offset: int, el_overrides: dict[str, Any] = {}) -> dict[str, Any] {
    el: dict[str, Any] = {"tag": "input", "name": name};
    for (k, v) in el_overrides.items() {
        el[k] = v;
    }
    return {
        "id": "evt_" + name + "_" + str(offset),
        "sessionId": "sess_1",
        "url": "https://example.com",
        "timestamp": ts(offset),
        "type": "input",
        "element": el,
        "value": value,
        "masked": False
    };
}

def mk_click(element_id: str, offset: int) -> dict[str, Any] {
    return {
        "id": "evt_click_" + element_id + "_" + str(offset),
        "sessionId": "sess_1",
        "url": "https://example.com",
        "timestamp": ts(offset),
        "type": "click",
        "element": {"tag": "button", "id": element_id}
    };
}

def mk_nav(url: str, offset: int) -> dict[str, Any] {
    return {
        "id": "evt_nav_" + str(offset),
        "sessionId": "sess_1",
        "url": url,
        "timestamp": ts(offset),
        "type": "navigation",
        "previousUrl": "https://example.com",
        "trigger": "link_click"
    };
}

def mk_focus(element_id: str, offset: int) -> dict[str, Any] {
    return {
        "id": "evt_focus_" + element_id + "_" + str(offset),
        "sessionId": "sess_1",
        "url": "https://example.com",
        "timestamp": ts(offset),
        "type": "focus",
        "element": {"tag": "input", "id": element_id}
    };
}

def mk_blur(element_id: str, offset: int) -> dict[str, Any] {
    return {
        "id": "evt_blur_" + element_id + "_" + str(offset),
        "sessionId": "sess_1",
        "url": "https://example.com",
        "timestamp": ts(offset),
        "type": "blur",
        "element": {"tag": "input", "id": element_id}
    };
}

glob DEFAULT_PRIVACY: dict[str, Any] = {
    "mode": "local",
    "llmUsage": {
        "allowDuringCompile": False,
        "allowDuringRepair": False,
        "allowRawDomInRepair": False
    }
};

glob DEFAULT_OPTIONS: dict[str, Any] = {
    "createdByUserId": "user_test",
    "privacy": DEFAULT_PRIVACY
};

# ============================================================
# merge_typing_events
# ============================================================

def test_merge_typing_events() {
    # Collapses consecutive same-element inputs to last value
    evts: list[Any] = [
        mk_input("email", "a", 0),
        mk_input("email", "ab", 100),
        mk_input("email", "abc", 200)
    ];
    r: list[Any] = merge_typing_events(evts);
    assert_eq("merge: 3 keystrokes collapse to 1", len(r), 1);
    assert_eq("merge: final value preserved", str(r[0].get("value", "")), "abc");

    # Different elements produce separate entries
    evts2: list[Any] = [
        mk_input("first_name", "Jo", 0),
        mk_input("last_name", "Sm", 100),
        mk_input("last_name", "Smith", 200)
    ];
    r2: list[Any] = merge_typing_events(evts2);
    assert_eq("merge: different elements kept separate", len(r2), 2);
    assert_eq("merge: second field final value", str(r2[1].get("value", "")), "Smith");

    # Non-input events between two same-field inputs break the run
    evts3: list[Any] = [
        mk_input("email", "a", 0),
        mk_click("btn", 150),
        mk_input("email", "b", 300)
    ];
    r3: list[Any] = merge_typing_events(evts3);
    assert_eq("merge: run broken by intervening click", len(r3), 3);

    # Empty array handled
    assert_eq("merge: empty array", len(merge_typing_events([])), 0);
}

# ============================================================
# collapse_duplicate_clicks
# ============================================================

def test_collapse_duplicate_clicks() {
    # Same element within 300ms — second dropped
    evts: list[Any] = [mk_click("btn-submit", 0), mk_click("btn-submit", 200)];
    r: list[Any] = collapse_duplicate_clicks(evts);
    assert_eq("collapse: second click within 300ms dropped", len(r), 1);

    # Same element >300ms apart — both kept
    evts2: list[Any] = [mk_click("btn-submit", 0), mk_click("btn-submit", 400)];
    assert_eq("collapse: clicks >300ms apart both kept", len(collapse_duplicate_clicks(evts2)), 2);

    # Different elements — both kept even if close
    evts3: list[Any] = [mk_click("btn-a", 0), mk_click("btn-b", 50)];
    assert_eq("collapse: different elements both kept", len(collapse_duplicate_clicks(evts3)), 2);

    # Same element within 300ms with intervening nav — second still dropped
    evts4: list[Any] = [mk_click("btn-submit", 0), mk_nav("https://x.com/2", 100), mk_click("btn-submit", 200)];
    r4: list[Any] = collapse_duplicate_clicks(evts4);
    assert_eq("collapse: intervening nav doesn't reset window, second click dropped", len(r4), 2);
    click_count: int = len([e for e in r4 if isinstance(e, dict) and e.get("type") == "click"]);
    assert_eq("collapse: exactly 1 click remains", click_count, 1);
}

# ============================================================
# remove_noise
# ============================================================

def test_remove_noise() {
    # Orphan focus removed
    focus: dict[str, Any] = mk_focus("orphan", 0);
    r: dict[str, Any] = remove_noise([focus]);
    assert_eq("noise: orphan focus removed", len(r["events"]), 0);
    assert_eq("noise: orphan focus logged", len(r["removed"]), 1);

    # Focus on element that also has input — kept
    inp: dict[str, Any] = mk_input("username", "alice", 100, {"id": "username-field"});
    focus2: dict[str, Any] = mk_focus("username-field", 0);
    r2: dict[str, Any] = remove_noise([focus2, inp]);
    focus_ids: list[str] = [str(e.get("id", "")) for e in r2["events"]];
    assert_true("noise: focus with input kept", focus2["id"] in focus_ids);

    # Orphan blur removed
    blur: dict[str, Any] = mk_blur("orphan", 0);
    r3: dict[str, Any] = remove_noise([blur]);
    assert_eq("noise: orphan blur removed", len(r3["events"]), 0);

    # Duplicate nav within 500ms — second dropped
    nav1: dict[str, Any] = mk_nav("https://example.com/page", 0);
    nav2: dict[str, Any] = mk_nav("https://example.com/page", 300);
    r4: dict[str, Any] = remove_noise([nav1, nav2]);
    assert_eq("noise: dup nav within 500ms dropped", len(r4["events"]), 1);
    assert_eq("noise: second nav logged as removed", str(r4["removed"][0].get("id", "")), nav2["id"]);

    # Same nav >500ms apart — both kept
    nav3: dict[str, Any] = mk_nav("https://example.com/page", 0);
    nav4: dict[str, Any] = mk_nav("https://example.com/page", 600);
    assert_eq("noise: same nav >500ms apart both kept", len(remove_noise([nav3, nav4])["events"]), 2);

    # Different nav URLs close together — both kept
    nav5: dict[str, Any] = mk_nav("https://example.com/a", 0);
    nav6: dict[str, Any] = mk_nav("https://example.com/b", 100);
    assert_eq("noise: different URLs always kept", len(remove_noise([nav5, nav6])["events"]), 2);
}

# ============================================================
# compile_session — heuristic path
# ============================================================

def test_compile_session() {
    session: dict[str, Any] = {
        "id": "sess_test_1",
        "startedAt": ts(0),
        "status": "stopped",
        "startUrl": "https://app.example.com/login",
        "domains": ["app.example.com"],
        "goalContext": "Log in to the app",
        "events": [
            {
                "id": "e1", "sessionId": "sess_test_1", "timestamp": ts(0),
                "type": "navigation", "url": "https://app.example.com/login",
                "previousUrl": "https://app.example.com", "trigger": "link_click"
            },
            {
                "id": "e2", "sessionId": "sess_test_1", "timestamp": ts(1000),
                "type": "input", "url": "https://app.example.com/login",
                "element": {"tag": "input", "name": "email", "label": "Email", "type": "email"},
                "value": "user@test.com", "masked": False
            },
            {
                "id": "e3", "sessionId": "sess_test_1", "timestamp": ts(2000),
                "type": "input", "url": "https://app.example.com/login",
                "element": {"tag": "input", "name": "email", "label": "Email", "type": "email"},
                "value": "user@test.com", "masked": False
            }
        ]
    };

    result: dict[str, Any] = compile_session(session, DEFAULT_OPTIONS);
    assert_true("compile: ok is True for valid session", bool(result.get("ok", False)));

    wf: Any = result.get("workflow", {});
    steps: list[Any] = wf.get("steps", []);
    fill_steps: list[Any] = [s for s in steps if isinstance(s, dict) and s.get("type") == "fill"];
    goto_steps: list[Any] = [s for s in steps if isinstance(s, dict) and s.get("type") == "goto"];

    assert_eq("compile: two consecutive email inputs collapse to one fill", len(fill_steps), 1);
    assert_eq("compile: navigation produces goto step", len(goto_steps), 1);
    assert_eq("compile: goto url matches navigation event", str(goto_steps[0].get("url", "")), "https://app.example.com/login");
    assert_eq("compile: goalContext becomes workflow name", str(wf.get("name", "")), "Log in to the app");
    assert_eq("compile: createdByUserId tracked", str(wf.get("metadata", {}).get("createdByUserId", "")), "user_test");

    email_inputs: list[Any] = [i for i in wf.get("inputs", []) if isinstance(i, dict) and i.get("type") == "email"];
    assert_true("compile: email field inferred as runtime input", len(email_inputs) > 0);

    # Validation passes on the compiled output
    v: dict[str, Any] = validate_workflow(wf);
    assert_true("compile: compiled workflow passes validate_workflow", bool(v.get("ok", False)));
}

def test_masked_input_becomes_secret() {
    session: dict[str, Any] = {
        "id": "sess_masked",
        "startUrl": "https://app.example.com/login",
        "goalContext": "",
        "events": [
            {
                "id": "e_pwd", "sessionId": "sess_masked", "timestamp": ts(0),
                "type": "input", "url": "https://app.example.com/login",
                "element": {"tag": "input", "name": "password", "type": "password"},
                "value": "secret", "masked": True
            }
        ]
    };
    result: dict[str, Any] = compile_session(session, DEFAULT_OPTIONS);
    assert_true("masked: ok is True", bool(result.get("ok", False)));
    steps: list[Any] = result.get("workflow", {}).get("steps", []);
    fill: list[Any] = [s for s in steps if isinstance(s, dict) and s.get("type") == "fill"];
    kind: str = str(fill[0].get("value", {}).get("kind", "")) if fill else "";
    assert_eq("masked: fill value kind is secret", kind, "secret");
}

def test_validate_rejects_partial() {
    bad: dict[str, Any] = {"name": "broken", "steps": []};
    r: dict[str, Any] = validate_workflow(bad);
    assert_eq("validate: rejects missing version field", bool(r.get("ok", True)), False);
    assert_true("validate: returns error list", len(r.get("errors", [])) > 0);
}

def test_infer_safety_rules() {
    steps: list[Any] = [
        {"type": "click", "target": {"primary": {"kind": "text", "text": "Submit Order"}}},
        {"type": "click", "target": {"primary": {"kind": "label", "label": "Delete Account"}}},
        {"type": "click", "target": {"primary": {"kind": "label", "label": "Continue"}}},
    ];
    rules: list[Any] = infer_safety_rules(steps);
    assert_eq("safety: 2 high-stakes clicks get rules", len(rules), 2);
    actions: list[str] = [str(r.get("action", "")) for r in rules];
    assert_true("safety: all rules require approval", all(a == "require_approval" for a in actions));
}

# ============================================================
# Run all tests
# ============================================================

with entry {
    test_merge_typing_events();
    test_collapse_duplicate_clicks();
    test_remove_noise();
    test_compile_session();
    test_masked_input_becomes_secret();
    test_validate_rejects_partial();
    test_infer_safety_rules();

    print("");
    print("Results: " + str(COUNTS["passed"]) + " passed, " + str(COUNTS["failed"]) + " failed.");
    if COUNTS["failed"] > 0 {
        print("SOME TESTS FAILED");
    } else {
        print("ALL TESTS PASSED");
    }
}
