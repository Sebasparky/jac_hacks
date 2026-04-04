import type { RawEvent } from "../../shared/types/trace.js";
import { isSensitiveField } from "./sensitiveFieldDetector.js";

const MASK = "***";

/** Returns a copy of the event with sensitive values replaced by the mask sentinel. */
export function maskEventValues(event: RawEvent): RawEvent {
  if (event.type !== "input" && event.type !== "change") return event;

  const el = event.element;
  const sensitive = isSensitiveField({
    ...(el.name !== undefined && { name: el.name }),
    ...(el.label !== undefined && { label: el.label }),
    ...(el.placeholder !== undefined && { placeholder: el.placeholder }),
    ...(el.type !== undefined && { type: el.type }),
    ...(el.id !== undefined && { id: el.id }),
  });

  if (!sensitive) return event;

  return { ...event, value: MASK, masked: true };
}
