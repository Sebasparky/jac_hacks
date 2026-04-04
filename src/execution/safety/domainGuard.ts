export type DomainCheckResult =
  | { allowed: true; domain: string }
  | { allowed: false; domain: string };

export function checkDomain(url: string, allowedDomains: string[]): DomainCheckResult {
  const domain = new URL(url).hostname;
  const allowed = allowedDomains.some((d) => domain === d || domain.endsWith(`.${d}`));
  return { allowed, domain };
}
