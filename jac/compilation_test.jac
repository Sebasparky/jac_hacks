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
    validate_workflow,
    compile_segmented_recording,
    validate_compiled_artifact
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
# SEGMENTED COMPILATION TESTS — helpers
# ============================================================

glob DEFAULT_CONTINUATION: dict[str, Any] = {
    "strategy": [{"mode": "next_similar_item", "options": {}}]
};

glob DEFAULT_STOP_POLICY: dict[str, Any] = {
    "mode": "no_more_items",
    "options": {}
};

def mk_segmented_recording(
    ot_events: list[Any],
    rep_events: list[Any],
    continuation: dict[str, Any],
    stop_policy: dict[str, Any]
) -> dict[str, Any] {
    return {
        "recording_id": "rec_test_001",
        "task_name": "Test workflow",
        "state": "finished",
        "segments": {
            "one_time": {"events": ot_events, "annotations": []},
            "repeated": {"events": rep_events, "annotations": []}
        },
        "continuation": continuation,
        "stop_policy": stop_policy,
        "meta": {
            "start_url": "https://example.com",
            "domains": ["example.com"],
            "user_goal": "Test goal"
        }
    };
}

# ============================================================
# Test 1: only one_time events compile successfully
# ============================================================

def test_seg_only_one_time() {
    rec: dict[str, Any] = mk_segmented_recording(
        [mk_click("btn-login", 0), mk_nav("https://example.com/list", 100)],
        [],
        DEFAULT_CONTINUATION,
        DEFAULT_STOP_POLICY
    );
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg1: only one_time compiles ok", bool(result.get("ok", False)));
    art: Any = result.get("artifact", {});
    ot_steps: list[Any] = art.get("one_time", {}).get("steps", []);
    rep_steps: list[Any] = art.get("repeated", {}).get("steps", []);
    assert_true("seg1: one_time has steps", len(ot_steps) > 0);
    assert_eq("seg1: repeated is empty", len(rep_steps), 0);
}

# ============================================================
# Test 2: only repeated events compile successfully
# ============================================================

def test_seg_only_repeated() {
    rec: dict[str, Any] = mk_segmented_recording(
        [],
        [mk_click("btn-item", 0), mk_nav("https://example.com/item/1", 100)],
        DEFAULT_CONTINUATION,
        DEFAULT_STOP_POLICY
    );
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg2: only repeated compiles ok", bool(result.get("ok", False)));
    art: Any = result.get("artifact", {});
    ot_steps: list[Any] = art.get("one_time", {}).get("steps", []);
    rep_steps: list[Any] = art.get("repeated", {}).get("steps", []);
    assert_eq("seg2: one_time is empty", len(ot_steps), 0);
    assert_true("seg2: repeated has steps", len(rep_steps) > 0);
}

# ============================================================
# Test 3: both segments compile successfully
# ============================================================

def test_seg_both_segments() {
    rec: dict[str, Any] = mk_segmented_recording(
        [mk_nav("https://example.com", 0)],
        [mk_click("btn-next", 0), mk_nav("https://example.com/item", 100)],
        DEFAULT_CONTINUATION,
        DEFAULT_STOP_POLICY
    );
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg3: both segments compile ok", bool(result.get("ok", False)));
    art: Any = result.get("artifact", {});
    assert_true("seg3: one_time has steps", len(art.get("one_time", {}).get("steps", [])) > 0);
    assert_true("seg3: repeated has steps", len(art.get("repeated", {}).get("steps", [])) > 0);
}

# ============================================================
# Test 4: one_time events compile into one_time steps only
# ============================================================

def test_seg_one_time_steps_isolated() {
    rec: dict[str, Any] = mk_segmented_recording(
        [mk_click("btn-login", 0)],
        [mk_click("btn-item", 0)],
        DEFAULT_CONTINUATION,
        DEFAULT_STOP_POLICY
    );
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg4: compiles ok", bool(result.get("ok", False)));
    art: Any = result.get("artifact", {});
    ot_clicks: list[Any] = [s for s in art.get("one_time", {}).get("steps", []) if isinstance(s, dict) and s.get("type") == "click"];
    rep_clicks: list[Any] = [s for s in art.get("repeated", {}).get("steps", []) if isinstance(s, dict) and s.get("type") == "click"];
    assert_eq("seg4: one_time has exactly 1 click", len(ot_clicks), 1);
    assert_eq("seg4: repeated has exactly 1 click", len(rep_clicks), 1);
    ot_sel: str = str(ot_clicks[0].get("target", {}).get("primary", {}).get("selector", ""));
    rep_sel: str = str(rep_clicks[0].get("target", {}).get("primary", {}).get("selector", ""));
    assert_eq("seg4: one_time click is btn-login", ot_sel, "#btn-login");
    assert_eq("seg4: repeated click is btn-item", rep_sel, "#btn-item");
}

