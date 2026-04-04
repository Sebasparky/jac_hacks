import type { DomElementContext } from "../../shared/types/trace.js";

/**
 * Builds a DomElementContext from a live DOM element.
 * Runs in the browser context (content script or Electron renderer).
 */
export function describeElement(el: Element): DomElementContext {
  const tag = el.tagName.toLowerCase();
  const input = el as HTMLInputElement;

  const ctx: DomElementContext = { tag };

  if (el.id) ctx.id = el.id;
  if (input.name) ctx.name = input.name;
  if (input.type) ctx.type = input.type;

  const role = el.getAttribute("aria-role") ?? el.getAttribute("role");
  if (role) ctx.role = role;

  const label = resolveLabel(el);
  if (label) ctx.label = label;

  if (input.placeholder) ctx.placeholder = input.placeholder;

  const testId = el.getAttribute("data-testid") ?? el.getAttribute("data-test-id");
  if (testId) ctx.testId = testId;

  const innerText = (el as HTMLElement).innerText?.slice(0, 200);
  if (innerText) ctx.innerText = innerText;

  const nearby = extractNearbyText(el);
  if (nearby.length) ctx.nearbyText = nearby;

  const heading = findSectionHeading(el);
  if (heading) ctx.sectionHeading = heading;

  const formName = (el.closest("form") as HTMLFormElement | null)?.name;
  if (formName) ctx.formName = formName;

  return ctx;
}

function resolveLabel(el: Element): string | undefined {
  // 1. aria-label
  const ariaLabel = el.getAttribute("aria-label");
  if (ariaLabel) return ariaLabel;

  // 2. aria-labelledby
  const labelledById = el.getAttribute("aria-labelledby");
  if (labelledById) {
    const labelEl = document.getElementById(labelledById);
    if (labelEl?.textContent) return labelEl.textContent.trim();
  }

  // 3. <label for="...">
  const id = el.id;
  if (id) {
    const labelEl = document.querySelector(`label[for="${id}"]`);
    if (labelEl?.textContent) return labelEl.textContent.trim();
  }

  // 4. Wrapping <label>
  const wrappingLabel = el.closest("label");
  if (wrappingLabel?.textContent) return wrappingLabel.textContent.trim();

  return undefined;
}

function extractNearbyText(el: Element): string[] {
  const texts: string[] = [];
  let node: Element | null = el.previousElementSibling;
  let i = 0;
  while (node && i < 3) {
    const text = node.textContent?.trim();
    if (text) texts.push(text.slice(0, 80));
    node = node.previousElementSibling;
    i++;
  }
  return texts;
}

function findSectionHeading(el: Element): string | undefined {
  let node: Element | null = el.parentElement;
  while (node) {
    const heading = node.querySelector("h1,h2,h3,h4,h5,h6");
    if (heading?.textContent) return heading.textContent.trim().slice(0, 100);
    node = node.parentElement;
  }
  return undefined;
}
