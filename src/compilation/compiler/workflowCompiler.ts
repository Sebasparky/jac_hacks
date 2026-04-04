import type { RecordingSession, CleanedTrace, RawEvent } from "../../shared/types/trace.js";
import type { Workflow, WorkflowStep, ClickStep, FillStep, GotoStep, SelectStep } from "../../shared/types/workflow.js";
import type { WorkflowSafetyPolicy } from "../../shared/types/safety.js";
import type { WorkflowPrivacyPolicy } from "../../shared/types/privacy.js";

import { mergeTypingEvents } from "../cleaner/mergeTypingEvents.js";
import { removeNoise } from "../cleaner/removeNoise.js";
import { collapseDuplicateClicks } from "../cleaner/collapseDuplicateClicks.js";
import { inferInputs } from "../inference/inferInputs.js";
import { inferAssertions } from "../inference/inferAssertions.js";
import { inferSafetyRules } from "../inference/inferSafetyRules.js";
import { validateWorkflow } from "../validate/validateWorkflow.js";
import type { ModelProvider, CompileWithModelOptions } from "../llm/compileTraceWithModel.js";
import { compileTraceWithModel } from "../llm/compileTraceWithModel.js";

import { newWorkflowId, newStepId, newAnnotationId } from "../../shared/utils/ids.js";
import { now } from "../../shared/utils/timestamps.js";

const COMPILER_VERSION = "0.1.0";

export type CompilerOptions = {
  /** Injected model provider. If omitted, compilation is heuristic-only. */
  model?: ModelProvider;
  modelOptions?: CompileWithModelOptions;
  privacy: WorkflowPrivacyPolicy;
  createdByUserId: string;
};

export type CompileResult =
  | { ok: true; workflow: Workflow; warnings: string[] }
  | { ok: false; errors: string[]; warnings: string[] };

// ---------------------------------------------------------------------------
// Pipeline:
//   raw session -> clean -> heuristic compile -> optional LLM enrich -> validate
// ---------------------------------------------------------------------------

export async function compileSession(
  session: RecordingSession,
  options: CompilerOptions
): Promise<CompileResult> {
  const warnings: string[] = [];

  // 1. Clean
  const cleaned = cleanTrace(session);
  warnings.push(...cleaned.removedEventIds.map((r) => `Removed event ${r.id}: ${r.reason}`));

  // 2. Heuristic compilation
  let partial = heuristicCompile(session, cleaned, options);

  // 3. Optional LLM enrichment
  if (options.model && options.privacy.llmUsage.allowDuringCompile) {
    const modelOpts: CompileWithModelOptions = {
      omitRawDom: !options.privacy.llmUsage.allowRawDomInRepair,
      ...options.modelOptions,
    };
    if (session.goalContext) modelOpts.goalContext = session.goalContext;
    const modelResult = await compileTraceWithModel(cleaned, options.model, modelOpts);
    // Merge model output — model may improve step names, confidence, and context
    partial = mergeModelResult(partial, modelResult);
  }

  // 4. Validate
  const validation = validateWorkflow(partial);
  if (!validation.ok) {
    return { ok: false, errors: validation.errors, warnings };
  }

  return { ok: true, workflow: validation.workflow, warnings };
}

// ---------------------------------------------------------------------------
// Clean pass
// ---------------------------------------------------------------------------

function cleanTrace(session: RecordingSession): CleanedTrace {
  let events = session.events;

  const noiseResult = removeNoise(events);
  events = noiseResult.events;
  events = mergeTypingEvents(events);
  events = collapseDuplicateClicks(events);

  return {
    sessionId: session.id,
    cleanedAt: now(),
    removedEventIds: noiseResult.removed,
    events,
  };
}

// ---------------------------------------------------------------------------
// Heuristic compiler — converts clean events to workflow steps
// ---------------------------------------------------------------------------

