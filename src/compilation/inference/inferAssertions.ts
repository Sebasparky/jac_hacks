import type { RawEvent } from "../../shared/types/trace.js";
import type { AssertStep } from "../../shared/types/workflow.js";
import { newStepId } from "../../shared/utils/ids.js";

/**
 * Inserts assert steps after navigation events and form submits.
 * These give the runner observable success signals beyond "no exception thrown."
 */
export function inferAssertions(events: RawEvent[]): AssertStep[] {
  const assertions: AssertStep[] = [];

  for (const event of events) {
    if (event.type === "navigation") {
      assertions.push({
        id: newStepId(),
        type: "assert",
        name: "Assert URL after navigation",
        confidence: 0.6,
        signal: { kind: "url_includes", value: new URL(event.url).pathname },
      });
    }

    if (event.type === "submit") {
      // Infer a generic success-text check; compiler or user should refine this
      assertions.push({
        id: newStepId(),
        type: "assert",
        name: "Assert success after form submit",
        confidence: 0.4,
        signal: { kind: "text_present", text: "success" },
      });
    }
  }

  return assertions;
}
