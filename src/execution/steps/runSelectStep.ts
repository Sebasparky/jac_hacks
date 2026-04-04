import type { SelectStep, Workflow } from "../../shared/types/workflow.js";
import type { RunnerContext } from "../runner/workflowRunner.js";
import { resolveTarget } from "../resolver/targetResolver.js";
import { resolveValue } from "../state/runtimeMemory.js";

export async function runSelectStep(
  step: SelectStep,
  context: RunnerContext,
  memory: Record<string, string | number | boolean>,
  workflow: Workflow
): Promise<void> {
  if (!step.target) throw new Error(`Step ${step.id}: select step has no target`);

  const result = await resolveTarget(step.target, context.driver, step.timeoutMs);
  if (!result.found) {
    throw new Error(`Step ${step.id}: could not resolve select target`);
  }

  const value = resolveValue(step.value, context.inputs, memory);
  if (value === null) throw new Error(`Step ${step.id}: could not resolve select value`);

  await result.element.selectOption(String(value));
}
