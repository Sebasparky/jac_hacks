// Annotations are first-class. They influence both compilation and runtime behavior —
// they are not passive notes.

export type GlobalAnnotationType =
  | "goal"
  | "constraint"
  | "safety"
  | "parameter_hint"
  | "repair_hint"
  | "success_hint";

export type StepAnnotationType =
  | "intent"
  | "warning"
  | "parameter_hint"
  | "repair_hint"
  | "safety_rule"
  | "success_hint";

/** Attached to the workflow as a whole. May apply to specific steps or domains. */
export type GlobalAnnotation = {
  id: string;
  type: GlobalAnnotationType;
  text: string;
  appliesTo?: {
    stepIds?: string[];
    domains?: string[];
  };
  createdAt: string;
};

/** Attached to a single step during recording or editing. */
export type StepAnnotation = {
  id: string;
  type: StepAnnotationType;
  text: string;
  createdAt: string;
};
