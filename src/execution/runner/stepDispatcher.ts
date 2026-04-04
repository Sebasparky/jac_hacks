import type { WorkflowStep, Workflow, RuntimeCondition } from "../../shared/types/workflow.js";
import type { RunnerContext } from "./workflowRunner.js";

import { runGotoStep } from "../steps/runGotoStep.js";
import { runClickStep } from "../steps/runClickStep.js";
import { runFillStep } from "../steps/runFillStep.js";
import { runSelectStep } from "../steps/runSelectStep.js";
import { runWaitForStep } from "../steps/runWaitForStep.js";
import { runAssertStep } from "../steps/runAssertStep.js";
import { runExtractStep } from "../steps/runExtractStep.js";
import { runUploadFileStep } from "../steps/runUploadFileStep.js";

/**
 * Routes a step to its executor.
 * Adding a new step type requires: (1) adding a file under steps/, (2) adding a case here.
 */
export async function stepDispatcher(
  step: WorkflowStep,
  context: RunnerContext,
  memory: Record<string, string | number | boolean>,
  workflow: Workflow
): Promise<void> {
  switch (step.type) {
    case "goto":
      return runGotoStep(step, context);
    case "click":
      return runClickStep(step, context, workflow);
    case "fill":
      return runFillStep(step, context, memory, workflow);
    case "select":
      return runSelectStep(step, context, memory, workflow);
    case "wait_for":
      return runWaitForStep(step, context);
    case "assert":
      return runAssertStep(step, context);
    case "extract":
      return runExtractStep(step, context, memory);
    case "upload_file":
      return runUploadFileStep(step, context, memory, workflow);
    case "branch": {
      // Evaluate condition and dispatch to the matching branch
      const conditionMet = evaluateBranchCondition(step.condition, context.inputs, memory);
      const branchSteps = conditionMet ? step.ifTrue : (step.ifFalse ?? []);
      for (const branchStep of branchSteps) {
        await stepDispatcher(branchStep, context, memory, workflow);
      }
      return;
    }
    default: {
      // TypeScript exhaustiveness check
      const _exhaustive: never = step;
      throw new Error(`Unknown step type: ${(_exhaustive as WorkflowStep).type}`);
    }
  }
}

function evaluateBranchCondition(
  condition: RuntimeCondition,
  inputs: Record<string, string | number | boolean>,
  memory: Record<string, string | number | boolean>
): boolean {
  switch (condition.kind) {
    case "input_equals":
      return inputs[condition.inputName] === condition.value;
    case "input_greater_than":
      return Number(inputs[condition.inputName]) > condition.value;
    case "memory_exists":
      return condition.key in memory;
    default: {
      const _: never = condition;
      return false;
    }
  }
}
