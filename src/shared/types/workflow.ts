import type { GlobalAnnotation, StepAnnotation } from "./annotations.js";
import type { WorkflowSafetyPolicy } from "./safety.js";
import type { WorkflowPrivacyPolicy } from "./privacy.js";

// ---------------------------------------------------------------------------
// Value resolution
// ---------------------------------------------------------------------------

/** How a step obtains a value at runtime. Literals are baked in; everything else is resolved. */
export type ValueSpec =
  | { kind: "literal"; value: string | number | boolean }
  | { kind: "input"; inputName: string }
  | { kind: "secret"; secretKey: string }
  | { kind: "derived"; expression: string }
  | { kind: "runtime_memory"; key: string };

// ---------------------------------------------------------------------------
// Target resolution
// ---------------------------------------------------------------------------

/** Semantic-first locator strategies. CSS/XPath are last-resort fallbacks. */
export type TargetLocator =
  | { kind: "label"; label: string; role?: string }
  | { kind: "text"; text: string; role?: string; exact?: boolean }
  | { kind: "placeholder"; placeholder: string }
  | { kind: "name"; name: string }
  | { kind: "testid"; testId: string }
  | { kind: "css"; selector: string }
  | { kind: "xpath"; selector: string };

export type TargetSpec = {
  /** Optional iframe or frame identifier. */
  frameHint?: string;
  /** Preferred locator — should be semantic (label, text, placeholder, name, testid). */
  primary: TargetLocator;
  /** Tried in order if primary fails. */
  fallbacks?: TargetLocator[];
  /** Hints that help resolver score candidates when locators are ambiguous. */
  resolutionHints?: {
    expectedTag?: string;
    nearbyText?: string[];
    sectionHeading?: string;
    formName?: string;
  };
};

// ---------------------------------------------------------------------------
// Wait and assert signals
// ---------------------------------------------------------------------------

export type WaitSignal =
  | { kind: "navigation"; urlIncludes?: string }
  | { kind: "element_present"; target: TargetSpec }
  | { kind: "text_present"; text: string }
  | { kind: "element_hidden"; target: TargetSpec };

export type AssertSignal =
  | { kind: "url_includes"; value: string }
  | { kind: "text_present"; text: string }
  | { kind: "element_present"; target: TargetSpec }
  | { kind: "element_not_present"; target: TargetSpec };

export type Postcondition = {
  description?: string;
  signal: WaitSignal | AssertSignal;
};

// ---------------------------------------------------------------------------
// Failure policy
// ---------------------------------------------------------------------------

export type FailurePolicy = {
  retry?: { attempts: number; delayMs: number };
  /** What to do after retries are exhausted. */
  fallbackStrategy?: "try_next_locator" | "repair" | "ask_user" | "abort";
  /** Plain-text hints forwarded to the repair engine if repair is attempted. */
  repairHints?: string[];
  /** Message shown to the user if fallbackStrategy is ask_user or abort. */
  userMessage?: string;
};

// ---------------------------------------------------------------------------
// Runtime conditions (for branch logic and safety gating)
// ---------------------------------------------------------------------------

export type RuntimeCondition =
  | { kind: "input_equals"; inputName: string; value: string | number | boolean }
  | { kind: "input_greater_than"; inputName: string; value: number }
  | { kind: "memory_exists"; key: string };

// ---------------------------------------------------------------------------
// Base step
// ---------------------------------------------------------------------------

export type BaseStep = {
  id: string;
  /** Discriminant — each concrete step type sets this. */
  type: string;
  name?: string;
  description?: string;
  /** Live notes attached during recording or editing. Influence compile and runtime behavior. */
  annotations?: StepAnnotation[];
  target?: TargetSpec;
  /** Pause execution and show an approval prompt before this step runs. */
  requiresApproval?: boolean;
  timeoutMs?: number;
  /** 0–1 compiler confidence that this step was correctly inferred. */
  confidence?: number;
  postconditions?: Postcondition[];
  onFailure?: FailurePolicy;
};

// ---------------------------------------------------------------------------
// Concrete step types
// ---------------------------------------------------------------------------

export type GotoStep = BaseStep & { type: "goto"; url: string };

export type ClickStep = BaseStep & { type: "click" };

export type FillStep = BaseStep & {
  type: "fill";
  value: ValueSpec;
  clearFirst?: boolean;
};

