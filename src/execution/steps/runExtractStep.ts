import type { ExtractStep } from "../../shared/types/workflow.js";
import type { RunnerContext } from "../runner/workflowRunner.js";
import { resolveTarget } from "../resolver/targetResolver.js";

export async function runExtractStep(
  step: ExtractStep,
  context: RunnerContext,
  memory: Record<string, string | number | boolean>
): Promise<void> {
  if (!step.target) throw new Error(`Step ${step.id}: extract step has no target`);

  const result = await resolveTarget(step.target, context.driver, step.timeoutMs);
  if (!result.found) throw new Error(`Step ${step.id}: could not resolve extract target`);

  let value: string | null = null;

  switch (step.extraction.kind) {
    case "text":
      value = await result.element.innerText();
      break;
    case "value":
      value = await result.element.getAttribute("value");
      break;
    case "attribute":
      if (!step.extraction.attributeName) throw new Error(`Step ${step.id}: attributeName required`);
      value = await result.element.getAttribute(step.extraction.attributeName);
      break;
  }

  if (value === null) throw new Error(`Step ${step.id}: extraction returned null`);
  memory[step.outputKey] = value;
}
