import type { GotoStep } from "../../shared/types/workflow.js";
import type { RunnerContext } from "../runner/workflowRunner.js";

export async function runGotoStep(step: GotoStep, context: RunnerContext): Promise<void> {
  await context.driver.goto(step.url);
}
