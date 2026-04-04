import type { TargetSpec, TargetLocator } from "../../shared/types/workflow.js";
import type { BrowserDriver, ElementHandle } from "../runner/workflowRunner.js";
import { scoreCandidates } from "./scoreCandidates.js";

export type ResolveResult =
  | { found: true; element: ElementHandle; locatorUsed: TargetLocator }
  | { found: false; triedLocators: TargetLocator[] };

/**
 * Attempts to find an element using the primary locator, then fallbacks in order.
 * CSS and XPath are tried last regardless of their position in the fallback list.
 */
export async function resolveTarget(
  spec: TargetSpec,
  driver: BrowserDriver,
  timeoutMs = 5000
): Promise<ResolveResult> {
  const locators = [spec.primary, ...(spec.fallbacks ?? [])];

  // Sort: semantic locators first, CSS/XPath last
  const sorted = [
    ...locators.filter((l) => l.kind !== "css" && l.kind !== "xpath"),
    ...locators.filter((l) => l.kind === "css" || l.kind === "xpath"),
  ];

  const tried: TargetLocator[] = [];

  for (const locator of sorted) {
    const element = await tryLocator(locator, driver, timeoutMs);
    tried.push(locator);

    if (element) {
      return { found: true, element, locatorUsed: locator };
    }
  }

  return { found: false, triedLocators: tried };
}

async function tryLocator(
  locator: TargetLocator,
  driver: BrowserDriver,
  timeoutMs: number
): Promise<ElementHandle | null> {
  try {
    switch (locator.kind) {
      case "label":
        return await driver.findElement("label", locator.label, timeoutMs);
      case "text":
        return await driver.findElement("text", locator.text, timeoutMs);
      case "placeholder":
        return await driver.findElement("placeholder", locator.placeholder, timeoutMs);
      case "name":
        return await driver.findElement("name", locator.name, timeoutMs);
      case "testid":
        return await driver.findElement("testid", locator.testId, timeoutMs);
      case "css":
        return await driver.findElement("css", locator.selector, timeoutMs);
      case "xpath":
        return await driver.findElement("xpath", locator.selector, timeoutMs);
    }
  } catch {
    return null;
  }
}
