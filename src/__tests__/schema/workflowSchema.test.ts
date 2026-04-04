import { describe, it, expect } from "vitest";
import { WorkflowSchema } from "../../shared/schema/workflowSchema.js";
import { expenseWorkflow } from "../../shared/examples/expenseWorkflow.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Deep-clone and apply a patch, returning the result. */
function patch(base: object, path: (string | number)[], value: unknown): object {
  const clone = JSON.parse(JSON.stringify(base));
  let node: Record<string, unknown> = clone as Record<string, unknown>;
  for (let i = 0; i < path.length - 1; i++) {
    node = node[path[i]!] as Record<string, unknown>;
  }
  const last = path[path.length - 1]!;
  if (value === undefined) {
    delete node[last as string];
  } else {
    node[last as string] = value;
  }
  return clone;
}

function withoutKey(base: object, path: (string | number)[]): object {
  return patch(base, path, undefined);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("WorkflowSchema — valid cases", () => {
  it("parses the reference expense workflow", () => {
    const result = WorkflowSchema.safeParse(expenseWorkflow);
    expect(result.success).toBe(true);
  });

  it("accepts a workflow with no optional fields", () => {
    const minimal = withoutKey(
      withoutKey(expenseWorkflow, ["description"]),
      ["runtimeState"]
    );
    expect(WorkflowSchema.safeParse(minimal).success).toBe(true);
  });

  it("accepts a workflow with runtimeState.learnedRepairs", () => {
    const withRepair = patch(expenseWorkflow, ["runtimeState"], {
      lastRunAt: "2026-04-04T13:00:00Z",
      lastRunStatus: "success",
      learnedRepairs: [
        {
          stepId: "step_2",
          previousLocator: { kind: "text", text: "New Report", role: "button" },
          updatedLocator: { kind: "css", selector: "button.new-report" },
          learnedAt: "2026-04-04T13:00:00Z",
          successCount: 3,
        },
      ],
    });
    expect(WorkflowSchema.safeParse(withRepair).success).toBe(true);
  });
});

describe("WorkflowSchema — invalid cases", () => {
  it("rejects a workflow with wrong version string", () => {
    const bad = patch(expenseWorkflow, ["version"], "2.0");
    const result = WorkflowSchema.safeParse(bad);
    expect(result.success).toBe(false);
  });

  it("rejects a workflow missing the name field", () => {
    const bad = withoutKey(expenseWorkflow, ["name"]);
    expect(WorkflowSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects a workflow with an empty steps array", () => {
    const bad = patch(expenseWorkflow, ["steps"], []);
    expect(WorkflowSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects a workflow with no allowedDomains in safety", () => {
    const bad = patch(expenseWorkflow, ["safety", "allowedDomains"], []);
    expect(WorkflowSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects an input whose name is not snake_case", () => {
    const bad = patch(expenseWorkflow, ["inputs", 0, "name"], "My Amount");
    expect(WorkflowSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects a step with an unrecognised type", () => {
    const bad = patch(expenseWorkflow, ["steps", 0, "type"], "hover");
    expect(WorkflowSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects a goto step with a non-URL value", () => {
    const bad = patch(expenseWorkflow, ["steps", 0, "url"], "not-a-url");
    expect(WorkflowSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects a metadata source with an empty domains array", () => {
    const bad = patch(expenseWorkflow, ["metadata", "source", "domains"], []);
    expect(WorkflowSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects a learnedRepair with successCount less than 1", () => {
    const bad = patch(expenseWorkflow, ["runtimeState"], {
      learnedRepairs: [
        {
          stepId: "step_2",
          previousLocator: { kind: "label", label: "Submit" },
          updatedLocator: { kind: "css", selector: "button" },
          learnedAt: "2026-04-04T13:00:00Z",
          successCount: 0,
        },
      ],
    });
    expect(WorkflowSchema.safeParse(bad).success).toBe(false);
  });
});