export type SelectStep = BaseStep & {
  type: "select";
  value: ValueSpec;
  matchMode?: "label" | "value" | "text";
};

export type WaitForStep = BaseStep & {
  type: "wait_for";
  signal: WaitSignal;
};

export type AssertStep = BaseStep & {
  type: "assert";
  signal: AssertSignal;
};

export type ExtractStep = BaseStep & {
  type: "extract";
  /** Key under which the extracted value is stored in runtimeMemory. */
  outputKey: string;
  extraction: {
    kind: "text" | "value" | "attribute";
    attributeName?: string;
  };
};

export type UploadFileStep = BaseStep & {
  type: "upload_file";
  file: ValueSpec;
};

export type BranchStep = BaseStep & {
  type: "branch";
  condition: RuntimeCondition;
  ifTrue: WorkflowStep[];
  ifFalse?: WorkflowStep[];
};

/** Discriminated union — add new step types here and in stepDispatcher. */
export type WorkflowStep =
  | GotoStep
  | ClickStep
  | FillStep
  | SelectStep
  | WaitForStep
  | AssertStep
  | ExtractStep
  | UploadFileStep
  | BranchStep;

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

export type WorkflowInputType =
  | "string"
  | "number"
  | "boolean"
  | "date"
  | "email"
  | "password"
  | "file"
  | "select";

export type WorkflowInput = {
  name: string;
  label: string;
  type: WorkflowInputType;
  required: boolean;
  /** Value must never be sent to an LLM or stored in plain text. */
  secret?: boolean;
  description?: string;
  defaultValue?: string | number | boolean | null;
  options?: string[];
  sourceHint?: {
    inferredFromStepIds?: string[];
    inferenceReason?: string;
  };
  validation?: {
    regex?: string;
    min?: number;
    max?: number;
  };
};

// ---------------------------------------------------------------------------
// Workflow metadata
// ---------------------------------------------------------------------------

export type WorkflowMetadata = {
  createdAt: string;
  updatedAt: string;
  createdByUserId: string;
  source: {
    recordingSessionId: string;
    origin: "browser-recording";
    startUrl?: string;
    domains: string[];
  };
  tags?: string[];
};

// ---------------------------------------------------------------------------
// Workflow context (global intent)
// ---------------------------------------------------------------------------

export type WorkflowContext = {
  goal: string;
  summary?: string;
  constraints?: string[];
  successCriteria?: string[];
  executionNotes?: string[];
  userProvidedContext?: string[];
  /** Global annotations — not tied to any single step. */
  annotations?: GlobalAnnotation[];
};

// ---------------------------------------------------------------------------
// Compile info
// ---------------------------------------------------------------------------

export type WorkflowCompileInfo = {
  compilerVersion: string;
  compiledAt: string;
  sourceTraceId: string;
  compileNotes?: string[];
  warnings?: string[];
  /** Maps each compiled step back to the raw trace events it came from. */
  stepOrigins?: Array<{
    stepId: string;
    sourceEventIds: string[];
  }>;
};

// ---------------------------------------------------------------------------
// Runtime state (mutable, updated after each run)
// ---------------------------------------------------------------------------

export type LearnedRepair = {
  stepId: string;
  previousLocator: TargetLocator;
  updatedLocator: TargetLocator;
  learnedAt: string;
  successCount: number;
};

export type WorkflowRuntimeState = {
  lastRunAt?: string;
  lastRunStatus?: "success" | "failed" | "partial";
  /** Locators that were updated by the repair engine and have since succeeded. */
  learnedRepairs?: LearnedRepair[];
  /** Values extracted during execution and available to downstream steps. */
  runtimeMemory?: Record<string, string | number | boolean>;
};

// ---------------------------------------------------------------------------
// Top-level workflow
// ---------------------------------------------------------------------------

export type Workflow = {
  version: "1.0";
  id: string;
  name: string;
  description?: string;
  metadata: WorkflowMetadata;
  context: WorkflowContext;
  inputs: WorkflowInput[];
  steps: WorkflowStep[];
  safety: WorkflowSafetyPolicy;
  privacy: WorkflowPrivacyPolicy;
  compileInfo: WorkflowCompileInfo;
  runtimeState?: WorkflowRuntimeState;
};
