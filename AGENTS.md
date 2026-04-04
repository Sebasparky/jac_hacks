# Project Agent Guidelines

## Language & Stack Rules
- Use Jac as the primary implementation language for this project.
- Do not introduce non-Jac application logic unless explicitly requested.
- External Python libraries are allowed when they provide clear value (SDKs, tooling, integrations).
- Keep Python usage minimal and focused on integration/support tasks.

## Code Style Rules
- Prefer the simplest implementation that satisfies requirements.
- Optimize for skimmability: short functions, clear names, shallow nesting, minimal indirection.
- Avoid clever patterns when a straightforward approach works.
- Keep files and modules focused on one responsibility.

## Function Documentation (RME Required)
- Every non-trivial function should include an RME note.
- RME format:
  - `R` (Role): what the function is responsible for.
  - `M` (Method): how it achieves the result at a high level.
  - `E` (Edge Cases): important edge conditions, failure modes, or assumptions.
- Keep RME brief (2-5 lines), practical, and close to the function.

## Maintainability Standards
- Make behavior explicit rather than implicit.
- Prefer predictable control flow over abstraction-heavy designs.
- Add comments only when they explain intent or non-obvious decisions.
- Keep public interfaces stable and easy to reason about.

## Review Checklist
- Is this implemented in Jac where appropriate?
- Is the code easy to skim and understand quickly?
- Are function names and boundaries clear?
- Are RME notes present for non-trivial functions?
- Did we avoid unnecessary complexity?
