import type { AssertStep } from "../../shared/types/workflow.js";
import type { RunnerContext } from "../runner/workflowRunner.js";
import { resolveTarget } from "../resolver/targetResolver.js";

export async function runAssertStep(step: AssertStep, context: RunnerContext): Promise<void> {
  const signal = step.signal;

  switch (signal.kind) {
    case "url_includes": {
      const url = await context.driver.currentUrl();
      if (!url.includes(signal.value)) {
        throw new Error(`Assert failed: URL "${url}" does not include "${signal.value}"`);
      }
      return;
    }
    case "text_present": {
      const text = await context.driver.pageText();
      if (!text.includes(signal.text)) {
        throw new Error(`Assert failed: text "${signal.text}" not found on page`);
      }
      return;
    }
    case "element_present": {
      const result = await resolveTarget(signal.target, context.driver, step.timeoutMs ?? 3000);
      if (!result.found) throw new Error(`Assert failed: element not present`);
      return;
    }
    case "element_not_present": {
      const result = await resolveTarget(signal.target, context.driver, 500);
      if (result.found) throw new Error(`Assert failed: element is present but should not be`);
      return;
    }
  }
}
