import { describe, it, expect } from "vitest";
import { mergeTypingEvents } from "../../compilation/cleaner/mergeTypingEvents.js";
import { collapseDuplicateClicks } from "../../compilation/cleaner/collapseDuplicateClicks.js";
import { removeNoise } from "../../compilation/cleaner/removeNoise.js";
import type { RawEvent, InputEvent, ClickEvent } from "../../shared/types/trace.js";

// ---------------------------------------------------------------------------
// Helpers to build minimal events
// ---------------------------------------------------------------------------

const BASE_FIELDS = {
  sessionId: "sess_1",
  url: "https://example.com",
};

let seq = 0;
function nextId(): string {
  return `evt_${++seq}`;
}

function makeInput(
  elementName: string,
  value: string,
  ts: number,
  overrides: Partial<InputEvent["element"]> = {}
): InputEvent {
  return {
    ...BASE_FIELDS,
    id: nextId(),
    timestamp: new Date(ts).toISOString(),
    type: "input",
    element: { tag: "input", name: elementName, ...overrides },
    value,
    masked: false,
  };
}

function makeClick(elementId: string, ts: number): ClickEvent {
  return {
    ...BASE_FIELDS,
    id: nextId(),
    timestamp: new Date(ts).toISOString(),
    type: "click",
    element: { tag: "button", id: elementId },
  };
}

function makeNavigation(url: string, ts: number): RawEvent {
  return {
    ...BASE_FIELDS,
    id: nextId(),
    timestamp: new Date(ts).toISOString(),
    type: "navigation",
    url,
    previousUrl: "https://example.com",
    trigger: "link_click",
  };
}

function makeFocus(elementId: string, ts: number): RawEvent {
  return {
    ...BASE_FIELDS,
    id: nextId(),
    timestamp: new Date(ts).toISOString(),
    type: "focus",
    element: { tag: "input", id: elementId },
  };
}

function makeBlur(elementId: string, ts: number): RawEvent {
  return {
    ...BASE_FIELDS,
    id: nextId(),
    timestamp: new Date(ts).toISOString(),
    type: "blur",
    element: { tag: "input", id: elementId },
  };
}

// ---------------------------------------------------------------------------
// mergeTypingEvents
// ---------------------------------------------------------------------------

const T0 = 1_000_000_000_000;

describe("mergeTypingEvents", () => {
  it("collapses consecutive input events on the same element to the last value", () => {
    const events: RawEvent[] = [
      makeInput("email", "a", T0),
      makeInput("email", "ab", T0 + 100),
      makeInput("email", "abc", T0 + 200),
    ];
    const result = mergeTypingEvents(events);
    expect(result).toHaveLength(1);
    expect((result[0] as InputEvent).value).toBe("abc");
  });

  it("keeps separate runs on different elements", () => {
    const events: RawEvent[] = [
      makeInput("first_name", "Jo", T0),
      makeInput("last_name", "Sm", T0 + 100),
      makeInput("last_name", "Smith", T0 + 200),
    ];
    const result = mergeTypingEvents(events);
    expect(result).toHaveLength(2);
    expect((result[0] as InputEvent).value).toBe("Jo");
    expect((result[1] as InputEvent).value).toBe("Smith");
  });

  it("does not merge runs separated by a non-input event", () => {
    const click = makeClick("btn", T0 + 150);
    const events: RawEvent[] = [
      makeInput("email", "a", T0),
      click,
      makeInput("email", "b", T0 + 300),
    ];
    const result = mergeTypingEvents(events);
    expect(result).toHaveLength(3);
  });

  it("passes through non-input events unchanged", () => {
    const nav = makeNavigation("https://example.com/page2", T0);
    const result = mergeTypingEvents([nav]);
    expect(result).toHaveLength(1);
    expect(result[0]!.type).toBe("navigation");
  });

  it("handles an empty array", () => {
    expect(mergeTypingEvents([])).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// collapseDuplicateClicks
// ---------------------------------------------------------------------------

describe("collapseDuplicateClicks", () => {
  it("drops a second click on the same element within 300ms", () => {
    const events: RawEvent[] = [
      makeClick("btn-submit", T0),
      makeClick("btn-submit", T0 + 200),
    ];
    const result = collapseDuplicateClicks(events);
    expect(result).toHaveLength(1);
    expect((result[0] as ClickEvent).element.id).toBe("btn-submit");
  });

  it("keeps both clicks on the same element if they are more than 300ms apart", () => {
    const events: RawEvent[] = [
      makeClick("btn-submit", T0),
      makeClick("btn-submit", T0 + 400),
    ];
    expect(collapseDuplicateClicks(events)).toHaveLength(2);
  });

  it("keeps clicks on different elements even within 300ms", () => {
    const events: RawEvent[] = [
      makeClick("btn-a", T0),
      makeClick("btn-b", T0 + 50),
    ];
    expect(collapseDuplicateClicks(events)).toHaveLength(2);
  });

  it("collapses clicks on the same element within 300ms even with intervening non-click events", () => {
    // Implementation uses findLast across all clicks, not just adjacent ones.
    // A nav event between two same-target clicks within 300ms does NOT reset the window.
    const nav = makeNavigation("https://example.com/2", T0 + 100);
    const events: RawEvent[] = [
      makeClick("btn-submit", T0),
      nav,
      makeClick("btn-submit", T0 + 200),
    ];
    const result = collapseDuplicateClicks(events);
    // nav is kept, second click is suppressed (same element, <300ms from last click)
    expect(result).toHaveLength(2);
    expect(result.some((e) => e.type === "navigation")).toBe(true);
    expect(result.filter((e) => e.type === "click")).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// removeNoise
// ---------------------------------------------------------------------------

describe("removeNoise", () => {
  it("removes focus events whose element has no corresponding input", () => {
    const focus = makeFocus("orphan-field", T0);
    const { events, removed } = removeNoise([focus]);
    expect(events).toHaveLength(0);
    expect(removed[0]!.id).toBe(focus.id);
  });

  it("keeps focus events on elements that also received input", () => {
    const input = makeInput("username", "alice", T0, { id: "username-field" });
    const focus = makeFocus("username-field", T0 - 100);
    const { events, removed } = removeNoise([focus, input]);
    expect(events.some((e) => e.id === focus.id)).toBe(true);
    expect(removed.some((r) => r.id === focus.id)).toBe(false);
  });

  it("removes blur events whose element has no corresponding input", () => {
    const blur = makeBlur("orphan-field", T0);
    const { events } = removeNoise([blur]);
    expect(events).toHaveLength(0);
  });

  it("drops duplicate navigations to the same URL within 500ms", () => {
    const nav1 = makeNavigation("https://example.com/page", T0);
    const nav2 = makeNavigation("https://example.com/page", T0 + 300);
    const { events, removed } = removeNoise([nav1, nav2]);
    expect(events).toHaveLength(1);
    expect(removed[0]!.id).toBe(nav2.id);
  });

  it("keeps navigations to the same URL if they are more than 500ms apart", () => {
    const nav1 = makeNavigation("https://example.com/page", T0);
    const nav2 = makeNavigation("https://example.com/page", T0 + 600);
    expect(removeNoise([nav1, nav2]).events).toHaveLength(2);
  });

  it("keeps navigations to different URLs regardless of timing", () => {
    const nav1 = makeNavigation("https://example.com/a", T0);
    const nav2 = makeNavigation("https://example.com/b", T0 + 100);
    expect(removeNoise([nav1, nav2]).events).toHaveLength(2);
  });
});
