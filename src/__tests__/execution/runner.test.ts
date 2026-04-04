import { describe, it, expect, vi } from "vitest";
import { runWorkflow } from "../../execution/runner/workflowRunner.js";
import type { BrowserDriver, ElementHandle, RunnerContext } from "../../execution/runner/workflowRunner.js";
import type { Workflow } from "../../shared/types/workflow.js";

// ---------------------------------------------------------------------------
// Fake BrowserDriver
// ---------------------------------------------------------------------------

/**
 * Configurable fake driver.
 *
 * - `elements`: maps "strategy:value" to a fake ElementHandle (or null to simulate not found).
 * - All driver calls are recorded for assertion.
 */
class FakeDriver implements BrowserDriver {
  private _url = "https://app.example.com";
  readonly gotoCalls: string[] = [];
  readonly findCalls: Array<{ strategy: string; value: string }> = [];

  /** Preregister findable elements: key = `${strategy}:${value}` */
  constructor(
    private elements: Record<string, ElementHandle | null> = {}
  ) {}

  async goto(url: string): Promise<void> {
    this.gotoCalls.push(url);
    this._url = url;
  }

  async findElement(strategy: string, value: string): Promise<ElementHandle | null> {
    this.findCalls.push({ strategy, value });
    const key = `${strategy}:${value}`;
    if (key in this.elements) return this.elements[key] ?? null;
    // Return a default working element so tests that don't care pass through
    return makeFakeElement();
  }

  async currentUrl(): Promise<string> {
    return this._url;
  }

  async pageText(): Promise<string> {
    return "page text";
  }

  registerElement(strategy: string, value: string, el: ElementHandle | null): void {
    this.elements[`${strategy}:${value}`] = el;
  }
}