function heuristicCompile(
  session: RecordingSession,
  cleaned: CleanedTrace,
  options: CompilerOptions
): Partial<Workflow> {
  const stepOrigins: Array<{ stepId: string; sourceEventIds: string[] }> = [];
  const steps: WorkflowStep[] = [];

  for (const event of cleaned.events) {
    const step = eventToStep(event);
    if (step) {
      steps.push(step);
      stepOrigins.push({ stepId: step.id, sourceEventIds: [event.id] });
    }
  }

  // Inject inferred assertions after steps
  const assertionSteps = inferAssertions(cleaned.events);
  steps.push(...assertionSteps);

  const inferredInputs = inferInputs(cleaned.events);
  const inferredRules = inferSafetyRules(steps);

  const domains = [...new Set(cleaned.events.map((e) => new URL(e.url).hostname))];

  const safety: WorkflowSafetyPolicy = {
    allowedDomains: domains,
    requireApprovalFor: ["final_submit", "delete", "purchase"],
    customRules: inferredRules,
  };

  return {
    version: "1.0",
    id: newWorkflowId(),
    name: session.goalContext ?? "Untitled workflow",
    metadata: {
      createdAt: now(),
      updatedAt: now(),
      createdByUserId: options.createdByUserId,
      source: {
        recordingSessionId: session.id,
        origin: "browser-recording",
        startUrl: session.startUrl,
        domains,
      },
    },
    context: {
      goal: session.goalContext ?? "",
      userProvidedContext: session.goalContext ? [session.goalContext] : [],
    },
    inputs: inferredInputs,
    steps,
    safety,
    privacy: options.privacy,
    compileInfo: {
      compilerVersion: COMPILER_VERSION,
      compiledAt: now(),
      sourceTraceId: session.id,
      stepOrigins,
    },
  };
}

function eventToStep(event: RawEvent): WorkflowStep | null {
  const id = newStepId();

  switch (event.type) {
    case "navigation":
      return { id, type: "goto", url: event.url } satisfies GotoStep;

    case "click": {
      const el = event.element;
      const primary =
        el.label ? { kind: "label" as const, label: el.label } :
        el.innerText ? { kind: "text" as const, text: el.innerText.slice(0, 60) } :
        el.placeholder ? { kind: "placeholder" as const, placeholder: el.placeholder } :
        el.name ? { kind: "name" as const, name: el.name } :
        el.testId ? { kind: "testid" as const, testId: el.testId } :
        el.cssSelector ? { kind: "css" as const, selector: el.cssSelector } :
        null;

      if (!primary) return null;

      const hints: { nearbyText?: string[]; sectionHeading?: string; formName?: string } = {};
      if (el.nearbyText) hints.nearbyText = el.nearbyText;
      if (el.sectionHeading) hints.sectionHeading = el.sectionHeading;
      if (el.formName) hints.formName = el.formName;

      return { id, type: "click", target: { primary, resolutionHints: hints } } satisfies ClickStep;
    }

    case "input":
    case "change": {
      const el = event.element;
      const primary =
        el.label ? { kind: "label" as const, label: el.label } :
        el.placeholder ? { kind: "placeholder" as const, placeholder: el.placeholder } :
        el.name ? { kind: "name" as const, name: el.name } :
        el.cssSelector ? { kind: "css" as const, selector: el.cssSelector } :
        null;

      if (!primary) return null;

      const value = event.masked
        ? { kind: "secret" as const, secretKey: el.name ?? el.label ?? "unknown" }
        : { kind: "literal" as const, value: event.value };

      return { id, type: "fill", target: { primary }, value } satisfies FillStep;
    }

    case "annotation":
      // Annotations don't become steps — they are attached to surrounding steps
      return null;

    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Merge heuristic result with model output (model fills gaps, doesn't overwrite)
// ---------------------------------------------------------------------------

function mergeModelResult(
  partial: Partial<Workflow>,
  modelResult: Partial<Workflow>
): Partial<Workflow> {
  const mergedContext: Workflow["context"] = {
    goal: partial.context?.goal || modelResult.context?.goal || "",
    ...partial.context,
  };
  if (!mergedContext.summary && modelResult.context?.summary) {
    mergedContext.summary = modelResult.context.summary;
  }
  if (!mergedContext.successCriteria && modelResult.context?.successCriteria) {
    mergedContext.successCriteria = modelResult.context.successCriteria;
  }

  const mergedSteps = partial.steps?.map((step, i) => {
    const modelStep = modelResult.steps?.[i];
    if (!modelStep || modelStep.type !== step.type) return step;
    const merged = { ...step };
    if (!merged.name && modelStep.name) merged.name = modelStep.name;
    if (merged.confidence === undefined && modelStep.confidence !== undefined) {
      merged.confidence = modelStep.confidence;
    }
    return merged;
  });

  return { ...partial, context: mergedContext, steps: mergedSteps ?? partial.steps };
}
