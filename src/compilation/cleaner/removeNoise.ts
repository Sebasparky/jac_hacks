import type { RawEvent } from "../../shared/types/trace.js";

export type RemovedEvent = { id: string; reason: string };

export type CleanResult = {
  events: RawEvent[];
  removed: RemovedEvent[];
};

/**
 * Removes events that carry no workflow-level meaning:
 * - focus/blur without accompanying input
 * - duplicate navigations to the same URL within 500ms
 */
export function removeNoise(events: RawEvent[]): CleanResult {
  const removed: RemovedEvent[] = [];
  const kept: RawEvent[] = [];

  const inputtedElementIds = new Set<string>(
    events
      .filter((e) => e.type === "input" || e.type === "change")
      .map((e) => {
        const el = (e as { element?: { id?: string } }).element;
        return el?.id ?? "";
      })
      .filter(Boolean)
  );

  for (let i = 0; i < events.length; i++) {
    const event = events[i]!;

    // Drop focus/blur that have no corresponding input
    if (event.type === "focus" || event.type === "blur") {
      const el = (event as { element?: { id?: string } }).element;
      if (el?.id && !inputtedElementIds.has(el.id)) {
        removed.push({ id: event.id, reason: `${event.type} with no input on element ${el.id}` });
        continue;
      }
    }

    // Drop duplicate navigation within 500ms
    if (event.type === "navigation") {
      const prev = kept.findLast((e) => e.type === "navigation");
      if (
        prev?.type === "navigation" &&
        prev.url === event.url &&
        Date.parse(event.timestamp) - Date.parse(prev.timestamp) < 500
      ) {
        removed.push({ id: event.id, reason: "duplicate navigation within 500ms" });
        continue;
      }
    }

    kept.push(event);
  }

  return { events: kept, removed };
}
