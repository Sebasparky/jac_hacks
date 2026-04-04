import type { WorkflowStep } from "../../shared/types/workflow.js";
import type { SafetyRule } from "../../shared/types/safety.js";
import { newRuleId } from "../../shared/utils/ids.js";

const SUBMIT_TEXT_PATTERNS = [/submit/i, /confirm/i, /place order/i, /pay/i, /delete/i, /remove/i];

/**
 * Infers safety rules from compiled steps.
 * These are conservative defaults — users can remove them in the workflow editor.
 */
export function inferSafetyRules(steps: WorkflowStep[]): SafetyRule[] {
  const rules: SafetyRule[] = [];

  for (const step of steps) {
    if (step.type !== "click") continue;

    const primary = step.target?.primary;
    if (!primary) continue;

    const text =
      primary.kind === "text" ? primary.text :
      primary.kind === "label" ? primary.label :
      undefined;

    if (text && SUBMIT_TEXT_PATTERNS.some((p) => p.test(text))) {
      rules.push({
        id: newRuleId(),
        description: `Require approval before clicking "${text}"`,
        condition: { kind: "target_text_contains", value: text },
        action: "require_approval",
      });
    }
  }

  return rules;
}
