import type { Workflow, WorkflowStep, WorkflowInput } from "../../shared/types/workflow.js";
import type { WorkflowRuntimeState, LearnedRepair } from "../../shared/types/workflow.js";
import { stepDispatcher } from "./stepDispatcher.js";
import { evaluateSafety } from "../safety/safetyEvaluator.js";
import { checkDomain } from "../safety/domainGuard.js";
import { resolveValue } from "../state/runtimeMemory.js";
import { now } from "../../shared/utils/timestamps.js";

export type RunnerContext = {
  /** Resolved runtime inputs from the user. */
  inputs: Record<string, string | number | boolean>;
  /** Browser automation driver — injected, never imported directly. */
  driver: BrowserDriver;
  /** Called for steps that require approval. Returns true to proceed, false to abort. */
  requestApproval: (stepName: string, reason: string) => Promise<boolean>;
};

/** Minimal browser driver interface. Implementations use Playwright, Puppeteer, Electron, etc. */
export interface BrowserDriver {
  goto(url: string): Promise<void>;
  findElement(strategy: string, value: string, timeout?: number): Promise<ElementHandle | null>;
  currentUrl(): Promise<string>;
  pageText(): Promise<string>;
}

export interface ElementHandle {
  click(): Promise<void>;
  fill(value: string): Promise<void>;
  selectOption(value: string): Promise<void>;
  isVisible(): Promise<boolean>;
  getAttribute(name: string): Promise<string | null>;
  innerText(): Promise<string>;
}

export type RunResult = {
  status: "success" | "failed" | "partial" | "aborted";
  completedStepIds: string[];
  failedStepId?: string;
  error?: string;
  runtimeState: WorkflowRuntimeState;
};

/**
 * Executes a validated workflow deterministically.
 * LLM repair is only invoked on step failure, never on the hot execution path.
 */
export async function runWorkflow(
  workflow: Workflow,
  context: RunnerContext
): Promise<RunResult> {
  const memory: Record<string, string | number | boolean> = {};
  const completedStepIds: string[] = [];
  const startedAt = now();

  // Domain guard — abort immediately if we're on a disallowed domain
  const startUrl = workflow.metadata.source.startUrl;
  if (startUrl) {
    const domainCheck = checkDomain(startUrl, workflow.safety.allowedDomains);
    if (!domainCheck.allowed) {
      return makeResult("aborted", completedStepIds, undefined, `Domain not allowed: ${domainCheck.domain}`, now());
    }
  }

  for (const step of workflow.steps) {
    // Safety evaluation before each step
    const safetyDecision = evaluateSafety(step, workflow.safety, context.inputs);

    if (safetyDecision.action === "abort") {
      return makeResult("aborted", completedStepIds, step.id, safetyDecision.reason, now());
    }

    if (safetyDecision.action === "require_approval" || step.requiresApproval) {
      const reason = safetyDecision.action !== "proceed" ? safetyDecision.reason : "Step requires approval";
      const approved = await context.requestApproval(
        step.name ?? step.id,
        reason
      );
      if (!approved) {
        return makeResult("aborted", completedStepIds, step.id, "User rejected approval", now());
      }
    }

    try {
      await stepDispatcher(step, context, memory, workflow);
      completedStepIds.push(step.id);
    } catch (err) {
      const error = err instanceof Error ? err.message : String(err);
      return makeResult("failed", completedStepIds, step.id, error, now());
    }
  }

  return makeResult("success", completedStepIds, undefined, undefined, now());
}

function makeResult(
  status: RunResult["status"],
  completedStepIds: string[],
  failedStepId: string | undefined,
  error: string | undefined,
  finishedAt: string
): RunResult {
  const result: RunResult = {
    status,
    completedStepIds,
    runtimeState: {
      lastRunAt: finishedAt,
      lastRunStatus: status === "success" ? "success" : "failed",
    },
  };
  if (failedStepId !== undefined) result.failedStepId = failedStepId;
  if (error !== undefined) result.error = error;
  return result;
}
