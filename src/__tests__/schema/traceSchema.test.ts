import { describe, it, expect } from "vitest";
import { RawEventSchema, RecordingSessionSchema, CleanedTraceSchema } from "../../shared/schema/traceSchema.js";

// ---------------------------------------------------------------------------
// Minimal valid event fixtures
// ---------------------------------------------------------------------------

const BASE = {
  id: "evt_1",
  sessionId: "sess_1",
  timestamp: "2026-04-04T12:00:00Z",
  url: "https://example.com",
};

const validClickEvent = {
  ...BASE,
  type: "click" as const,
  element: { tag: "button", innerText: "Submit" },
};

const validInputEvent = {
  ...BASE,
  id: "evt_2",
  type: "input" as const,
  element: { tag: "input", name: "email" },
  value: "user@example.com",
  masked: false,
};

const validNavigationEvent = {
  ...BASE,
  id: "evt_3",
  type: "navigation" as const,
  previousUrl: "https://example.com/start",
  trigger: "link_click" as const,
};

const validAnnotationEvent = {
  ...BASE,
  id: "evt_4",
  type: "annotation" as const,
  annotationType: "step_intent" as const,
  text: "Clicking the submit button",
};

const validSession = {
  id: "sess_1",
  startedAt: "2026-04-04T12:00:00Z",
  status: "stopped" as const,
  startUrl: "https://example.com",
  domains: ["example.com"],
  events: [validClickEvent, validNavigationEvent],
};

// ---------------------------------------------------------------------------
// RawEvent validation
// ---------------------------------------------------------------------------

describe("RawEventSchema — valid events", () => {
  it("parses a click event", () => {
    expect(RawEventSchema.safeParse(validClickEvent).success).toBe(true);
  });

  it("parses an input event", () => {
    expect(RawEventSchema.safeParse(validInputEvent).success).toBe(true);
  });

  it("parses a navigation event", () => {
    expect(RawEventSchema.safeParse(validNavigationEvent).success).toBe(true);
  });

  it("parses an annotation event", () => {
    expect(RawEventSchema.safeParse(validAnnotationEvent).success).toBe(true);
  });

  it("parses a keydown event with optional element omitted", () => {
    const event = {
      ...BASE,
      id: "evt_5",
      type: "keydown" as const,
      key: "Enter",
      isFunctionalKey: true,
    };
    expect(RawEventSchema.safeParse(event).success).toBe(true);
  });
});

describe("RawEventSchema — malformed events", () => {
  it("rejects a click event missing the element field", () => {
    const bad = { ...BASE, type: "click" };
    expect(RawEventSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects an input event missing the value field", () => {
    const bad = { ...validInputEvent, value: undefined };
    expect(RawEventSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects a navigation event with an invalid trigger enum", () => {
    const bad = { ...validNavigationEvent, trigger: "drag" };
    expect(RawEventSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects an annotation event with an empty text field", () => {
    const bad = { ...validAnnotationEvent, text: "" };
    expect(RawEventSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects an event with an unknown type", () => {
    const bad = { ...BASE, type: "mousemove" };
    expect(RawEventSchema.safeParse(bad).success).toBe(false);
  });

  it("rejects an event with a malformed timestamp", () => {
    const bad = { ...validClickEvent, timestamp: "April 4th 2026" };
    expect(RawEventSchema.safeParse(bad).success).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// RecordingSession validation
// ---------------------------------------------------------------------------

describe("RecordingSessionSchema", () => {
  it("parses a valid session", () => {
    expect(RecordingSessionSchema.safeParse(validSession).success).toBe(true);
  });

  it("accepts a session with an empty events array", () => {
    expect(RecordingSessionSchema.safeParse({ ...validSession, events: [] }).success).toBe(true);
  });

  it("rejects a session with an invalid status", () => {
    const bad = { ...validSession, status: "idle" };
    expect(RecordingSessionSchema.safeParse(bad).success).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// CleanedTrace validation
// ---------------------------------------------------------------------------

describe("CleanedTraceSchema", () => {
  it("parses a valid cleaned trace", () => {
    const trace = {
      sessionId: "sess_1",
      cleanedAt: "2026-04-04T12:05:00Z",
      removedEventIds: [{ id: "evt_noise", reason: "focus with no input" }],
      events: [validClickEvent],
    };
    expect(CleanedTraceSchema.safeParse(trace).success).toBe(true);
  });

  it("rejects a cleaned trace with a malformed cleanedAt date", () => {
    const bad = {
      sessionId: "sess_1",
      cleanedAt: "not-a-date",
      removedEventIds: [],
      events: [],
    };
    expect(CleanedTraceSchema.safeParse(bad).success).toBe(false);
  });
});