# ============================================================
# Test 5: repeated events compile into repeated steps only
# ============================================================

def test_seg_repeated_steps_isolated() {
    rec: dict[str, Any] = mk_segmented_recording(
        [],
        [mk_click("btn-process", 0)],
        DEFAULT_CONTINUATION,
        DEFAULT_STOP_POLICY
    );
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg5: compiles ok", bool(result.get("ok", False)));
    art: Any = result.get("artifact", {});
    ot_steps: list[Any] = art.get("one_time", {}).get("steps", []);
    rep_clicks: list[Any] = [s for s in art.get("repeated", {}).get("steps", []) if isinstance(s, dict) and s.get("type") == "click"];
    assert_eq("seg5: one_time has 0 steps", len(ot_steps), 0);
    assert_eq("seg5: repeated has 1 click step", len(rep_clicks), 1);
}

# ============================================================
# Test 6: repeated typing collapse works inside repeated
# ============================================================

def test_seg_repeated_typing_collapse() {
    rec: dict[str, Any] = mk_segmented_recording(
        [],
        [
            mk_input("search", "h", 0),
            mk_input("search", "he", 100),
            mk_input("search", "hello", 200)
        ],
        DEFAULT_CONTINUATION,
        DEFAULT_STOP_POLICY
    );
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg6: compiles ok", bool(result.get("ok", False)));
    rep_steps: list[Any] = result.get("artifact", {}).get("repeated", {}).get("steps", []);
    fills: list[Any] = [s for s in rep_steps if isinstance(s, dict) and s.get("type") == "fill"];
    assert_eq("seg6: 3 keystrokes collapse to 1 fill in repeated", len(fills), 1);
    assert_eq("seg6: fill value is final keystroke", str(fills[0].get("value", {}).get("value", "")), "hello");
}

# ============================================================
# Test 7: masked repeated input becomes secret in repeated output
# ============================================================

def test_seg_masked_repeated_input_is_secret() {
    pwd_evt: dict[str, Any] = {
        "id": "evt_pwd_rep", "timestamp": ts(0), "type": "input",
        "url": "https://example.com",
        "element": {"tag": "input", "name": "password", "type": "password"},
        "value": "s3cret", "masked": True
    };
    rec: dict[str, Any] = mk_segmented_recording([], [pwd_evt], DEFAULT_CONTINUATION, DEFAULT_STOP_POLICY);
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg7: compiles ok", bool(result.get("ok", False)));
    rep_steps: list[Any] = result.get("artifact", {}).get("repeated", {}).get("steps", []);
    fills: list[Any] = [s for s in rep_steps if isinstance(s, dict) and s.get("type") == "fill"];
    kind: str = str(fills[0].get("value", {}).get("kind", "")) if fills else "";
    assert_eq("seg7: masked repeated input becomes secret", kind, "secret");
    ot_steps: list[Any] = result.get("artifact", {}).get("one_time", {}).get("steps", []);
    assert_eq("seg7: one_time has no secret fill", len(ot_steps), 0);
}

# ============================================================
# Test 8: continuation strategy preserved in compiled output
# ============================================================

def test_seg_continuation_preserved() {
    cont: dict[str, Any] = {
        "strategy": [{"mode": "next_page", "options": {"max_pages": 5}}]
    };
    rec: dict[str, Any] = mk_segmented_recording([], [mk_click("btn-next", 0)], cont, DEFAULT_STOP_POLICY);
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg8: compiles ok", bool(result.get("ok", False)));
    stored_cont: Any = result.get("artifact", {}).get("continuation", {});
    strategy: list[Any] = stored_cont.get("strategy", []);
    assert_eq("seg8: strategy has 1 entry", len(strategy), 1);
    assert_eq("seg8: strategy mode preserved", str(strategy[0].get("mode", "")), "next_page");
    assert_eq("seg8: strategy max_pages preserved", strategy[0].get("options", {}).get("max_pages", 0), 5);
}

# ============================================================
# Test 9: stop policy preserved in compiled output
# ============================================================

