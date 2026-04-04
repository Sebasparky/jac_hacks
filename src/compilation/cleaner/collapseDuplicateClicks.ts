import type { RawEvent, ClickEvent } from "../../shared/types/trace.js";

/**
 * Removes double-click duplicates: if two click events target the same element
 * within 300ms, keep only the first.
 */
export function collapseDuplicateClicks(events: RawEvent[]): RawEvent[] {
  const result: RawEvent[] = [];

  for (const event of events) {
    if (event.type !== "click") {
      result.push(event);
      continue;
    }

    const click = event as ClickEvent;
    const prev = result.findLast((e): e is ClickEvent => e.type === "click");

    if (
      prev &&
      isSameTarget(prev, click) &&
      Date.parse(click.timestamp) - Date.parse(prev.timestamp) < 300
    ) {
      // Duplicate — skip
      continue;
    }

    result.push(click);
  }

  return result;
}

function isSameTarget(a: ClickEvent, b: ClickEvent): boolean {
  return (
    (!!a.element.id && a.element.id === b.element.id) ||
    (!!a.element.cssSelector && a.element.cssSelector === b.element.cssSelector)
  );
}
