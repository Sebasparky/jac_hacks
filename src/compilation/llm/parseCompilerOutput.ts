import type { Workflow } from "../../shared/types/workflow.js";

/**
 * Extracts and parses a JSON object from raw model output.
 * The model may wrap JSON in markdown code fences — strip them first.
 */
export function parseCompilerOutput(raw: string): Partial<Workflow> {
  const trimmed = raw.trim();

  // Strip ```json ... ``` or ``` ... ```
  const fenceMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)```\s*$/);
  const json = fenceMatch ? fenceMatch[1]!.trim() : trimmed;

  try {
    return JSON.parse(json) as Partial<Workflow>;
  } catch {
    throw new Error(`CompilerOutputParseError: model returned non-JSON output.\n${raw.slice(0, 300)}`);
  }
}
