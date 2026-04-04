import type { CleanedTrace } from "../../shared/types/trace.js";

export type CompilerPromptOptions = {
  goalContext?: string;
  userAnnotations?: string[];
  /** When true, raw DOM snapshots are omitted (privacy policy: allowRawDomInRepair=false). */
  omitRawDom?: boolean;
};

/**
 * Builds a structured prompt asking the model to infer workflow structure from a cleaned trace.
 * The model should return a partial Workflow JSON object.
 * Heuristic inference runs first — this prompt is only called when heuristics are insufficient.
 */
export function buildCompilerPrompt(
  trace: CleanedTrace,
  options: CompilerPromptOptions = {}
): string {
  const eventSummary = trace.events
    .filter((e) => e.type !== "focus" && e.type !== "blur")
    .map((e) => {
      const base = `[${e.type}] ${e.url}`;
      if (e.type === "input" || e.type === "change") {
        const el = e.element;
        return `${base} | field: ${el.label ?? el.name ?? el.id ?? "?"} | value: ${e.masked ? "***" : e.value}`;
      }
      if (e.type === "click") {
        const el = e.element;
        return `${base} | target: ${el.label ?? el.innerText ?? el.id ?? "?"}`;
      }
      if (e.type === "navigation") {
        return `${base} -> ${e.url}`;
      }
      if (e.type === "annotation") {
        return `[user note: ${e.text}]`;
      }
      return base;
    })
    .join("\n");

  const annotationSection = options.userAnnotations?.length
    ? `\nUser annotations:\n${options.userAnnotations.map((a) => `- ${a}`).join("\n")}`
    : "";

  const goalSection = options.goalContext
    ? `\nTask goal: ${options.goalContext}`
    : "";

  return `You are a workflow compiler. Given a cleaned browser recording trace, output a structured workflow in JSON.

Rules:
- Infer which field values should be runtime inputs vs literals.
- Attach postconditions to submit and confirm actions.
- Add assert steps after navigations and form submissions.
- Return only valid JSON matching the Workflow schema. Do not include prose.
- Set confidence on each step between 0 and 1.
- If a field value was masked (***), mark the input as secret: true.
${goalSection}${annotationSection}

Trace:
${eventSummary}
`;
}