def test_seg_stop_policy_preserved() {
    sp: dict[str, Any] = {"mode": "after_n_successes", "options": {"count": 10}};
    rec: dict[str, Any] = mk_segmented_recording([], [mk_click("btn-item", 0)], DEFAULT_CONTINUATION, sp);
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg9: compiles ok", bool(result.get("ok", False)));
    stored_sp: Any = result.get("artifact", {}).get("stop_policy", {});
    assert_eq("seg9: stop_policy mode preserved", str(stored_sp.get("mode", "")), "after_n_successes");
    assert_eq("seg9: stop_policy count preserved", stored_sp.get("options", {}).get("count", 0), 10);
}

# ============================================================
# Test 10: one_time and repeated segments do not leak events
# ============================================================

def test_seg_no_event_leakage() {
    ot_click: dict[str, Any] = mk_click("btn-login", 0);
    rep_click: dict[str, Any] = mk_click("btn-download", 0);
    rec: dict[str, Any] = mk_segmented_recording([ot_click], [rep_click], DEFAULT_CONTINUATION, DEFAULT_STOP_POLICY);
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg10: compiles ok", bool(result.get("ok", False)));
    art: Any = result.get("artifact", {});
    ot_css: list[str] = [
        str(s.get("target", {}).get("primary", {}).get("selector", ""))
        for s in art.get("one_time", {}).get("steps", [])
        if isinstance(s, dict) and s.get("type") == "click"
    ];
    rep_css: list[str] = [
        str(s.get("target", {}).get("primary", {}).get("selector", ""))
        for s in art.get("repeated", {}).get("steps", [])
        if isinstance(s, dict) and s.get("type") == "click"
    ];
    assert_true("seg10: login click in one_time", "#btn-login" in ot_css);
    assert_true("seg10: download click NOT in one_time", "#btn-download" not in ot_css);
    assert_true("seg10: download click in repeated", "#btn-download" in rep_css);
    assert_true("seg10: login click NOT in repeated", "#btn-login" not in rep_css);
}

# ============================================================
# Test 11: validate_compiled_artifact positive and negative
# ============================================================

def test_seg_validate_artifact() {
    rec: dict[str, Any] = mk_segmented_recording(
        [mk_click("btn-start", 0)],
        [mk_click("btn-item", 0)],
        DEFAULT_CONTINUATION,
        DEFAULT_STOP_POLICY
    );
    result: dict[str, Any] = compile_segmented_recording(rec, DEFAULT_OPTIONS);
    assert_true("seg11: compile ok", bool(result.get("ok", False)));
    v: dict[str, Any] = validate_compiled_artifact(result.get("artifact", {}));
    assert_true("seg11: valid artifact passes validation", bool(v.get("ok", False)));

    bad: dict[str, Any] = {"name": "incomplete"};
    v_bad: dict[str, Any] = validate_compiled_artifact(bad);
    assert_eq("seg11: bad artifact fails validation", bool(v_bad.get("ok", True)), False);
    assert_true("seg11: error list is non-empty", len(v_bad.get("errors", [])) > 0);
}

# ============================================================
# Test 12: flat-session dry_run path is still supported
# ============================================================

def test_old_dry_run_still_works() {
    session: dict[str, Any] = {
        "id": "sess_compat_1",
        "startUrl": "https://example.com",
        "goalContext": "Check backward compat",
        "events": [
            mk_nav("https://example.com/page", 0),
            mk_click("btn-ok", 200)
        ]
    };
    result: dict[str, Any] = compile_session(session, DEFAULT_OPTIONS);
    assert_true("compat: flat compile_session still works", bool(result.get("ok", False)));
    wf: Any = result.get("workflow", {});
    assert_true("compat: flat workflow has steps", len(wf.get("steps", [])) > 0);
    v: dict[str, Any] = validate_workflow(wf);
    assert_true("compat: flat workflow passes validate_workflow", bool(v.get("ok", False)));
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

    test_seg_only_one_time();
    test_seg_only_repeated();
    test_seg_both_segments();
    test_seg_one_time_steps_isolated();
    test_seg_repeated_steps_isolated();
    test_seg_repeated_typing_collapse();
    test_seg_masked_repeated_input_is_secret();
    test_seg_continuation_preserved();
    test_seg_stop_policy_preserved();
    test_seg_no_event_leakage();
    test_seg_validate_artifact();
    test_old_dry_run_still_works();

    print("");
    print("Results: " + str(COUNTS["passed"]) + " passed, " + str(COUNTS["failed"]) + " failed.");
    if COUNTS["failed"] > 0 {
        print("SOME TESTS FAILED");
    } else {
        print("ALL TESTS PASSED");
    }
}
