import { describe, it, expect } from "vitest";
import { compileSession } from "../../compilation/compiler/workflowCompiler.js";
import { validateWorkflow } from "../../compilation/validate/validateWorkflow.js";
import type { RecordingSession } from "../../shared/types/trace.js";
import type { WorkflowPrivacyPolicy } from "../../shared/types/privacy.js";
import type { GotoStep, FillStep } from "../../shared/types/workflow.js";

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const PRIVACY: WorkflowPrivacyPolicy = {
  mode: "local",
  llmUsage: {
    allowDuringCompile: false,
    allowDuringRepair: false,
    allowRawDomInRepair: false,
  },
};

const T0 = 1_000_000_000_000;

function ts(offset = 0): string {
  return new Date(T0 + offset).toISOString();
}

/** Minimal session: navigate then type an email address. */
const SIMPLE_SESSION: RecordingSession = {
  id: "sess_test_1",
  startedAt: ts(),
  status: "stopped",
  startUrl: "https://app.example.com/login",
  domains: ["app.example.com"],
  goalContext: "Log in to the app",
  events: [
    {
      id: "e1",
      sessionId: "sess_test_1",
      timestamp: ts(0),
      type: "navigation",
      url: "https://app.example.com/login",
      previousUrl: "https://app.example.com",
      trigger: "link_click",
    },
    {
      id: "e2",
      sessionId: "sess_test_1",
      timestamp: ts(1000),
      type: "input",
      url: "https://app.example.com/login",
      element: { tag: "input", name: "email", label: "Email", type: "email" },
      value: "user@test.com",
      masked: false,
    },
    {
      id: "e3",
      sessionId: "sess_test_1",
      timestamp: ts(2000),
      type: "input",
      url: "https://app.example.com/login",
      element: { tag: "input", name: "email", label: "Email", type: "email" },
      value: "user@test.com",
      masked: false,
    },
  ],
};

// ---------------------------------------------------------------------------
// Compiler pipeline
// ---------------------------------------------------------------------------

describe("compileSession — heuristic path (no model)", () => {
  it("returns ok:true for a valid minimal session", async () => {
    const result = await compileSession(SIMPLE_SESSION, {
      privacy: PRIVACY,
      createdByUserId: "user_test",
    });
    expect(result.ok).toBe(true);
  });

  it("compiled workflow passes schema validation independently", async () => {
    const result = await compileSession(SIMPLE_SESSION, {
      privacy: PRIVACY,
      createdByUserId: "user_test",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const validation = validateWorkflow(result.workflow);
    expect(validation.ok).toBe(true);
  });

  it("deduplicates consecutive input events — only one fill step for email", async () => {
    const result = await compileSession(SIMPLE_SESSION, {
      privacy: PRIVACY,
      createdByUserId: "user_test",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const fillSteps = result.workflow.steps.filter((s) => s.type === "fill");
    expect(fillSteps).toHaveLength(1);
  });

  it("produces a goto step from the navigation event", async () => {
    const result = await compileSession(SIMPLE_SESSION, {
      privacy: PRIVACY,
      createdByUserId: "user_test",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const gotoStep = result.workflow.steps.find((s) => s.type === "goto") as GotoStep | undefined;
    expect(gotoStep).toBeDefined();
    expect(gotoStep!.url).toBe("https://app.example.com/login");
  });

  it("infers the email field as a runtime input", async () => {
    const result = await compileSession(SIMPLE_SESSION, {
      privacy: PRIVACY,
      createdByUserId: "user_test",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const emailInput = result.workflow.inputs.find((i) => i.type === "email");
    expect(emailInput).toBeDefined();
  });

  it("uses the session goalContext as the workflow name", async () => {
    const result = await compileSession(SIMPLE_SESSION, {
      privacy: PRIVACY,
      createdByUserId: "user_test",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.workflow.name).toBe("Log in to the app");
  });

  it("records the createdByUserId in metadata", async () => {
    const result = await compileSession(SIMPLE_SESSION, {
      privacy: PRIVACY,
      createdByUserId: "user_42",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.workflow.metadata.createdByUserId).toBe("user_42");
  });

  it("masked input events produce a secret ValueSpec", async () => {
    const session: RecordingSession = {
      ...SIMPLE_SESSION,
      id: "sess_masked",
      events: [
        {
          id: "e_pwd",
          sessionId: "sess_masked",
          timestamp: ts(),
          type: "input",
          url: "https://app.example.com/login",
          element: { tag: "input", name: "password", type: "password" },
          value: "••••••",
          masked: true,
        },
      ],
    };
    const result = await compileSession(session, {
      privacy: PRIVACY,
      createdByUserId: "user_test",
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const fill = result.workflow.steps.find((s) => s.type === "fill") as FillStep | undefined;
    expect(fill?.value.kind).toBe("secret");
  });
});

describe("compileSession — validateWorkflow rejects partial workflows", () => {
  it("validateWorkflow rejects an object missing the version field", () => {
    const bad = { name: "broken", steps: [] };
    const result = validateWorkflow(bad);
    expect(result.ok).toBe(false);
  });
});
