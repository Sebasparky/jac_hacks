// Approval gate interface — UI implementations inject a concrete requestApproval function.
// This file defines the contract and a CLI fallback for testing.

export type ApprovalRequest = {
  stepId: string;
  stepName: string;
  reason: string;
};

export type ApprovalGate = (request: ApprovalRequest) => Promise<boolean>;

/**
 * Auto-approve gate for automated testing only.
 * Never use in production workflows with high-stakes steps.
 */
export const autoApproveGate: ApprovalGate = async () => true;

/**
 * Auto-deny gate — useful for dry runs.
 */
export const autoDenyGate: ApprovalGate = async () => false;
