import type { FillStep, Workflow } from "../../shared/types/workflow.js";
import type { RunnerContext } from "../runner/workflowRunner.js";
import { resolveTarget } from "../resolver/targetResolver.js";
import { resolveValue } from "../state/runtimeMemory.js";

export async function runFillStep(
  step: FillStep,
  context: RunnerContext,
  memory: Record<string, string | number | boolean>,
  workflow: Workflow
): Promise<void> {
  if (!step.target) throw new Error(`Step ${step.id}: fill step has no target`);

  const result = await resolveTarget(step.target, context.driver, step.timeoutMs);
  if (!result.found) {
    throw new Error(`Step ${step.id}: could not resolve fill target`);
  }

  const value = resolveValue(step.value, context.inputs, memory);
  if (value === null) throw new Error(`Step ${step.id}: could not resolve value spec`);

  await result.element.fill(String(value));
}
