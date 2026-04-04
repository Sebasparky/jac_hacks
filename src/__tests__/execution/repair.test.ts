import { describe, it, expect } from "vitest";
import { saveLearnedRepair } from "../../execution/repair/saveLearnedRepair.js";
import { runWorkflow } from "../../execution/runner/workflowRunner.js";
import type { Workflow, TargetLocator } from "../../shared/types/workflow.js";
import type { BrowserDriver, ElementHandle, RunnerContext } from "../../execution/runner/workflowRunner.js";
import { vi } from "vitest";

// ---------------------------------------------------------------------------
// Minimal workflow fixture
// ---------------------------------------------------------------------------

function makeWorkflow(overrides: Partial<Workflow> = {}): Workflow {
  return {
    version: "1.0",
    id: "wf_repair_test",
    name: "Repair test workflow",
    metadata: {
      createdAt: "2026-04-04T12:00:00Z",
      updatedAt: "2026-04-04T12:00:00Z",
      createdByUserId: "user_1",
      source: {
        recordingSessionId: "sess_1",
        origin: "browser-recording",
        startUrl: "https://app.example.com",
        domains: ["app.example.com"],
      },
    },
    context: { goal: "test repair" },
    inputs: [],
    steps: [
      {
        id: "s1",
        type: "click",
        target: { primary: { kind: "text", text: "Submit" } },
      },
    ],
    safety: { allowedDomains: ["app.example.com"] },
    privacy: {
      mode: "local",
      llmUsage: {
        allowDuringCompile: false,
        allowDuringRepair: false,
        allowRawDomInRepair: false,
      },
    },
    compileInfo: {
      compilerVersion: "0.1.0",
      compiledAt: "2026-04-04T12:00:00Z",
      sourceTraceId: "sess_1",
    },
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// saveLearnedRepair — persistence logic
// ---------------------------------------------------------------------------

describe("saveLearnedRepair — new repair", () => {
  it("creates a new repair entry with successCount 1", () => {
    const workflow = makeWorkflow();
    const prev: TargetLocator = { kind: "text", text: "Submit" };
    const updated: TargetLocator = { kind: "css", selector: "button#submit-btn" };

    const updated_wf = saveLearnedRepair(workflow, "s1", prev, updated);

    const repairs = updated_wf.runtimeState?.learnedRepairs;
    expect(repairs).toHaveLength(1);
    expect(repairs![0]!.stepId).toBe("s1");
    expect(repairs![0]!.successCount).toBe(1);
    expect(repairs![0]!.updatedLocator).toEqual(updated);
    expect(repairs![0]!.previousLocator).toEqual(prev);
  });

  it("does not mutate the original workflow", () => {
    const workflow = makeWorkflow();
    saveLearnedRepair(workflow, "s1", { kind: "text", text: "Submit" }, { kind: "css", selector: "#x" });
    expect(workflow.runtimeState?.learnedRepairs).toBeUndefined();
  });
});

describe("saveLearnedRepair — incrementing successCount", () => {
  it("increments successCount when the same locator repair already exists", () => {
    const workflow = makeWorkflow();
    const prev: TargetLocator = { kind: "text", text: "Submit" };
    const updated: TargetLocator = { kind: "css", selector: "button#submit-btn" };

    const wf2 = saveLearnedRepair(workflow, "s1", prev, updated);
    const wf3 = saveLearnedRepair(wf2, "s1", prev, updated);

    const repairs = wf3.runtimeState?.learnedRepairs;
    expect(repairs).toHaveLength(1);
    expect(repairs![0]!.successCount).toBe(2);
  });

  it("creates a separate entry when the updatedLocator is different", () => {
    const workflow = makeWorkflow();
    const prev: TargetLocator = { kind: "text", text: "Submit" };
    const updated1: TargetLocator = { kind: "css", selector: "#btn-a" };
    const updated2: TargetLocator = { kind: "css", selector: "#btn-b" };

    const wf2 = saveLearnedRepair(workflow, "s1", prev, updated1);
    const wf3 = saveLearnedRepair(wf2, "s1", prev, updated2);

    expect(wf3.runtimeState?.learnedRepairs).toHaveLength(2);
  });

  it("stores repairs for different stepIds independently", () => {
    const workflow = makeWorkflow();
    const locator: TargetLocator = { kind: "css", selector: "#x" };
    const prev: TargetLocator = { kind: "text", text: "X" };

    const wf2 = saveLearnedRepair(workflow, "s1", prev, locator);
    const wf3 = saveLearnedRepair(wf2, "s2", prev, locator);

    const repairs = wf3.runtimeState?.learnedRepairs!;
    expect(repairs).toHaveLength(2);
    expect(repairs.map((r) => r.stepId).sort()).toEqual(["s1", "s2"]);
  });
});

// ---------------------------------------------------------------------------
// Runner — learned repairs are applied on subsequent runs
// ---------------------------------------------------------------------------

interface FakeEl extends ElementHandle {
  _id: string;
}

function makeFakeEl(id: string): FakeEl {
  return {
    _id: id,
    click: vi.fn().mockResolvedValue(undefined),
    fill: vi.fn().mockResolvedValue(undefined),
    selectOption: vi.fn().mockResolvedValue(undefined),
    isVisible: vi.fn().mockResolvedValue(true),
    getAttribute: vi.fn().mockResolvedValue(null),
    innerText: vi.fn().mockResolvedValue(""),
  };
}

class FakeDriver implements BrowserDriver {
  private elements: Record<string, ElementHandle | null> = {};
  gotoCalls: string[] = [];

  register(strategy: string, value: string, el: ElementHandle | null): void {
    this.elements[`${strategy}:${value}`] = el;
  }

  async goto(url: string): Promise<void> {
    this.gotoCalls.push(url);
  }
  async findElement(strategy: string, value: string): Promise<ElementHandle | null> {
    const key = `${strategy}:${value}`;
    if (key in this.elements) return this.elements[key] ?? null;
    return null;
  }
  async currentUrl(): Promise<string> { return "https://app.example.com"; }
  async pageText(): Promise<string> { return ""; }
}

function makeContext(driver: BrowserDriver): RunnerContext {
  return {
    inputs: {},
    driver,
    requestApproval: vi.fn().mockResolvedValue(true),
  };
}

describe("workflowRunner — applies learned repairs", () => {
  it("uses the learned locator instead of the original primary on a re-run", async () => {
    const originalEl = makeFakeEl("original");
    const repairedEl = makeFakeEl("repaired");

    const driver = new FakeDriver();
    // Original primary "text:Submit" is broken
    driver.register("text", "Submit", null);
    // Repaired locator "css:button#fixed" works
    driver.register("css", "button#fixed", repairedEl);

    const baseWorkflow = makeWorkflow();
    // Simulate a previously learned repair stored in runtimeState
    const workflowWithRepair = saveLearnedRepair(
      baseWorkflow,
      "s1",
      { kind: "text", text: "Submit" },
      { kind: "css", selector: "button#fixed" }
    );

    const result = await runWorkflow(workflowWithRepair, makeContext(driver));

    expect(result.status).toBe("success");
    expect(repairedEl.click).toHaveBeenCalledOnce();
    expect(originalEl.click).not.toHaveBeenCalled();
  });
});
