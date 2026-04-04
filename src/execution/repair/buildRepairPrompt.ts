import type { RepairContext } from "./repairEngine.js";

export function buildRepairPrompt(context: RepairContext): string {
  const step = context.step;
  const annotations = step.annotations
    ?.filter((a) => a.type === "repair_hint")
    .map((a) => `- ${a.text}`)
    .join("\n") ?? "";

  const domSection = context.allowRawDom
    ? `\nPage snapshot (truncated):\n${context.pageSnapshot.slice(0, 3000)}`
    : "\n(Raw DOM omitted by privacy policy)";

  return `A workflow step failed to find its target element.

Step: ${step.name ?? step.id} (type: ${step.type})
Failed locator: ${JSON.stringify(context.failedLocator)}

Repair hints from user annotations:
${annotations || "(none)"}
${domSection}

Return a single JSON object representing a new TargetLocator that should find the correct element.
Prefer semantic locators (label, text, placeholder) over CSS/XPath.
Return only the JSON object, no prose.`;
}
