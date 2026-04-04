import type { Workflow } from "../types/workflow.js";

/** Reference example showing what a compiled workflow looks like end-to-end. */
export const expenseWorkflow: Workflow = {
  version: "1.0",
  id: "wf_expense_submit_001",
  name: "Submit expense report",
  description: "Creates and submits a new expense report from runtime inputs",

  metadata: {
    createdAt: "2026-04-04T12:00:00Z",
    updatedAt: "2026-04-04T12:00:00Z",
    createdByUserId: "user_123",
    source: {
      recordingSessionId: "rec_001",
      origin: "browser-recording",
      startUrl: "https://portal.example.com/expenses",
      domains: ["portal.example.com"],
    },
  },

  context: {
    goal: "Create and submit a new expense report",
    constraints: [
      "Only run on the expense portal",
      "Require approval if amount exceeds 100",
    ],
    successCriteria: [
      "A success message appears",
      "The URL includes /submitted",
    ],
  },

  inputs: [
    { name: "amount", label: "Amount", type: "number", required: true },
    { name: "vendor", label: "Vendor", type: "string", required: true },
    { name: "date", label: "Date", type: "date", required: true },
  ],

  steps: [
    {
      id: "step_1",
      type: "goto",
      url: "https://portal.example.com/expenses",
    },
    {
      id: "step_2",
      type: "click",
      target: {
        primary: { kind: "text", text: "New Report", role: "button" },
      },
    },
    {
      id: "step_3",
      type: "fill",
      target: { primary: { kind: "label", label: "Amount" } },
      value: { kind: "input", inputName: "amount" },
      annotations: [
        {
          id: "ann_1",
          type: "parameter_hint",
          text: "This value changes every run",
          createdAt: "2026-04-04T12:00:00Z",
        },
      ],
    },
    {
      id: "step_4",
      type: "fill",
      target: { primary: { kind: "label", label: "Vendor" } },
      value: { kind: "input", inputName: "vendor" },
    },
    {
      id: "step_5",
      type: "fill",
      target: { primary: { kind: "label", label: "Date" } },
      value: { kind: "input", inputName: "date" },
    },
    {
      id: "step_6",
      type: "click",
      target: {
        primary: { kind: "text", text: "Submit", role: "button" },
        fallbacks: [
          { kind: "text", text: "Create", role: "button" },
          { kind: "css", selector: "button[type='submit']" },
        ],
      },
      requiresApproval: true,
      annotations: [
        {
          id: "ann_2",
          type: "safety_rule",
          text: "Ask before final submission",
          createdAt: "2026-04-04T12:00:00Z",
        },
      ],
      postconditions: [
        { signal: { kind: "text_present", text: "Report submitted" } },
      ],
    },
    {
      id: "step_7",
      type: "assert",
      signal: { kind: "url_includes", value: "/submitted" },
    },
  ],

  safety: {
    allowedDomains: ["portal.example.com"],
    requireApprovalFor: ["final_submit"],
    customRules: [
      {
        id: "safe_1",
        description: "Require approval for large amounts",
        condition: { kind: "input_greater_than", inputName: "amount", value: 100 },
        action: "require_approval",
      },
    ],
  },

  privacy: {
    mode: "hybrid",
    sensitiveInputs: [],
    llmUsage: {
      allowDuringCompile: true,
      allowDuringRepair: true,
      allowRawDomInRepair: false,
    },
  },

  compileInfo: {
    compilerVersion: "0.1.0",
    compiledAt: "2026-04-04T12:00:00Z",
    sourceTraceId: "trace_001",
  },
};
