import { v4 as uuidv4 } from "uuid";

export function generateId(prefix: string): string {
  return `${prefix}_${uuidv4().replace(/-/g, "").slice(0, 16)}`;
}

export const newWorkflowId = () => generateId("wf");
export const newStepId = () => generateId("step");
export const newAnnotationId = () => generateId("ann");
export const newSessionId = () => generateId("sess");
export const newEventId = () => generateId("evt");
export const newInputId = () => generateId("inp");
export const newRuleId = () => generateId("rule");
