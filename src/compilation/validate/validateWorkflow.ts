import { WorkflowSchema } from "../../shared/schema/workflowSchema.js";
import type { Workflow } from "../../shared/types/workflow.js";

export type ValidationResult =
  | { ok: true; workflow: Workflow }
  | { ok: false; errors: string[] };

/**
 * Validates a workflow object against the schema.
 * Called before persisting a compiled workflow and before execution.
 */
export function validateWorkflow(candidate: unknown): ValidationResult {
  const result = WorkflowSchema.safeParse(candidate);

  if (result.success) {
    return { ok: true, workflow: result.data as Workflow };
  }

  const errors = result.error.issues.map(
    (issue) => `${issue.path.join(".")}: ${issue.message}`
  );
  return { ok: false, errors };
}
