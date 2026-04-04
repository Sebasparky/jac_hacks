import type { RawEvent, RecordingSession } from "../../shared/types/trace.js";
import { newSessionId, newEventId } from "../../shared/utils/ids.js";
import { now } from "../../shared/utils/timestamps.js";

export type RecorderConfig = {
  startUrl: string;
  goalContext?: string;
  /** Field name substrings whose values should be masked before storing. */
  sensitiveFieldPatterns?: string[];
};

/** Minimal interface every recorder module must satisfy. */
export interface IEventRecorder {
  start(config: RecorderConfig): RecordingSession;
  addEvent(session: RecordingSession, event: Omit<RawEvent, "id" | "sessionId" | "timestamp">): RawEvent;
  stop(session: RecordingSession): RecordingSession;
}

/** Base recorder — concrete recorders extend or compose this. */
export class EventRecorder implements IEventRecorder {
  start(config: RecorderConfig): RecordingSession {
    const session: RecordingSession = {
      id: newSessionId(),
      startedAt: now(),
      status: "recording",
      startUrl: config.startUrl,
      domains: [new URL(config.startUrl).hostname],
      events: [],
    };
    if (config.goalContext) session.goalContext = config.goalContext;
    return session;
  }

  addEvent(
    session: RecordingSession,
    partial: Omit<RawEvent, "id" | "sessionId" | "timestamp">
  ): RawEvent {
    const event = {
      ...partial,
      id: newEventId(),
      sessionId: session.id,
      timestamp: now(),
    } as RawEvent;

    session.events.push(event);
    return event;
  }

  stop(session: RecordingSession): RecordingSession {
    return { ...session, stoppedAt: now(), status: "stopped" };
  }
}
