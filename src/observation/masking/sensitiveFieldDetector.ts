// Sensitive field detection runs at record time — before values are stored.
// This is structural masking, not model-based inference.

const SENSITIVE_PATTERNS = [
  /password/i,
  /passwd/i,
  /secret/i,
  /token/i,
  /api.?key/i,
  /credit.?card/i,
  /card.?number/i,
  /cvv/i,
  /ssn/i,
  /social.?security/i,
  /auth/i,
];

export function isSensitiveField(
  hints: {
    name?: string;
    label?: string;
    placeholder?: string;
    type?: string;
    id?: string;
  },
  extraPatterns: RegExp[] = []
): boolean {
  if (hints.type === "password") return true;

  const haystack = [hints.name, hints.label, hints.placeholder, hints.id]
    .filter(Boolean)
    .join(" ");

  return [...SENSITIVE_PATTERNS, ...extraPatterns].some((p) => p.test(haystack));
}
