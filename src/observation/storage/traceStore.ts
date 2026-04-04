import type { RecordingSession, CleanedTrace } from "../../shared/types/trace.js";

/**
 * Persistence interface for recording sessions and cleaned traces.
 * Implementations may write to disk, IndexedDB, or an in-process store.
 */
export interface ITraceStore {
  saveSession(session: RecordingSession): Promise<void>;
  loadSession(id: string): Promise<RecordingSession | null>;
  listSessions(): Promise<Array<{ id: string; startedAt: string; status: RecordingSession["status"] }>>;
  deleteSession(id: string): Promise<void>;

  saveCleanedTrace(trace: CleanedTrace): Promise<void>;
  loadCleanedTrace(sessionId: string): Promise<CleanedTrace | null>;
}

/** In-memory store for development and testing. */
export class MemoryTraceStore implements ITraceStore {
  private sessions = new Map<string, RecordingSession>();
  private cleanedTraces = new Map<string, CleanedTrace>();

  async saveSession(session: RecordingSession): Promise<void> {
    this.sessions.set(session.id, session);
  }

  async loadSession(id: string): Promise<RecordingSession | null> {
    return this.sessions.get(id) ?? null;
  }

  async listSessions() {
    return [...this.sessions.values()].map((s) => ({
      id: s.id,
      startedAt: s.startedAt,
      status: s.status,
    }));
  }

  async deleteSession(id: string): Promise<void> {
    this.sessions.delete(id);
  }

  async saveCleanedTrace(trace: CleanedTrace): Promise<void> {
    this.cleanedTraces.set(trace.sessionId, trace);
  }

  async loadCleanedTrace(sessionId: string): Promise<CleanedTrace | null> {
    return this.cleanedTraces.get(sessionId) ?? null;
  }
}
