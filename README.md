# Jac Browser Automation (Working Title)
AI-assisted browser automation platform that can record real user workflows and replay them as reliable, editable task pipelines.

## Project Goals
### Primary Goal
- [ ] Build an AI-integrated browser workflow system that captures user interactions and turns them into repeatable automations.
- [ ] Support telemetry-driven replay (DOM interactions, navigation paths, optional network context) to reproduce tasks accurately.
- [ ] Let users compose multiple tasks into reusable workflows that reduce manual effort and token spend.

### Success Criteria
- [ ] Clean user interface with minimalist browser functionality.
- [ ] User can "Record" a task, which an LLM turns into a repeatable instruction set.
- [ ] Allow users to make entire workflows, which utilize tasks to increase speed and avoid unnecessary LLM usage.
- [ ] Allow users to use whatever cloud or local LLM model they wish.
- [ ] Replay success rate is high enough to trust in day-to-day work (target: >90% on test workflows).
- [ ] Users can inspect and edit generated task plans before execution.

### Non-Goals
- [ ] Building a full general-purpose web browser to compete with Chrome/Firefox.
- [ ] Circumventing website security controls, authentication policies, or anti-bot protections.
- [ ] Storing sensitive data without explicit user control and visibility.
- [ ] Fully autonomous execution without user review in v1.

## Problem Overview
### Current Pain
Many repetitive web tasks are still manual, fragile, and hard to automate. Traditional scripts break when UI changes, while LLM-only automations can be expensive and inconsistent. Teams need a practical middle path: record once, replay safely, and only invoke AI when needed.

### Users / Stakeholders
- Primary users: power users, operators, researchers, and technical teams doing repetitive browser tasks.
- Secondary users: product teams, QA, customer support, growth/ops teams.
- Decision-makers: project owner/maintainers and eventual internal or external adopters.

## Proposed Solution
### Summary
- Provide a recording mode that captures browser actions, context, and metadata.
- Convert recorded sessions into structured task definitions (LLM-assisted, user-editable).
- Execute tasks via deterministic actions first, with selective LLM fallbacks for ambiguity.
- Support workflow composition so users can chain tasks and reuse components.
- Keep provider/model selection open so users can bring their own cloud or local LLM.

### Why This Approach
This hybrid approach balances reliability and flexibility. Deterministic replay keeps costs and failure rates down, while LLM assistance handles fuzzy steps and adaptation. It is more maintainable than raw RPA scripts and more predictable than fully free-form agent execution.

## Market Context & Positioning
### Current Landscape (Adjacent Products)
- Agent-first browser products exist (for one-off task completion with frequent model reasoning).
- Browser automation frameworks exist that mix code + AI (developer-oriented).
- Computer-use style model tooling exists (screenshots + keyboard/mouse control).

### Our Wedge
- Do not compete on "general AI browsing."
- Compete on "demonstrate once, replay many times."
- Core differentiator: workflow compilation, not step-by-step agent reasoning.

### Positioning Statement
Instead of asking an AI agent to reason from scratch on every click, this project watches a user perform a workflow once, compiles it into a reusable procedure, and replays it quickly with selective repair when UI drift occurs.

## Scope
### In Scope (Now)
- [ ] Define core task/workflow data model.
- [ ] Implement recording pipeline for UI interactions.
- [ ] Implement execution engine for basic replay actions.
- [ ] LLM step generation/editing with provider-agnostic model config.
- [ ] Minimal UI for record, inspect, edit, and run.
- [ ] Hackathon-first implementation in Electron runtime (Jac-authored source only).

### Out of Scope (Later or Never)
- [ ] Team multi-tenant RBAC and enterprise admin features.
- [ ] Marketplace/ecosystem for shared public workflows.
- [ ] Fully autonomous long-horizon agents with no guardrails.
- [ ] Broad cross-device sync in initial releases.

## Milestones
### Milestone 1: Foundation
- [ ] Finalize architecture and task/workflow schema.
- [ ] Create first Jac modules and project structure.
- [ ] Build telemetry capture prototype (events + serialization).
- [ ] Establish provider configuration path (`MODEL`, API keys, local model option).
- [ ] Build Jac launcher + Electron runtime wiring with no hand-written JS source files.

### Milestone 2: Core Features
- [ ] Task recorder MVP (start/stop, action timeline, save task).
- [ ] Replay engine MVP (navigation, click, type, wait, assert).
- [ ] LLM-assisted instruction generation from recordings.
- [ ] Workflow composer MVP (chain tasks with variables/outputs).
- [ ] Add repair-on-failure flow: deterministic retry -> fallback locator -> optional LLM repair.

### Milestone 3: Hardening
- [ ] Testing, reliability, docs, polish
- [ ] Reliability benchmarking and replay diagnostics.
- [ ] Security/privacy controls for captured data.
- [ ] Error handling and recovery UX.
- [ ] Developer and user documentation for onboarding.

## Technical Direction
### Stack
- Primary language: Jac
- Supporting libraries/tools: Python libraries allowed when needed.
- AI backend tooling: `jac-coder`/`jac-mcp` capable environment (optional for IDE workflows).
- App runtime (hackathon): Electron shell with Jac-backed URL normalization (`jac/browser_core.jac`).
- Source policy: Jac-only authored code; no hand-written JavaScript files.
- Replay engine: Playwright-style deterministic browser actions and resilient locators.

