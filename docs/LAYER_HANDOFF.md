# Layer Handoff Guide

## Current Status
- Electron shell is running with a modern browser chrome.
- Jac URL normalization is active (`jac/browser_core.jac`).
- Three Jac layer APIs are scaffolded, validated, and callable from UI:
  - Observation: `jac/layers/observation.jac`
  - Compilation: `jac/layers/compilation.jac`
  - Execution: `jac/layers/execution.jac`
- A "Layer Dev" panel in the app can:
  - Start trace
  - Stop trace
  - Compile trace into workflow
  - Plan workflow execution (dry-run)
- Dev A implementation now includes:
  - Multi-tab UI with create/switch/close events
  - In-page observation capture via `webview_preload.js`:
    - click, input, submit, page_ready events
    - network metadata for `fetch` and `XMLHttpRequest`
  - Observation hardening in Jac:
    - schema normalization/validation
    - sensitive input redaction
    - duplicate-event suppression
- Jac migration groundwork now includes:
  - `jac-client` enabled in the installed `jac` toolchain
  - Jac-authored client entrypoint in `main.jac`
  - Jac-authored UI components in `components/`
  - `jac build main.jac` producing a client bundle successfully
- Check status:
  - `jac check` passes for browser core + all three layer files.
  - `npm run layers:check` passes.
  - CLI smoke flow passes: `start -> append -> stop -> build -> plan`.

## Data Paths
- Observation traces: `jac/layer_data/traces/*.json`
- Compiled workflows: `jac/layer_data/workflows/*.json`

## Jac Layer Commands
Observation:
```bash
jac run jac/layers/observation.jac start '{"title":"Manual","url":"https://example.com"}'
jac run jac/layers/observation.jac append '{"session_id":"<id>","event":{"type":"navigate","url":"https://example.com"}}'
jac run jac/layers/observation.jac append '{"session_id":"<id>","event":{"type":"input","target":{"label":"query"},"value":"hello"}}'
jac run jac/layers/observation.jac stop '{"session_id":"<id>"}'
jac run jac/layers/observation.jac get '{"session_id":"<id>"}'
```

Compilation:
```bash
jac run jac/layers/compilation.jac build '{"session_id":"<id>"}'
jac run jac/layers/compilation.jac get '{"workflow_id":"wf_<id>"}'
```

Execution:
```bash
jac run jac/layers/execution.jac plan '{"workflow_id":"wf_<id>","inputs":{}}'
jac run jac/layers/execution.jac dry_run '{"workflow_id":"wf_<id>","inputs":{"query":"jac"}}'
```

## Response Contracts (Current)
- Observation `start`: `{ ok, session_id, trace_file }`
- Observation `append`: `{ ok, session_id, event_count }`
- Observation `stop`: `{ ok, session_id, event_count }`
- Observation `get`: `{ ok, trace }`
- Compilation `build`: `{ ok, workflow_id, workflow_file, input_count, step_count }`
- Compilation `get`: `{ ok, workflow }`
- Execution `plan|dry_run`: `{ ok, workflow_id, planned_at, step_count, unresolved_inputs, planned_steps }`

## Suggested Split For Two Developers
Dev A (Observation + Runtime capture):
- Extend capture fidelity:
  - add scroll/selection/context-menu signals where useful
  - add lightweight DOM neighborhood context for selectors
- Add batching/flush strategy for high-volume network events.
- Add replay-focused event quality scoring for compiler hints.

Dev B (Compilation + Execution):
- Improve compiler heuristics for robust selectors and dedupe.
- Add branching/guard/assert step generation.
- Extend execution planner into a real deterministic runner.

## Push Checklist
- Run:
  - `node --check main.js preload.js renderer.js`
  - `jac check jac/browser_core.jac jac/layers/observation.jac jac/layers/compilation.jac jac/layers/execution.jac`
  - `npm run layers:check`
  - `npm start`
- Confirm Layer Dev panel flow:
  - Start Trace -> navigate -> Stop Trace -> Compile -> Plan
- Commit + push to `main`.
