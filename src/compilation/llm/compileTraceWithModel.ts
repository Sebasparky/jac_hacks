import type { CleanedTrace } from "../../shared/types/trace.js";
import type { Workflow } from "../../shared/types/workflow.js";
import { buildCompilerPrompt } from "./buildCompilerPrompt.js";
import { parseCompilerOutput } from "./parseCompilerOutput.js";

export type ModelProvider = {
  /** Send a prompt and return the raw text response. */
  complete(prompt: string): Promise<string>;
};

export type CompileWithModelOptions = {
  goalContext?: string;
  userAnnotations?: string[];
  omitRawDom?: boolean;
};

/**
 * Calls the model to enrich a partially-compiled workflow.
 * Only called when heuristic inference is insufficient.
 * Model providers are injected — never imported directly here.
 */
export async function compileTraceWithModel(
  trace: CleanedTrace,
  model: ModelProvider,
  options: CompileWithModelOptions = {}
): Promise<Partial<Workflow>> {
  const prompt = buildCompilerPrompt(trace, options);
  const raw = await model.complete(prompt);
  return parseCompilerOutput(raw);
}
