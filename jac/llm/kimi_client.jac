"""
Jac-native Kimi compile-time enrichment client.

Purpose:
- Resolve Kimi configuration from `.env` and process environment.
- Call the Kimi chat completions API in JSON mode.
- Return a small enrichment object that the compilation layer can merge safely.
"""

import os;
import json;
import from typing { Any }
import from urllib.request { Request, urlopen }
import from urllib.error { HTTPError, URLError }

glob DEFAULT_KIMI_BASE_URL: str = "https://api.moonshot.ai/v1";
glob DEFAULT_KIMI_MODEL: str = "kimi-k2.5";

"""R: Parse one local `.env` file into a small key/value map.
M: Reads non-comment `KEY=VALUE` lines and trims optional wrapping quotes.
E: Missing files and malformed lines are ignored so runtime config stays fail-soft.
"""
def parse_dotenv(path: str = ".env") -> dict[str, str] {
    values: dict[str, str] = {};
    if not os.path.exists(path) {
        return values;
    }

    try {
        with open(path, "r") as file {
            for raw_line in file {
                line: str = str(raw_line).strip();
                if not line or line.startswith("#") or "=" not in line {
                    continue;
                }

                split_at: int = line.find("=");
                key: str = str(line[:split_at]).strip();
                value: str = str(line[split_at + 1:]).strip();
                if not key {
                    continue;
                }

                if len(value) >= 2 {
                    if (value.startswith("\"") and value.endswith("\"")) or
                       (value.startswith("'") and value.endswith("'")) {
                        value = value[1:-1];
                    }
                }
                values[key] = value;
            }
        }
    } except OSError {
        return {};
    }

    return values;
}

"""R: Read one config value from process env first, then `.env`, then fallback.
M: Checks `os.environ`, falls back to parsed dotenv values, and trims whitespace.
E: Empty values collapse to the provided fallback.
"""
def env_value(name: str, dotenv: dict[str, str], fallback: str = "") -> str {
    process_value: str = str(os.environ.get(name, "") or "").strip();
    if process_value {
        return process_value;
    }

    file_value: str = str(dotenv.get(name, "") or "").strip();
    if file_value {
        return file_value;
    }

    return fallback;
}

"""R: Detect placeholder secrets so the compiler does not attempt fake API calls.
M: Rejects empty values and common sample-token markers like `your-...` and `replace-me`.
E: Conservative heuristic may classify custom sample values as placeholders.
"""
def is_placeholder_secret(raw_value: str) -> bool {
    value: str = str(raw_value or "").strip();
    if not value {
        return True;
    }

    lowered: str = value.lower();
    if lowered.startswith("your-") or lowered.startswith("sk-your-") {
        return True;
    }
    if "replace" in lowered or "placeholder" in lowered or "api-key" in lowered {
        return True;
    }

    return False;
}

"""R: Convert loose env strings into booleans.
M: Accepts common truthy tokens used in `.env` files.
E: Unknown values resolve to false.
"""
def env_bool(raw_value: str) -> bool {
    lowered: str = str(raw_value or "").strip().lower();
    return lowered in ["1", "true", "yes", "on", "enabled"];
}

"""R: Build the effective Kimi compile configuration from local settings.
M: Supports provider-agnostic env names plus Moonshot-specific aliases.
E: Returns `enabled: false` when provider intent or usable credentials are missing.
"""
def resolve_kimi_compile_config() -> dict[str, Any] {
    dotenv: dict[str, str] = parse_dotenv();

    provider: str = env_value("LLM_PROVIDER", dotenv, "").lower();
    model: str = env_value(
        "LLM_MODEL",
        dotenv,
        env_value("MOONSHOT_MODEL", dotenv, env_value("MODEL", dotenv, DEFAULT_KIMI_MODEL))
    );
    base_url: str = env_value(
        "LLM_BASE_URL",
        dotenv,
        env_value("MOONSHOT_BASE_URL", dotenv, DEFAULT_KIMI_BASE_URL)
    ).rstrip("/");
    api_key: str = env_value(
        "LLM_API_KEY",
        dotenv,
        env_value("MOONSHOT_API_KEY", dotenv, "")
    );
    thinking_mode: str = env_value("KIMI_THINKING", dotenv, "disabled").lower();
    allow_compile_raw: str = env_value("LLM_ALLOW_COMPILE", dotenv, "true");

    provider_requested: bool = provider in ["kimi", "moonshot"];
    model_requested: bool = str(model or "").lower().startswith("kimi-");
    api_key_ready: bool = not is_placeholder_secret(api_key);
    enabled: bool = (provider_requested or model_requested) and api_key_ready and env_bool(allow_compile_raw);

    return {
        "enabled": enabled,
        "provider": "kimi",
        "model": model if model else DEFAULT_KIMI_MODEL,
        "base_url": base_url if base_url else DEFAULT_KIMI_BASE_URL,
        "api_key": api_key if api_key_ready else "",
        "thinking_mode": thinking_mode if thinking_mode in ["enabled", "disabled"] else "disabled",
        "allow_compile": env_bool(allow_compile_raw)
    };
}

