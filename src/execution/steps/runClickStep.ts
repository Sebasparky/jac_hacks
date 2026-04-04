import type { ClickStep, Workflow } from "../../shared/types/workflow.js";
import type { RunnerContext } from "../runner/workflowRunner.js";
import { resolveTarget } from "../resolver/targetResolver.js";

export async function runClickStep(
  step: ClickStep,
  context: RunnerContext,
  workflow: Workflow
): Promise<void> {
  if (!step.target) throw new Error(`Step ${step.id}: click step has no target`);

  const learnedRepairs = workflow.runtimeState?.learnedRepairs?.filter((r) => r.stepId === step.id);
  const spec = learnedRepairs?.length
    ? { ...step.target, primary: learnedRepairs[learnedRepairs.length - 1]!.updatedLocator }
    : step.target;

  const result = await resolveTarget(spec, context.driver, step.timeoutMs);

  if (!result.found) {
    throw new Error(`Step ${step.id}: could not resolve click target after trying ${result.triedLocators.length} locators`);
  }

  await result.element.click();
}
