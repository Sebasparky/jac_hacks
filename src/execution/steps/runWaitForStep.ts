import type { WaitForStep } from "../../shared/types/workflow.js";
import type { RunnerContext } from "../runner/workflowRunner.js";
import { resolveTarget } from "../resolver/targetResolver.js";

const POLL_INTERVAL_MS = 200;

export async function runWaitForStep(
  step: WaitForStep,
  context: RunnerContext
): Promise<void> {
  const timeout = step.timeoutMs ?? 10_000;
  const signal = step.signal;

  await poll(async () => {
    switch (signal.kind) {
      case "navigation": {
        const url = await context.driver.currentUrl();
        return signal.urlIncludes ? url.includes(signal.urlIncludes) : true;
      }
      case "text_present": {
        const text = await context.driver.pageText();
        return text.includes(signal.text);
      }
      case "element_present": {
        const result = await resolveTarget(signal.target, context.driver, 500);
        return result.found;
      }
      case "element_hidden": {
        const result = await resolveTarget(signal.target, context.driver, 500);
        if (!result.found) return true;
        return !(await result.element.isVisible());
      }
    }
  }, timeout, POLL_INTERVAL_MS);
}

async function poll(condition: () => Promise<boolean>, timeoutMs: number, intervalMs: number): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await condition()) return;
    await sleep(intervalMs);
  }
  throw new Error("wait_for timed out");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
