// Privacy policy determines where LLM calls may occur and which data may leave the device.
// mode drives routing at compile and repair time — not just documentation.

export type PrivacyMode = "cloud" | "local" | "hybrid";

export type WorkflowPrivacyPolicy = {
  /**
   * cloud  — all LLM calls go to a cloud provider.
   * local  — all LLM calls must use a local model; no data leaves the device.
   * hybrid — compile may use cloud; repair uses local for sensitive workflows.
   */
  mode: PrivacyMode;

  /** Input names whose values must never be sent to an LLM or persisted in plain text. */
  sensitiveInputs?: string[];

  /** Field name substrings whose values should be masked during recording. */
  maskRecordingFields?: string[];

  /** Selectors containing these strings must not be stored in the trace. */
  neverPersistSelectorsContainingText?: string[];

  llmUsage: {
    /** Whether the LLM may be called during workflow compilation. */
    allowDuringCompile: boolean;
    /** Whether the LLM may be called during step repair. */
    allowDuringRepair: boolean;
    /** Whether raw DOM snapshots may be sent to the LLM during repair. */
    allowRawDomInRepair: boolean;
  };
};
