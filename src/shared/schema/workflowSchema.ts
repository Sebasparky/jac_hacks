import { z } from "zod";

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

const StepAnnotationSchema = z.object({
  id: z.string(),
  type: z.enum(["intent", "warning", "parameter_hint", "repair_hint", "safety_rule", "success_hint"]),
  text: z.string().min(1),
  createdAt: z.string().datetime(),
});

const GlobalAnnotationSchema = z.object({
  id: z.string(),
  type: z.enum(["goal", "constraint", "safety", "parameter_hint", "repair_hint", "success_hint"]),
  text: z.string().min(1),
  appliesTo: z.object({
    stepIds: z.array(z.string()).optional(),
    domains: z.array(z.string()).optional(),
  }).optional(),
  createdAt: z.string().datetime(),
});

// ---------------------------------------------------------------------------
// Target resolution
// ---------------------------------------------------------------------------

const TargetLocatorSchema: z.ZodType = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("label"), label: z.string(), role: z.string().optional() }),
  z.object({ kind: z.literal("text"), text: z.string(), role: z.string().optional(), exact: z.boolean().optional() }),
  z.object({ kind: z.literal("placeholder"), placeholder: z.string() }),
  z.object({ kind: z.literal("name"), name: z.string() }),
  z.object({ kind: z.literal("testid"), testId: z.string() }),
  z.object({ kind: z.literal("css"), selector: z.string() }),
  z.object({ kind: z.literal("xpath"), selector: z.string() }),
]);

const TargetSpecSchema = z.object({
  frameHint: z.string().optional(),
  primary: TargetLocatorSchema,
  fallbacks: z.array(TargetLocatorSchema).optional(),
  resolutionHints: z.object({
    expectedTag: z.string().optional(),
    nearbyText: z.array(z.string()).optional(),
    sectionHeading: z.string().optional(),
    formName: z.string().optional(),
  }).optional(),
});

// ---------------------------------------------------------------------------
// Wait / assert signals
// ---------------------------------------------------------------------------

const WaitSignalSchema: z.ZodType = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("navigation"), urlIncludes: z.string().optional() }),
  z.object({ kind: z.literal("element_present"), target: TargetSpecSchema }),
  z.object({ kind: z.literal("text_present"), text: z.string() }),
  z.object({ kind: z.literal("element_hidden"), target: TargetSpecSchema }),
]);

const AssertSignalSchema: z.ZodType = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("url_includes"), value: z.string() }),
  z.object({ kind: z.literal("text_present"), text: z.string() }),
  z.object({ kind: z.literal("element_present"), target: TargetSpecSchema }),
  z.object({ kind: z.literal("element_not_present"), target: TargetSpecSchema }),
]);

const PostconditionSchema = z.object({
  description: z.string().optional(),
  signal: z.union([WaitSignalSchema, AssertSignalSchema]),
});

// ---------------------------------------------------------------------------
// Failure policy
// ---------------------------------------------------------------------------

const FailurePolicySchema = z.object({
  retry: z.object({ attempts: z.number().int().min(1), delayMs: z.number().min(0) }).optional(),
  fallbackStrategy: z.enum(["try_next_locator", "repair", "ask_user", "abort"]).optional(),
  repairHints: z.array(z.string()).optional(),
  userMessage: z.string().optional(),
});

// ---------------------------------------------------------------------------
// Value spec
// ---------------------------------------------------------------------------

const ValueSpecSchema: z.ZodType = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("literal"), value: z.union([z.string(), z.number(), z.boolean()]) }),
  z.object({ kind: z.literal("input"), inputName: z.string() }),
  z.object({ kind: z.literal("secret"), secretKey: z.string() }),
  z.object({ kind: z.literal("derived"), expression: z.string() }),
  z.object({ kind: z.literal("runtime_memory"), key: z.string() }),
]);

// ---------------------------------------------------------------------------
// Base step fields (shared by all step schemas)
// ---------------------------------------------------------------------------

const BaseStepFields = {
  id: z.string(),
  name: z.string().optional(),
  description: z.string().optional(),
  annotations: z.array(StepAnnotationSchema).optional(),
  target: TargetSpecSchema.optional(),
  requiresApproval: z.boolean().optional(),
  timeoutMs: z.number().optional(),
  confidence: z.number().min(0).max(1).optional(),
  postconditions: z.array(PostconditionSchema).optional(),
  onFailure: FailurePolicySchema.optional(),
};

// ---------------------------------------------------------------------------
// Runtime condition
// ---------------------------------------------------------------------------

const RuntimeConditionSchema: z.ZodType = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("input_equals"), inputName: z.string(), value: z.union([z.string(), z.number(), z.boolean()]) }),
  z.object({ kind: z.literal("input_greater_than"), inputName: z.string(), value: z.number() }),
  z.object({ kind: z.literal("memory_exists"), key: z.string() }),
]);

// ---------------------------------------------------------------------------
// Concrete step schemas
// ---------------------------------------------------------------------------

const GotoStepSchema = z.object({ ...BaseStepFields, type: z.literal("goto"), url: z.string().url() });
const ClickStepSchema = z.object({ ...BaseStepFields, type: z.literal("click") });
const FillStepSchema = z.object({ ...BaseStepFields, type: z.literal("fill"), value: ValueSpecSchema, clearFirst: z.boolean().optional() });
const SelectStepSchema = z.object({ ...BaseStepFields, type: z.literal("select"), value: ValueSpecSchema, matchMode: z.enum(["label", "value", "text"]).optional() });
const WaitForStepSchema = z.object({ ...BaseStepFields, type: z.literal("wait_for"), signal: WaitSignalSchema });
const AssertStepSchema = z.object({ ...BaseStepFields, type: z.literal("assert"), signal: AssertSignalSchema });
const ExtractStepSchema = z.object({
  ...BaseStepFields,
  type: z.literal("extract"),
  outputKey: z.string(),
  extraction: z.object({
    kind: z.enum(["text", "value", "attribute"]),
    attributeName: z.string().optional(),
  }),
});
const UploadFileStepSchema = z.object({ ...BaseStepFields, type: z.literal("upload_file"), file: ValueSpecSchema });

