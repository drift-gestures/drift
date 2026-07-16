---
name: drift-shape
description: Shape a Drift product idea through natural conversation into an approved GitHub issue or parent issue with useful sub-issues. Use when the user wants to explore, define, scope, specify, or publish new Drift work, including UI ideas that need a design handout.
---

# Shape Drift Work

Find and read the repository-root `.agents/WORKFLOW.md` and the active
`AGENTS.md` instructions before shaping work.

## Understand the product change

- Discuss the idea like a product-minded engineering partner.
- Challenge assumptions and expose missing behavior, but do not default to a
  long interrogation or a rigid questionnaire.
- Ask one focused question at a time only when the answer materially changes the
  product or implementation contract.
- Investigate the repository for facts instead of asking the user to provide
  discoverable codebase context.
- Distinguish user decisions from engineering details Codex can own.

Delegate bounded codebase discovery to `drift-scout`. Consult
`drift-architect` only when shaping the idea requires a consequential
architecture, persistence, permission, security, concurrency, or platform
decision.

For UI work, use `drift-figma-handout-pack` before finalizing the issue. Accept
screenshots, exports, descriptions, or available Figma context; do not require
Figma MCP access. Use `drift-ui-specialist` for the design interpretation.

## Form the work

Create one issue when the change is safely reviewable as a single vertical
slice. For larger ideas, draft a parent issue and native GitHub sub-issues that
each deliver independently testable user value. Avoid splitting only by
technical layer.

The draft must make the intended product legible:

- user problem and outcome;
- behavior and interaction rules;
- scope and non-goals;
- acceptance criteria;
- relevant design handout;
- important risks or decisions;
- dependencies and blocking relationships.

Propose Type, Priority, and Effort using the repository's real issue metadata.
The user must explicitly confirm Priority. Follow the GitHub metadata and
authorization rules in `AGENTS.md`; never guess field IDs or option names.

## Publish only after approval

Show the complete issue and sub-issue structure before creating anything.
Publish only after the user explicitly approves the draft and metadata.

Apply `ready-for-agent` only when the user explicitly approves the issue for
implementation. Do not implement the issue in this skill.
