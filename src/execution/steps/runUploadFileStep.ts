import type { UploadFileStep, Workflow } from "../../shared/types/workflow.js";
import type { RunnerContext } from "../runner/workflowRunner.js";
import { resolveTarget } from "../resolver/targetResolver.js";
import { resolveValue } from "../state/runtimeMemory.js";

export async function runUploadFileStep(
  step: UploadFileStep,
  context: RunnerContext,
  memory: Record<string, string | number | boolean>,
  workflow: Workflow
): Promise<void> {
  if (!step.target) throw new Error(`Step ${step.id}: upload_file step has no target`);

  const result = await resolveTarget(step.target, context.driver, step.timeoutMs);
  if (!result.found) throw new Error(`Step ${step.id}: could not resolve file input target`);

  const filePath = resolveValue(step.file, context.inputs, memory);
  if (!filePath) throw new Error(`Step ${step.id}: could not resolve file path`);

  // Actual file upload is driver-specific — the driver handles <input type="file"> interactions
  await result.element.fill(String(filePath));
}