"""R: Build a compact event summary suitable for model-side workflow enrichment.
M: Keeps only event type, URL, labels, and masked values from the first few cleaned events.
E: Non-dict events are skipped; long values stay bounded by upstream normalization.
"""
def compact_event_summary(cleaned: dict[str, Any], limit: int = 10) -> list[Any] {
    items: list[Any] = [];
    events: Any = cleaned.get("events", []);
    if not isinstance(events, list) {
        return items;
    }

    count: int = 0;
    for event in events {
        if count >= limit or not isinstance(event, dict) {
            continue;
        }

        element: Any = event.get("element", {});
        target_label: str = "";
        if isinstance(element, dict) {
            target_label = str(
                element.get("label", "") or
                element.get("name", "") or
                element.get("placeholder", "") or
                element.get("innerText", "")
            );
        }

        items.append({
            "type": str(event.get("type", "")),
            "url": str(event.get("url", "")),
            "label": target_label,
            "value": "__redacted__" if bool(event.get("masked", False)) else str(event.get("value", ""))
        });
        count += 1;
    }

    return items;
}

"""R: Extract the highest-value semantic clues from raw observation events.
M: Scans recent events for `semantic` payloads and returns the newest non-empty fields.
E: Missing semantic telemetry yields an empty dict.
"""
def latest_semantic_summary(raw_session: dict[str, Any]) -> dict[str, Any] {
    summary: dict[str, Any] = {};
    events: Any = raw_session.get("events", []);
    if not isinstance(events, list) {
        return summary;
    }

    for raw_event in events {
        if not isinstance(raw_event, dict) {
            continue;
        }
        semantic: Any = raw_event.get("semantic", {});
        if not isinstance(semantic, dict) or not semantic {
            continue;
        }

        summary = {
            "title": str(semantic.get("title", "")),
            "page_kind": str(semantic.get("page_kind", "")),
            "workflow_stage": str(semantic.get("workflow_stage", "")),
            "primary_actions": semantic.get("primary_actions", []) if isinstance(semantic.get("primary_actions", []), list) else [],
            "headings": semantic.get("headings", []) if isinstance(semantic.get("headings", []), list) else []
        };
    }

    return summary;
}

"""R: Build the JSON-mode prompt payload sent to Kimi for compile enrichment.
M: Provides the heuristic workflow plus light trace context and a strict output contract.
E: Keeps payload intentionally compact to reduce cost and latency.
"""
def build_kimi_compile_request(
    raw_session: dict[str, Any],
    normalized_session: dict[str, Any],
    cleaned: dict[str, Any],
    partial: dict[str, Any],
    config: dict[str, Any]
) -> dict[str, Any] {
    system_prompt: str = """
You are enriching a heuristic browser workflow compilation for Jac Browser.
Return exactly one JSON object.

Required output shape:
{
  "context": {
    "summary": "short paragraph",
    "successCriteria": ["criterion 1", "criterion 2"]
  },
  "steps": [
    {
      "type": "same as input step type",
      "name": "short human-readable step name",
      "confidence": 0.0
    }
  ],
  "model": {
    "provider": "kimi",
    "model": "kimi-k2.5",
    "thinking_mode": "disabled"
  }
}

Rules:
- Keep the exact same number of steps as the heuristic workflow.
- Keep each step type identical to the corresponding heuristic step.
- Only enrich summary, success criteria, step names, and confidence.
- Use confidence from 0.0 to 1.0.
- Be concise and practical.
""".strip();

    request_context: dict[str, Any] = {
        "goal": str(normalized_session.get("goalContext", "")),
        "start_url": str(normalized_session.get("startUrl", "")),
        "status": str(normalized_session.get("status", "")),
        "semantic_summary": latest_semantic_summary(raw_session),
        "event_summary": compact_event_summary(cleaned, 12),
        "heuristic_workflow": {
            "name": str(partial.get("name", "")),
            "context": partial.get("context", {}),
            "inputs": partial.get("inputs", []),
            "steps": partial.get("steps", [])
        }
    };

    payload: dict[str, Any] = {
        "model": str(config.get("model", DEFAULT_KIMI_MODEL)),
        "messages": [
            {
                "role": "system",
                "content": "You are Kimi, a careful workflow compiler assistant."
            },
            {
                "role": "system",
                "content": system_prompt
            },
            {
                "role": "user",
                "content": json.dumps(request_context)
            }
        ],
        "response_format": {"type": "json_object"},
        "max_tokens": 1800
    };

    if str(config.get("thinking_mode", "disabled")) == "disabled" {
        payload["thinking"] = {"type": "disabled"};
    }

    return payload;
}

