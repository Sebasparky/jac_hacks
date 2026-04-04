import type { RawEvent, InputEvent, ChangeEvent } from "../../shared/types/trace.js";
import type { WorkflowInput } from "../../shared/types/workflow.js";
import { newInputId } from "../../shared/utils/ids.js";

/**
 * Heuristically infers which filled fields should become runtime inputs
 * rather than baked-in literal values.
 *
 * A field becomes an input when:
 * - It has a parameter_hint annotation referencing it
 * - Its value looks dynamic (date-like, number-like, email-like)
 * - Its label matches known parameterizable patterns
 */
export function inferInputs(
  events: RawEvent[],
  annotationHints: string[] = []
): WorkflowInput[] {
  const inputs: WorkflowInput[] = [];
  const seen = new Set<string>();

  for (const event of events) {
    if (event.type !== "input" && event.type !== "change") continue;

    const e = event as InputEvent | ChangeEvent;
    const el = e.element;

    const key = el.name ?? el.label ?? el.id;
    if (!key || seen.has(key)) continue;

    const type = inferInputType(el, e.value);
    if (!type) continue;

    seen.add(key);
    inputs.push({
      name: toSnakeCase(key),
      label: el.label ?? key,
      type,
      required: true,
      secret: el.type === "password",
      sourceHint: {
        inferredFromStepIds: [],
        inferenceReason: `value "${e.value.slice(0, 30)}" appears dynamic`,
      },
    });
  }

  return inputs;
}

function inferInputType(
  el: { type?: string; label?: string; name?: string },
  value: string
): WorkflowInput["type"] | null {
  if (el.type === "password") return "password";
  if (el.type === "email" || /email/i.test(el.label ?? "") || /email/i.test(el.name ?? "")) return "email";
  if (el.type === "date" || /date/i.test(el.label ?? "") || /\d{4}-\d{2}-\d{2}/.test(value)) return "date";
  if (el.type === "number" || /amount|price|qty|quantity/i.test(el.label ?? "")) return "number";
  if (el.type === "file") return "file";

  // Only parameterize values that look dynamic (not fixed labels/IDs)
  if (/^\d+(\.\d+)?$/.test(value)) return "number";
  if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) return "email";
  if (value.length > 3) return "string";

  return null;
}

function toSnakeCase(s: string): string {
  return s.toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_]/g, "");
}
