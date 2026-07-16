# Agent Notes

## Agent Workflow

- `.agents/WORKFLOW.md` is the single source of truth for Drift's agent-assisted
  product-development workflow.
- Use the project skills in `.agents/skills/` for shaping work, building
  approved issues, preparing UI handouts, and maintaining the user guide.
- Skills apply the workflow; they do not override the standing directions in
  this file.

## Communication

- For larger logic flows, explain the mental model before the details.
- Show how responsibilities, states, or information move through the system.
  Use one small diagram or concrete analogy when it materially improves
  understanding.
- Avoid presenting a flat inventory of files, stages, or rules without first
  explaining how the pieces relate and why they exist.
- Explain every architectural change as a mental model: identify the owners,
  boundaries, responsibility flow, and why the new structure exists. Do not
  present architectural changes as only a series of disconnected facts.
- Keep simple answers simple; do not add diagrams to one-step or obvious work.

## Standing User Direction

- Follow the user's instructions strictly. Do not do anything against what the user said.
- If a different approach seems better or a user instruction appears risky or conflicting, stop work and ask before proceeding.
- Clarify before implementing when the request has a real ambiguity that affects the outcome.
- Never choose between raising a deployment target and adding API-availability gating without explicit user approval. Treat supported-platform changes as a material product decision, even when one direction appears consistent with existing code.
- Do not over-clarify obvious choices. When the intended file, workspace, or next step is clear from context, proceed.

## Change Ownership

- If the user removes a style constant, dimension, animation, transition, or abstraction, do not re-add it under a new name or reintroduce the same idea elsewhere unless the user explicitly asks for it. Treat removals as intentional design direction.
- Always respect changes made by the user. If a recent user edit conflicts with an implementation idea, ask before changing it.
- Clarify before assuming when the request could reasonably be interpreted in more than one way.

## Engineering Quality

- Whenever writing code, think through the architecture first: extensibility, ownership boundaries, and lifecycle responsibilities should be clear and proper before implementation.
- Do not write code that merely "just works." Prefer code that fits the existing architecture, has the right ownership model, and will be understandable to maintain or extend later.
- After completing a task that changes application code, provide one consolidated architecture-level change map in the final response. List the functions, views, stores, services, or other code owners that were modified, indicate their location within the architecture, and show how responsibility flows between them. Include one Mermaid flowchart. Do not produce architecture maps after individual edits or in intermediate progress updates. Do not create an architecture map for basic non-code changes, including `.md` documentation writes.

## GitHub Issue Metadata

- Every GitHub issue must explicitly set all three of these properties when it is created:
  - **Type**
  - **Priority**
  - **Effort**
- Never leave Type, Priority, or Effort unset. Discover the repository's valid issue types, organization field IDs, and option names before creating or updating the issue; never guess them.
- When creating or updating GitHub issues, use the repository or project’s real fields for priority, effort, status, and similar metadata. Do not duplicate those values in the issue body.
- If the required project fields are unavailable or cannot be written, stop and report the access blocker instead of substituting body text for fields.
- Before starting or refreshing GitHub authorization (including a device-login flow), ask the user for approval every time.
- Always run `gh` commands outside the sandbox by requesting approval through the command popup. Do not first attempt the command inside the sandbox, and do not ask the user to copy and run the command manually.
- Use GitHub's issue APIs, not project fields, for issue Type and organization-level issue fields. Use API version `2026-03-10`:
  - After `gh issue create` returns an issue number, run both the Type PATCH command and the field-values POST command below before reporting the issue as created.
  - List valid issue types with `gh api -H 'X-GitHub-Api-Version: 2026-03-10' repos/OWNER/REPO/issue-types`.
  - Set Type with `gh api --method PATCH -H 'X-GitHub-Api-Version: 2026-03-10' repos/OWNER/REPO/issues/NUMBER -f type=TYPE_NAME`.
  - Discover Priority, Effort, and other issue fields and their options with `gh api -H 'X-GitHub-Api-Version: 2026-03-10' orgs/ORG/issue-fields`.
  - Set issue field values with `gh api --method POST -H 'X-GitHub-Api-Version: 2026-03-10' repos/OWNER/REPO/issues/NUMBER/issue-field-values --input FIELD_VALUES_JSON`.
  - Build `FIELD_VALUES_JSON` as `{"issue_field_values":[{"field_id":FIELD_ID,"value":"OPTION_NAME"}]}`. Discover `FIELD_ID` and `OPTION_NAME` from the organization fields response; never guess or hardcode them across repositories.

## UI Discipline

- Be extra careful with UI changes. Prefer the smallest possible edit that satisfies the request.
- When changing UI, use existing values for typography, padding, spacing, border radius, colors, and dimensions. If an appropriate value does not already exist, ask before adding a new one.
- Do not introduce random or one-off style values. Avoid local aliases for shared style values unless the user explicitly asks for them.

## SwiftUI Animation Guardrails

- Do not add animations, transitions, or motion effects on your own. Only add or change them when the user explicitly asks. Leave animation code completely to the user, because its SwiftUI and animation behaviours are very weird.
- Keep HUD/window size changes mode-based and stable. Do not update `HUDStore` size overrides from hover, focus, countdown, or other high-frequency UI state.
- Avoid changing a parent `.frame(width:)` at the same time a child view is entering or leaving with a transition. Reserve the needed width and transition the child inside that stable space.