// BranchStep is self-referential. z.lazy cannot join a discriminatedUnion directly,
// so we use z.union for the top-level step schema and keep z.lazy for branch's inner steps.
const NonBranchStepSchemas = [
  GotoStepSchema,
  ClickStepSchema,
  FillStepSchema,
  SelectStepSchema,
  WaitForStepSchema,
  AssertStepSchema,
  ExtractStepSchema,
  UploadFileStepSchema,
] as const;

// Forward declaration for recursive reference
export const WorkflowStepSchema: z.ZodType = z.lazy(() =>
  z.union([
    ...NonBranchStepSchemas,
    z.object({
      ...BaseStepFields,
      type: z.literal("branch"),
      condition: RuntimeConditionSchema,
      ifTrue: z.array(WorkflowStepSchema),
      ifFalse: z.array(WorkflowStepSchema).optional(),
    }),
  ])
);

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

const WorkflowInputSchema = z.object({
  name: z.string().regex(/^[a-z_][a-z0-9_]*$/, "Input name must be snake_case"),
  label: z.string().min(1),
  type: z.enum(["string", "number", "boolean", "date", "email", "password", "file", "select"]),
  required: z.boolean(),
  secret: z.boolean().optional(),
  description: z.string().optional(),
  defaultValue: z.union([z.string(), z.number(), z.boolean(), z.null()]).optional(),
  options: z.array(z.string()).optional(),
  sourceHint: z.object({
    inferredFromStepIds: z.array(z.string()).optional(),
    inferenceReason: z.string().optional(),
  }).optional(),
  validation: z.object({
    regex: z.string().optional(),
    min: z.number().optional(),
    max: z.number().optional(),
  }).optional(),
});

// ---------------------------------------------------------------------------
// Safety and privacy
// ---------------------------------------------------------------------------

const SafetyRuleSchema = z.object({
  id: z.string(),
  description: z.string(),
  condition: z.union([
    z.object({ kind: z.literal("step_type"), value: z.string() }),
    z.object({ kind: z.literal("target_text_contains"), value: z.string() }),
    z.object({ kind: z.literal("input_greater_than"), inputName: z.string(), value: z.number() }),
  ]),
  action: z.enum(["require_approval", "abort", "warn"]),
});

const WorkflowSafetyPolicySchema = z.object({
  allowedDomains: z.array(z.string()).min(1),
  requireApprovalFor: z.array(z.enum(["final_submit", "delete", "purchase", "send_email", "external_navigation"])).optional(),
  customRules: z.array(SafetyRuleSchema).optional(),
});

const WorkflowPrivacyPolicySchema = z.object({
  mode: z.enum(["cloud", "local", "hybrid"]),
  sensitiveInputs: z.array(z.string()).optional(),
  maskRecordingFields: z.array(z.string()).optional(),
  neverPersistSelectorsContainingText: z.array(z.string()).optional(),
  llmUsage: z.object({
    allowDuringCompile: z.boolean(),
    allowDuringRepair: z.boolean(),
    allowRawDomInRepair: z.boolean(),
  }),
});

// ---------------------------------------------------------------------------
// Top-level workflow schema
// ---------------------------------------------------------------------------

export const WorkflowSchema = z.object({
  version: z.literal("1.0"),
  id: z.string(),
  name: z.string().min(1),
  description: z.string().optional(),

  metadata: z.object({
    createdAt: z.string().datetime(),
    updatedAt: z.string().datetime(),
    createdByUserId: z.string(),
    source: z.object({
      recordingSessionId: z.string(),
      origin: z.literal("browser-recording"),
      startUrl: z.string().url().optional(),
      domains: z.array(z.string()).min(1),
    }),
    tags: z.array(z.string()).optional(),
  }),

  context: z.object({
    goal: z.string().min(1),
    summary: z.string().optional(),
    constraints: z.array(z.string()).optional(),
    successCriteria: z.array(z.string()).optional(),
    executionNotes: z.array(z.string()).optional(),
    userProvidedContext: z.array(z.string()).optional(),
    annotations: z.array(GlobalAnnotationSchema).optional(),
  }),

  inputs: z.array(WorkflowInputSchema),
  steps: z.array(WorkflowStepSchema).min(1),

  safety: WorkflowSafetyPolicySchema,
  privacy: WorkflowPrivacyPolicySchema,

  compileInfo: z.object({
    compilerVersion: z.string(),
    compiledAt: z.string().datetime(),
    sourceTraceId: z.string(),
    compileNotes: z.array(z.string()).optional(),
    warnings: z.array(z.string()).optional(),
    stepOrigins: z.array(z.object({
      stepId: z.string(),
      sourceEventIds: z.array(z.string()),
    })).optional(),
  }),

  runtimeState: z.object({
    lastRunAt: z.string().datetime().optional(),
    lastRunStatus: z.enum(["success", "failed", "partial"]).optional(),
    learnedRepairs: z.array(z.object({
      stepId: z.string(),
      previousLocator: TargetLocatorSchema,
      updatedLocator: TargetLocatorSchema,
      learnedAt: z.string().datetime(),
      successCount: z.number().int().min(1),
    })).optional(),
    runtimeMemory: z.record(z.union([z.string(), z.number(), z.boolean()])).optional(),
  }).optional(),
});

export type WorkflowSchemaType = z.infer<typeof WorkflowSchema>;
