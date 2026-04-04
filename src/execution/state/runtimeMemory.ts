import type { ValueSpec } from "../../shared/types/workflow.js";

/**
 * Resolves a ValueSpec to a concrete value using runtime inputs and extracted memory.
 * Returns null if the value cannot be resolved (missing input, missing memory key).
 */
export function resolveValue(
  spec: ValueSpec,
  inputs: Record<string, string | number | boolean>,
  memory: Record<string, string | number | boolean>
): string | number | boolean | null {
  switch (spec.kind) {
    case "literal":
      return spec.value;
    case "input":
      return inputs[spec.inputName] ?? null;
    case "runtime_memory":
      return memory[spec.key] ?? null;
    case "secret":
      // Secret resolution is injected by the host environment — not handled here
      return null;
    case "derived":
      // Expression evaluation is intentionally deferred — not in MVP scope
      return null;
  }
}
