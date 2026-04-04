import type { Workflow, TargetLocator, LearnedRepair } from "../../shared/types/workflow.js";
import { now } from "../../shared/utils/timestamps.js";

/**
 * Persists a successful repair to the workflow's runtimeState.
 * On subsequent runs, workflowRunner applies the learned locator before trying the original.
 */
export function saveLearnedRepair(
  workflow: Workflow,
  stepId: string,
  previousLocator: TargetLocator,
  updatedLocator: TargetLocator
): Workflow {
  const existing = workflow.runtimeState?.learnedRepairs?.find(
    (r) => r.stepId === stepId && JSON.stringify(r.updatedLocator) === JSON.stringify(updatedLocator)
  );

  const repair: LearnedRepair = existing
    ? { ...existing, successCount: existing.successCount + 1 }
    : { stepId, previousLocator, updatedLocator, learnedAt: now(), successCount: 1 };

  const repairs = [
    ...(workflow.runtimeState?.learnedRepairs?.filter((r) => r !== existing) ?? []),
    repair,
  ];

  return {
    ...workflow,
    runtimeState: {
      ...workflow.runtimeState,
      learnedRepairs: repairs,
    },
  };
}
