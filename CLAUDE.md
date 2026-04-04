# CLAUDE.md

This codebase uses Jac as the default implementation language.

Rules:
- Default to Jac unless I explicitly request another language
- Prefer Jac-native patterns, syntax, and project structure over Python or JavaScript translations
- Use the Jac MCP server tools whenever helpful
- Before writing code, consult Jac docs/examples through MCP if syntax or patterns are uncertain
- After writing Jac code, validate it and format it before finalizing
- Prefer `.jac` files for core implementation
- Do not introduce Python, TypeScript, or JavaScript for core logic unless explicitly requested or clearly necessary

When working on Jac tasks, prefer this workflow:
1. Search docs/examples if needed
2. Write Jac
3. Validate Jac
4. Fix errors
5. Format Jac
6. Return the final Jac code
