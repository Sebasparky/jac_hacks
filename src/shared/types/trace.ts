// Observation owns facts, not meaning.
// Raw trace events record WHAT happened, WHERE, and WHEN — never WHY.
// Meaning is assigned by the compiler, not by the recorder.

// ---------------------------------------------------------------------------
// DOM context captured at the time of each event
// ---------------------------------------------------------------------------

export type DomElementContext = {
  tag: string;
  id?: string;
  name?: string;
  type?: string;
  role?: string;
  label?: string;
  placeholder?: string;
  testId?: string;
  innerText?: string;
  /** Closest visible text nodes near the element, for semantic targeting. */
  nearbyText?: string[];
  /** Heading text of the containing section. */
  sectionHeading?: string;
  /** Name attribute of the containing form. */
  formName?: string;
  /** CSS selector — stored only as last-resort fallback. */
  cssSelector?: string;
  /** XPath — stored only as last-resort fallback. */
  xpath?: string;
  boundingRect?: { x: number; y: number; width: number; height: number };
};

export type FrameContext = {
  frameId: string;
  src?: string;
  name?: string;
};

// ---------------------------------------------------------------------------
// Raw event types
// ---------------------------------------------------------------------------

export type RawEventType =
  | "click"
  | "input"
  | "change"
  | "focus"
  | "blur"
  | "keydown"
  | "submit"
  | "navigation"
  | "file_selected"
  | "annotation";

type BaseRawEvent = {
  id: string;
  sessionId: string;
  timestamp: string;
  type: RawEventType;
  url: string;
  frame?: FrameContext;
};

export type ClickEvent = BaseRawEvent & {
  type: "click";
  element: DomElementContext;
};

export type InputEvent = BaseRawEvent & {
  type: "input";
  element: DomElementContext;
  /** Masked if the field is detected as sensitive. */
  value: string;
  masked: boolean;
};

export type ChangeEvent = BaseRawEvent & {
  type: "change";
  element: DomElementContext;
  value: string;
  masked: boolean;
};

export type FocusEvent = BaseRawEvent & {
  type: "focus";
  element: DomElementContext;
};

export type BlurEvent = BaseRawEvent & {
  type: "blur";
  element: DomElementContext;
};

export type KeydownEvent = BaseRawEvent & {
  type: "keydown";
  key: string;
  /** Only captured for functional keys (Enter, Tab, Escape, …). */
  isFunctionalKey: boolean;
  element?: DomElementContext;
};

export type SubmitEvent = BaseRawEvent & {
  type: "submit";
  formElement: DomElementContext;
};

export type NavigationEvent = BaseRawEvent & {
  type: "navigation";
  previousUrl: string;
  trigger: "link_click" | "form_submit" | "back_forward" | "script" | "unknown";
};

export type FileSelectedEvent = BaseRawEvent & {
  type: "file_selected";
  element: DomElementContext;
  /** File name only — content is never stored in the trace. */
  fileName: string;
  mimeType?: string;
};

/** User-authored annotation attached at a point in the recording. */
export type AnnotationEvent = BaseRawEvent & {
  type: "annotation";
  annotationType:
    | "step_intent"
    | "parameter_hint"
    | "repair_hint"
    | "safety_note"
    | "general";
  text: string;
  /** If provided, the annotation is associated with this specific event. */
  refersToEventId?: string;
};

export type RawEvent =
  | ClickEvent
  | InputEvent
  | ChangeEvent
  | FocusEvent
  | BlurEvent
  | KeydownEvent
  | SubmitEvent
  | NavigationEvent
  | FileSelectedEvent
  | AnnotationEvent;

// ---------------------------------------------------------------------------
// Recording session
// ---------------------------------------------------------------------------

export type RecordingSessionStatus =
  | "recording"
  | "paused"
  | "stopped"
  | "exported";

export type RecordingSession = {
  id: string;
  startedAt: string;
  stoppedAt?: string;
  status: RecordingSessionStatus;
  startUrl: string;
  domains: string[];
  /** User-provided description of the overall goal before or during recording. */
  goalContext?: string;
  events: RawEvent[];
};

// ---------------------------------------------------------------------------
// Cleaned trace (output of the cleaner pipeline)
// ---------------------------------------------------------------------------

/** A cleaned trace still contains raw event references but noise has been removed. */
export type CleanedTrace = {
  sessionId: string;
  cleanedAt: string;
  /** IDs of events removed during cleaning, with reasons. */
  removedEventIds: Array<{ id: string; reason: string }>;
  events: RawEvent[];
};
