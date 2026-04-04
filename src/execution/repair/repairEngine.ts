import type { WorkflowStep, TargetLocator, Workflow } from "../../shared/types/workflow.js";
import type { ModelProvider } from "../../compilation/llm/compileTraceWithModel.js";
import { buildRepairPrompt } from "./buildRepairPrompt.js";
import { saveLearnedRepair } from "./saveLearnedRepair.js";

export type RepairContext = {
  step: WorkflowStep;
  failedLocator: TargetLocator;
  pageSnapshot: string;
  workflow: Workflow;
  model: ModelProvider;
  allowRawDom: boolean;
};

export type RepairResult =
  | { repaired: true; updatedLocator: TargetLocator }
  | { repaired: false; reason: string };

/**
 * Attempts to find a new locator for a failed step using the model.
 * Only called on step failure — never on the hot execution path.
 */
export async function repairStep(context: RepairContext): Promise<RepairResult> {
  const prompt = buildRepairPrompt(context);
  const raw = await context.model.complete(prompt);

  let locator: TargetLocator;
  try {
    locator = JSON.parse(raw.trim()) as TargetLocator;
  } catch {
    return { repaired: false, reason: "Model returned non-JSON repair output" };
  }

  return { repaired: true, updatedLocator: locator };
}