function makeFakeElement(overrides: Partial<ElementHandle> = {}): ElementHandle {
  return {
    click: vi.fn().mockResolvedValue(undefined),
    fill: vi.fn().mockResolvedValue(undefined),
    selectOption: vi.fn().mockResolvedValue(undefined),
    isVisible: vi.fn().mockResolvedValue(true),
    getAttribute: vi.fn().mockResolvedValue(null),
    innerText: vi.fn().mockResolvedValue(""),
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Workflow fixture helpers
// ---------------------------------------------------------------------------

function makeWorkflow(overrides: Partial<Workflow> = {}): Workflow {
  return {
    version: "1.0",
    id: "wf_test",
    name: "Test workflow",
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
    context: { goal: "test" },
    inputs: [],
    steps: [
      { id: "s1", type: "goto", url: "https://app.example.com/dashboard" },
    ],
    safety: {
      allowedDomains: ["app.example.com"],
    },
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

function makeContext(
  driverOverride?: BrowserDriver,
  approveFn?: (name: string, reason: string) => Promise<boolean>
): RunnerContext {
  return {
    inputs: {},
    driver: driverOverride ?? new FakeDriver(),
    requestApproval: approveFn ?? vi.fn().mockResolvedValue(true),
  };
}

// ---------------------------------------------------------------------------
// Step ordering
// ---------------------------------------------------------------------------

describe("workflowRunner — step execution order", () => {
  it("executes a single goto step and reports success", async () => {
    const driver = new FakeDriver();
    const workflow = makeWorkflow();
    const result = await runWorkflow(workflow, makeContext(driver));

    expect(result.status).toBe("success");
    expect(result.completedStepIds).toContain("s1");
    expect(driver.gotoCalls).toEqual(["https://app.example.com/dashboard"]);
  });

  it("executes multiple steps in order", async () => {
    const driver = new FakeDriver();
    const submitEl = makeFakeElement();
    driver.registerElement("text", "Submit", submitEl);

    const workflow = makeWorkflow({
      steps: [
        { id: "s1", type: "goto", url: "https://app.example.com/form" },
        {
          id: "s2",
          type: "click",
          target: { primary: { kind: "text", text: "Submit" } },
        },
      ],
    });

    const result = await runWorkflow(workflow, makeContext(driver));

    expect(result.status).toBe("success");
    expect(result.completedStepIds).toEqual(["s1", "s2"]);
    expect(driver.gotoCalls[0]).toBe("https://app.example.com/form");
    expect(submitEl.click).toHaveBeenCalledOnce();
  });

  it("stops at the failing step and reports failed status", async () => {
    const driver = new FakeDriver();
    // Make the click target unfindable
    driver.registerElement("text", "Missing Button", null);
    // All other locators also return null for this element
    const workflow = makeWorkflow({
      steps: [
        { id: "s1", type: "goto", url: "https://app.example.com" },
        {
          id: "s2",
          type: "click",
          target: {
            primary: { kind: "text", text: "Missing Button" },
            // No fallbacks so resolution definitely fails
          },
        },
        { id: "s3", type: "goto", url: "https://app.example.com/next" },
      ],
    });

    // Override findElement to always return null for this test
    driver.findElement = vi.fn().mockResolvedValue(null);

    const result = await runWorkflow(workflow, makeContext(driver));

    expect(result.status).toBe("failed");
    expect(result.failedStepId).toBe("s2");
    expect(result.completedStepIds).toContain("s1");
    expect(result.completedStepIds).not.toContain("s3");
  });
});

// ---------------------------------------------------------------------------
// Domain guard
// ---------------------------------------------------------------------------

describe("workflowRunner — domain guard", () => {
  it("aborts immediately when the startUrl domain is not in allowedDomains", async () => {
    const workflow = makeWorkflow({
      metadata: {
        createdAt: "2026-04-04T12:00:00Z",
        updatedAt: "2026-04-04T12:00:00Z",
        createdByUserId: "user_1",
        source: {
          recordingSessionId: "sess_1",
          origin: "browser-recording",
          startUrl: "https://forbidden.example.com/path",
          domains: ["app.example.com"],
        },
      },
      safety: { allowedDomains: ["app.example.com"] },
    });

    const driver = new FakeDriver();
    const result = await runWorkflow(workflow, makeContext(driver));

    expect(result.status).toBe("aborted");
    expect(result.error).toMatch(/domain not allowed/i);
    // Runner must not execute any steps
    expect(driver.gotoCalls).toHaveLength(0);
  });

  it("allows execution when the startUrl subdomain matches an allowed domain", async () => {
    const workflow = makeWorkflow({
      metadata: {
        createdAt: "2026-04-04T12:00:00Z",
        updatedAt: "2026-04-04T12:00:00Z",
        createdByUserId: "user_1",
        source: {
          recordingSessionId: "sess_1",
          origin: "browser-recording",
          startUrl: "https://sub.app.example.com/path",
          domains: ["app.example.com"],
        },
      },
      safety: { allowedDomains: ["app.example.com"] },
    });

    const result = await runWorkflow(workflow, makeContext());
    expect(result.status).toBe("success");
  });
});

// ---------------------------------------------------------------------------
// Approval gate
// ---------------------------------------------------------------------------

describe("workflowRunner — approval gate", () => {
  it("calls requestApproval for steps marked requiresApproval:true", async () => {
    const approvalFn = vi.fn().mockResolvedValue(true);
    const workflow = makeWorkflow({
      steps: [
        {
          id: "s1",
          type: "goto",
          url: "https://app.example.com",
          requiresApproval: true,
        },
      ],
    });

    const result = await runWorkflow(workflow, makeContext(undefined, approvalFn));

    expect(approvalFn).toHaveBeenCalledOnce();
    expect(result.status).toBe("success");
  });

  it("aborts when the user denies an approval-gated step", async () => {
    const denyFn = vi.fn().mockResolvedValue(false);
    const workflow = makeWorkflow({
      steps: [
        {
          id: "s1",
          type: "goto",
          url: "https://app.example.com",
          requiresApproval: true,
        },
      ],
    });

    const result = await runWorkflow(workflow, makeContext(undefined, denyFn));

    expect(result.status).toBe("aborted");
    expect(result.failedStepId).toBe("s1");
    expect(result.error).toMatch(/rejected/i);
  });

  it("does not call requestApproval for steps without requiresApproval", async () => {
    const approvalFn = vi.fn().mockResolvedValue(true);
    const workflow = makeWorkflow({
      steps: [{ id: "s1", type: "goto", url: "https://app.example.com" }],
    });

    await runWorkflow(workflow, makeContext(undefined, approvalFn));
    expect(approvalFn).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Fallback locator resolution
// ---------------------------------------------------------------------------

describe("workflowRunner — fallback resolution", () => {
  it("falls back to the second locator when the primary fails", async () => {
    const driver = new FakeDriver();
    const fallbackEl = makeFakeElement();

    // Primary "text:Submit" returns null, fallback "css:button.submit" succeeds
    driver.registerElement("text", "Submit", null);
    driver.registerElement("css", "button.submit", fallbackEl);

    const workflow = makeWorkflow({
      steps: [
        {
          id: "s1",
          type: "click",
          target: {
            primary: { kind: "text", text: "Submit" },
            fallbacks: [{ kind: "css", selector: "button.submit" }],
          },
        },
      ],
    });

    const result = await runWorkflow(workflow, makeContext(driver));

    expect(result.status).toBe("success");
    expect(fallbackEl.click).toHaveBeenCalledOnce();
  });

  it("reports failure when both primary and all fallbacks fail", async () => {
    const driver = new FakeDriver();
    driver.findElement = vi.fn().mockResolvedValue(null);

    const workflow = makeWorkflow({
      steps: [
        {
          id: "s1",
          type: "click",
          target: {
            primary: { kind: "text", text: "Submit" },
            fallbacks: [{ kind: "css", selector: "button.submit" }],
          },
        },
      ],
    });

    const result = await runWorkflow(workflow, makeContext(driver));

    expect(result.status).toBe("failed");
    expect(result.failedStepId).toBe("s1");
  });
});
