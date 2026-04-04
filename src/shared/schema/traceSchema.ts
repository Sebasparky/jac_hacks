import { z } from "zod";

const DomElementContextSchema = z.object({
  tag: z.string(),
  id: z.string().optional(),
  name: z.string().optional(),
  type: z.string().optional(),
  role: z.string().optional(),
  label: z.string().optional(),
  placeholder: z.string().optional(),
  testId: z.string().optional(),
  innerText: z.string().optional(),
  nearbyText: z.array(z.string()).optional(),
  sectionHeading: z.string().optional(),
  formName: z.string().optional(),
  cssSelector: z.string().optional(),
  xpath: z.string().optional(),
  boundingRect: z.object({ x: z.number(), y: z.number(), width: z.number(), height: z.number() }).optional(),
});

const FrameContextSchema = z.object({
  frameId: z.string(),
  src: z.string().optional(),
  name: z.string().optional(),
});

const BaseRawEventFields = {
  id: z.string(),
  sessionId: z.string(),
  timestamp: z.string().datetime(),
  url: z.string(),
  frame: FrameContextSchema.optional(),
};

export const RawEventSchema = z.discriminatedUnion("type", [
  z.object({ ...BaseRawEventFields, type: z.literal("click"), element: DomElementContextSchema }),
  z.object({ ...BaseRawEventFields, type: z.literal("input"), element: DomElementContextSchema, value: z.string(), masked: z.boolean() }),
  z.object({ ...BaseRawEventFields, type: z.literal("change"), element: DomElementContextSchema, value: z.string(), masked: z.boolean() }),
  z.object({ ...BaseRawEventFields, type: z.literal("focus"), element: DomElementContextSchema }),
  z.object({ ...BaseRawEventFields, type: z.literal("blur"), element: DomElementContextSchema }),
  z.object({ ...BaseRawEventFields, type: z.literal("keydown"), key: z.string(), isFunctionalKey: z.boolean(), element: DomElementContextSchema.optional() }),
  z.object({ ...BaseRawEventFields, type: z.literal("submit"), formElement: DomElementContextSchema }),
  z.object({ ...BaseRawEventFields, type: z.literal("navigation"), previousUrl: z.string(), trigger: z.enum(["link_click", "form_submit", "back_forward", "script", "unknown"]) }),
  z.object({ ...BaseRawEventFields, type: z.literal("file_selected"), element: DomElementContextSchema, fileName: z.string(), mimeType: z.string().optional() }),
  z.object({ ...BaseRawEventFields, type: z.literal("annotation"), annotationType: z.enum(["step_intent", "parameter_hint", "repair_hint", "safety_note", "general"]), text: z.string().min(1), refersToEventId: z.string().optional() }),
]);

export const RecordingSessionSchema = z.object({
  id: z.string(),
  startedAt: z.string().datetime(),
  stoppedAt: z.string().datetime().optional(),
  status: z.enum(["recording", "paused", "stopped", "exported"]),
  startUrl: z.string(),
  domains: z.array(z.string()),
  goalContext: z.string().optional(),
  events: z.array(RawEventSchema),
});

export const CleanedTraceSchema = z.object({
  sessionId: z.string(),
  cleanedAt: z.string().datetime(),
  removedEventIds: z.array(z.object({ id: z.string(), reason: z.string() })),
  events: z.array(RawEventSchema),
});
