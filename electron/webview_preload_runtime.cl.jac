"""Jac-authored webview preload telemetry runtime."""

cl import from 'electron' { ipcRenderer }

cl {
    """R: Install page-side telemetry capture for the browser webview.
    M: Records core interaction events and forwards compact payloads back to the host shell.
    E: Sensitive field values are redacted before they leave the page context.
    """
    def:pub installWebviewPreload() -> None {
        INPUT_DEBOUNCE_MS = 350;
        SENSITIVE_HINTS = [
            "password",
            "passcode",
            "token",
            "secret",
            "auth",
            "session",
            "cookie",
            "credit",
            "card",
            "ssn"
        ];
        pendingInputTimers = Reflect.construct(WeakMap, []);

        def emitObservation(eventType: any, target: any = {}, value: any = "", meta: any = {}) -> None {
            ipcRenderer.sendToHost("observation:event", {
                "type": str(eventType or "unknown"),
                "url": window.location.href,
                "target": target,
                "value": str(value or ""),
                "meta": meta
            });
        }

        def elementText(element: any) -> str {
            if not element {
                return "";
            }
            innerText = str(element.innerText or element.textContent or "").trim();
            if innerText {
                return innerText.slice(0, 140);
            }
            fallback = element.getAttribute("value") or element.getAttribute("alt") or element.getAttribute("title") or "";
            return str(fallback).trim().slice(0, 140);
        }

        def elementLabel(element: any) -> str {
            if not element {
                return "";
            }

            ariaLabel = str(element.getAttribute("aria-label") or "").trim();
            if ariaLabel {
                return ariaLabel.slice(0, 140);
            }

            fieldId = str(element.id or "").trim();
            if fieldId {
                labelNode = document.querySelector("label[for=\"" + CSS.escape(fieldId) + "\"]");
                if labelNode {
                    labelText = str(labelNode.innerText or labelNode.textContent or "").trim();
                    if labelText {
                        return labelText.slice(0, 140);
                    }
                }
            }

            parentLabel = element.closest("label");
            if parentLabel {
                parentText = str(parentLabel.innerText or parentLabel.textContent or "").trim();
                if parentText {
                    return parentText.slice(0, 140);
                }
            }

            placeholder = str(element.getAttribute("placeholder") or "").trim();
            return placeholder.slice(0, 140);
        }

        def describeTarget(element: any) -> any {
            if not element or not element.tagName {
                return {"tag": "", "text": "", "label": ""};
            }
            return {
                "tag": str(element.tagName or "").toLowerCase(),
                "id": str(element.id or "").slice(0, 120),
                "name": str(element.getAttribute("name") or "").slice(0, 120),
                "role": str(element.getAttribute("role") or "").slice(0, 80),
                "type": str(element.getAttribute("type") or "").slice(0, 40),
                "label": elementLabel(element),
                "text": elementText(element),
                "placeholder": str(element.getAttribute("placeholder") or "").slice(0, 140),
                "class_name": str(element.className or "").slice(0, 220)
            };
        }

        def isSensitiveTarget(target: any) -> bool {
            fieldType = str(target["type"] or "").toLowerCase();
            if fieldType == "password" {
                return True;
            }
            haystack = str((target["label"] or "") + " " + (target["name"] or "") + " " + (target["id"] or "") + " " + (target["placeholder"] or "")).toLowerCase();
            for hint in SENSITIVE_HINTS {
                if haystack.includes(hint) {
                    return True;
                }
            }
            return False;
        }

        def safeValue(value: any, target: any) -> str {
            if isSensitiveTarget(target) {
                return "__redacted__";
            }
            return str(value or "").slice(0, 300);
        }

        def queueInputEvent(element: any) -> None {
            if not element or not element.tagName {
                return;
            }
            previousTimer = pendingInputTimers.get(element);
            if previousTimer {
                clearTimeout(previousTimer);
            }
            timer = setTimeout(lambda {
                target = describeTarget(element);
                rawValue = element.value if "value" in element else "";
                emitObservation("input", target, safeValue(rawValue, target), {
                    "source": "page",
                    "trigger": "debounced_input"
                });
                pendingInputTimers.delete(element);
            }, INPUT_DEBOUNCE_MS);
            pendingInputTimers.set(element, timer);
        }

        document.addEventListener("click", lambda event: any {
            if not event.target or not event.target.tagName {
                return;
            }
            clickable = event.target.closest("a,button,input,textarea,select,[role='button'],[role='link']") or event.target;
            emitObservation("click", describeTarget(clickable), "", {"source": "page"});
        }, True);

        document.addEventListener("input", lambda event: any {
            if not event.target or not event.target.tagName {
                return;
            }
            if not ("value" in event.target) {
                return;
            }
            queueInputEvent(event.target);
        }, True);

        document.addEventListener("change", lambda event: any {
            if not event.target or not event.target.tagName {
                return;
            }
            if not ("value" in event.target) {
                return;
            }
            target = describeTarget(event.target);
            emitObservation("input", target, safeValue(event.target.value, target), {
                "source": "page",
                "trigger": "change"
            });
        }, True);

        document.addEventListener("submit", lambda event: any {
            if not event.target or not event.target.tagName {
                return;
            }
            emitObservation("submit", describeTarget(event.target), "", {"source": "page"});
        }, True);

        window.addEventListener("DOMContentLoaded", lambda {
            emitObservation("page_ready", {"role": "document", "label": "page_ready"}, "", {"source": "page"});
        });
    }
}
