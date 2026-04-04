import type { RawEvent, InputEvent } from "../../shared/types/trace.js";

/**
 * Collapses consecutive input events on the same element into a single event
 * that carries the final value. This prevents one fill step per keystroke.
 */
export function mergeTypingEvents(events: RawEvent[]): RawEvent[] {
  const result: RawEvent[] = [];

  for (let i = 0; i < events.length; i++) {
    const event = events[i];
    if (!event) continue;

    if (event.type !== "input") {
      result.push(event);
      continue;
    }

    // Look ahead: collect all consecutive input events on the same element
    const group: InputEvent[] = [event as InputEvent];
    while (
      i + 1 < events.length &&
      events[i + 1]?.type === "input" &&
      isSameElement(event as InputEvent, events[i + 1] as InputEvent)
    ) {
      i++;
      group.push(events[i] as InputEvent);
    }

    // Keep the last event in the group (final value)
    const last = group[group.length - 1]!;
    result.push(last);
  }

  return result;
}

function isSameElement(a: InputEvent, b: InputEvent): boolean {
  return (
    (a.element.id && a.element.id === b.element.id) ||
    (a.element.name && a.element.name === b.element.name) ||
    (a.element.cssSelector !== undefined && a.element.cssSelector === b.element.cssSelector)
  );
}
