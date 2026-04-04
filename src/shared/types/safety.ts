import type { WorkflowStep } from "./workflow.js";

// Safety rules are executable conditions, not passive notes.
// They are evaluated at runtime before high-stakes steps execute.

export type SafetyRuleCondition =
  | { kind: "step_type"; value: WorkflowStep["type"] }
  | { kind: "target_text_contains"; value: string }
  | { kind: "input_greater_than"; inputName: string; value: number };

export type SafetyRuleAction = "require_approval" | "abort" | "warn";

export type SafetyRule = {
  id: string;
  description: string;
  condition: SafetyRuleCondition;
  action: SafetyRuleAction;
};

export type HighStakesAction =
  | "final_submit"
  | "delete"
  | "purchase"
  | "send_email"
  | "external_navigation";

export type WorkflowSafetyPolicy = {
  /** Execution will abort if the current domain is not in this list. */
  allowedDomains: string[];
  /** Step types that always require user approval before execution. */
  requireApprovalFor?: HighStakesAction[];
  /** Custom conditions that trigger approval, abort, or warning. */
  customRules?: SafetyRule[];
};
