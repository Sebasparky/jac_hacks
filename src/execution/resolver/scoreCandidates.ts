import type { TargetSpec } from "../../shared/types/workflow.js";
import type { ElementHandle } from "../runner/workflowRunner.js";

export type ScoredCandidate = { element: ElementHandle; score: number };

/**
 * Scores a list of candidate elements against the resolution hints in a TargetSpec.
 * Used when a locator matches multiple elements and we need to pick the best one.
 */
export async function scoreCandidates(
  candidates: ElementHandle[],
  spec: TargetSpec
): Promise<ScoredCandidate[]> {
  const hints = spec.resolutionHints;
  const scored: ScoredCandidate[] = [];

  for (const element of candidates) {
    let score = 0;

    if (hints?.expectedTag) {
      // Implementations check element.getAttribute("tagName") or similar
      score += 0; // placeholder — driver-specific
    }

    if (hints?.nearbyText?.length) {
      const text = await element.innerText();
      const matches = hints.nearbyText.filter((t) => text.includes(t)).length;
      score += matches * 2;
    }

    scored.push({ element, score });
  }

  return scored.sort((a, b) => b.score - a.score);
}