"""R: POST one JSON payload to the Kimi chat completions endpoint.
M: Uses Python stdlib HTTP utilities so the integration stays Jac-native.
E: Raises descriptive exceptions for HTTP/network/parse failures.
"""
def post_kimi_json(config: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any] {
    endpoint: str = str(config.get("base_url", DEFAULT_KIMI_BASE_URL)).rstrip("/") + "/chat/completions";
    api_key: str = str(config.get("api_key", ""));
    request_body: bytes = json.dumps(payload).encode("utf-8");

    request: Any = Request(
        endpoint,
        data=request_body,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + api_key
        },
        method="POST"
    );

    try {
        response: Any = urlopen(request, timeout=30);
        raw_bytes: Any = response.read();
        response.close();
        raw_body: str = str(raw_bytes.decode("utf-8"));
        return json.loads(raw_body);
    } except HTTPError as err {
        details: str = "";
        try {
            details = err.read().decode("utf-8");
        } except Exception {
            details = "";
        }
        raise Exception("Kimi HTTP " + str(err.code) + (": " + details if details else ""));
    } except URLError as err {
        raise Exception("Kimi network error: " + str(err.reason or err));
    }
}

"""R: Extract the JSON-mode object returned by Kimi chat completions.
M: Reads `choices[0].message.content`, parses it as JSON, and returns the dict.
E: Raises when the response is incomplete, malformed, or missing a usable choice.
"""
def parse_kimi_json_mode_response(response: dict[str, Any]) -> dict[str, Any] {
    choices: Any = response.get("choices", []);
    if not isinstance(choices, list) or not choices {
        raise Exception("Kimi response missing choices");
    }

    first_choice: Any = choices[0];
    if not isinstance(first_choice, dict) {
        raise Exception("Kimi response choice is invalid");
    }

    message: Any = first_choice.get("message", {});
    if not isinstance(message, dict) {
        raise Exception("Kimi response message is invalid");
    }

    content: Any = message.get("content", "");
    if not isinstance(content, str) or not content.strip() {
        raise Exception("Kimi response content is empty");
    }

    parsed: Any = json.loads(content);
    if not isinstance(parsed, dict) {
        raise Exception("Kimi JSON mode returned a non-object payload");
    }

    finish_reason: str = str(first_choice.get("finish_reason", ""));
    if finish_reason == "length" {
        parsed["_warning"] = "Kimi response was truncated";
    }

    return parsed;
}

"""R: Run compile-time workflow enrichment through Kimi 2.5.
M: Builds a JSON-mode prompt, calls Moonshot's chat completions API, and returns mergeable workflow hints.
E: Raises on config or API failures so the compiler can fall back to heuristics with warnings.
"""
def kimi_compile_enrichment(
    raw_session: dict[str, Any],
    normalized_session: dict[str, Any],
    cleaned: dict[str, Any],
    partial: dict[str, Any],
    options: dict[str, Any]
) -> dict[str, Any] {
    config: dict[str, Any] = resolve_kimi_compile_config();
    if not bool(config.get("enabled", False)) {
        raise Exception("Kimi compile enrichment is not enabled");
    }

    request_payload: dict[str, Any] = build_kimi_compile_request(
        raw_session,
        normalized_session,
        cleaned,
        partial,
        config
    );

    response: dict[str, Any] = post_kimi_json(config, request_payload);
    parsed: dict[str, Any] = parse_kimi_json_mode_response(response);

    parsed["model"] = {
        "provider": "kimi",
        "model": str(config.get("model", DEFAULT_KIMI_MODEL)),
        "thinking_mode": str(config.get("thinking_mode", "disabled"))
    };
    return parsed;
}