### Architecture Notes
- Recorder component captures browser events and normalizes them into task steps.
- Planner component uses LLMs to convert/rewrite recordings into robust instructions.
- Runner component executes workflows with deterministic primitives and fallback logic.
- Storage layer persists tasks, workflows, run history, and versioned edits.
- Policy layer controls redaction, secrets handling, and sensitive-action approvals.

### Three-Layer Implementation Plan
1. Observation Layer
Capture user actions and context (click, input, navigation, nearby DOM semantics, optional network metadata). Store a trace with enough semantic detail to survive minor UI changes.
2. Compilation Layer
Transform raw traces into a workflow IR (JSON-like steps: `goto`, `wait_for`, `click`, `fill`, `assert`). Use heuristics first, LLM second. Parameterize variable user data and mask secrets.
3. Execution Layer
Replay deterministically at machine speed. Only invoke LLM when confidence drops, selectors fail, or a repair/decision step is needed.

### Workflow IR (Draft Shape)
```json
{
  "workflow_name": "submit timesheet",
  "inputs": ["hours", "project"],
  "steps": [
    {"type": "goto", "url": "https://app.example.com/timesheets"},
    {"type": "wait_for", "target": {"role": "button", "text": "New Entry"}},
    {"type": "click", "target": {"role": "button", "text": "New Entry"}},
    {"type": "fill", "target": {"label": "Hours"}, "value_source": "input.hours"},
    {"type": "fill", "target": {"label": "Project"}, "value_source": "input.project"},
    {"type": "click", "target": {"role": "button", "text": "Submit"}},
    {"type": "assert", "signal": {"text": "Timesheet submitted"}}
  ]
}
```

### Key Constraints
- Performance: replay latency should feel near-real-time; avoid unnecessary model calls.
- Security: strict handling of cookies/tokens/PII; explicit user controls and redaction.
- Cost: optimize for deterministic execution first; LLM calls should be targeted.
- Time: prioritize MVP path to validate real user value quickly.

## Developer Workflow
### Local Setup
```bash
# install deps
npm install

# launch browser runtime (Jac launcher -> Electron)
npm start

# launch Jac-authored client migration shell
npm run jac:web

# build Jac-authored client bundle
npm run jac:build

# verify jac and mcp availability
jac --version
jac mcp --inspect
```

### Layer Scaffolding
- Observation API: `jac/layers/observation.jac`
- Compilation API: `jac/layers/compilation.jac`
- Execution API: `jac/layers/execution.jac`
- Handoff guide: `docs/LAYER_HANDOFF.md`
- Jac client entrypoint: `main.jac`
- Jac client UI components: `components/*.cl.jac`
- Current readiness:
  - `npm run layers:check` passes
  - Layer flow works via CLI: `start -> append -> stop -> build -> plan`
  - Dev A baseline shipped:
    - multi-tab shell with new/switch/close behavior
    - in-page event capture and network metadata via webview preload
    - observation schema validation, dedupe, and sensitive-value redaction
  - Jac migration path shipped:
    - `jac-client` enabled in the local `jac` toolchain
    - `jac build main.jac` produces a client bundle from Jac-authored UI

### Coding Standards
- Keep code simple, skimmable, and easy to maintain.
- Use RME notes for non-trivial functions (Role, Method, Edge Cases).
- Prefer Jac for core implementation; use Python only where external libraries are needed.

## Risks & Mitigations
- Risk: Privacy/security issues from captured telemetry.
  - Mitigation: Data minimization, redaction defaults, explicit consent, encrypted storage.
- Risk: Replay brittleness when website UI changes.
  - Mitigation: Robust selectors, fallback heuristics, validation checks, repair prompts.
- Risk: LLM cost spikes.
  - Mitigation: Deterministic-first execution, caching, and model/provider controls.
- Risk: Ambiguous generated instructions.
  - Mitigation: Human-in-the-loop review before save/run in v1.
- Risk: Scope creep during 24-hour hackathon.
  - Mitigation: Limit MVP to one deterministic happy-path workflow + one repair scenario.

## Open Questions
- [ ] What telemetry is required vs optional for reliable replay?
- [ ] What is the safest default policy for cookies/session data?
- [ ] Which local model options should be first-class in v1?
- [ ] What level of auto-healing is acceptable before requiring user confirmation?
- [ ] Should v1 be extension-first, Electron-first, or both?

## 24-Hour Hackathon Plan
### MVP Definition
- Record one real workflow on one site.
- Compile to editable workflow IR.
- Replay at speed with minimal model calls.
- Demonstrate one UI-change failure that gets repaired.

### Demo Script
1. User records a workflow once.
2. System shows generated workflow steps.
3. User runs workflow with new input values.
4. Replay runs mostly deterministic and visibly faster than agent-per-step execution.
5. One step fails due to UI drift, system repairs and continues.

## Decision Log
- 2026-04-04: Jac-first implementation policy -> keep core logic consistent and maintainable.
- 2026-04-04: Python libraries allowed for integrations -> preserve flexibility without diluting core stack.
- 2026-04-04: Start with human-reviewed automation generation -> prioritize safety and trust in early versions.
- 2026-04-04: Product wedge set to "teach once, replay many" -> differentiate from general browser agents.
- 2026-04-04: Jac-only source policy enforced -> Electron is runtime only, no hand-written JS files.

## License
TBD (recommend choosing MIT or Apache-2.0 before first public release).
