import type { WorkflowStep } from "../../shared/types/workflow.js";
import type { WorkflowSafetyPolicy, SafetyRuleCondition } from "../../shared/types/safety.js";

export type SafetyDecision =
  | { action: "proceed" }
  | { action: "require_approval"; reason: string }
  | { action: "warn"; reason: string }
  | { action: "abort"; reason: string };

/**
 * Evaluates all safety rules against the current step and runtime inputs.
 * Returns the most restrictive decision (abort > approval > warn > proceed).
 */
export function evaluateSafety(
  step: WorkflowStep,
  policy: WorkflowSafetyPolicy,
  inputs: Record<string, string | number | boolean>
): SafetyDecision {
  const decisions: SafetyDecision[] = [];

  for (const rule of policy.customRules ?? []) {
    const matches = matchesCondition(rule.condition, step, inputs);
    if (!matches) continue;

    switch (rule.action) {
      case "abort":
        return { action: "abort", reason: rule.description };
      case "require_approval":
        decisions.push({ action: "require_approval", reason: rule.description });
        break;
      case "warn":
        decisions.push({ action: "warn", reason: rule.description });
        break;
    }
  }

  // Return highest-priority non-abort decision, or proceed
  return decisions.find((d) => d.action === "require_approval")
    ?? decisions.find((d) => d.action === "warn")
    ?? { action: "proceed" };
}

function matchesCondition(
  condition: SafetyRuleCondition,
  step: WorkflowStep,
  inputs: Record<string, string | number | boolean>
): boolean {
  switch (condition.kind) {
    case "step_type":
      return step.type === condition.value;

    case "target_text_contains": {
      const primary = step.target?.primary;
      if (!primary) return false;
      const text =
        primary.kind === "text" ? primary.text :
        primary.kind === "label" ? primary.label :
        undefined;
      return text ? text.toLowerCase().includes(condition.value.toLowerCase()) : false;
    }

    case "input_greater_than": {
      const value = inputs[condition.inputName];
      return typeof value === "number" && value > condition.value;
    }

    default: {
      const _: never = condition;
      return false;
    }
  }
}
