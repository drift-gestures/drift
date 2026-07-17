---
name: drift-build
description: Implement an approved Drift GitHub issue autonomously through a tested, independently reviewed, documented pull request. Use when the user asks Codex to start, build, implement, or finish an issue marked ready for agent.
---

# Build Approved Drift Work

Find and read the repository-root `.agents/WORKFLOW.md`, the issue and its linked
context, and all active `AGENTS.md` instructions before editing.

## Take ownership safely

- Require an approved issue marked `ready-for-agent`.
- If another collaborator is assigned or has clearly claimed the issue, leave
  it with them and report that Codex is waiting.
- When work actually begins, discover the authenticated GitHub user and assign
  the issue to that user. Do not assign it earlier.
- Create one dedicated `codex/issue-<number>-<slug>` branch.
- Delegate bounded discovery to `drift-scout`.
- Use `drift-engineer` as the single implementation writer. Do not let the root
  task or another agent edit application code concurrently.

## Plan in proportion to risk

Understand the existing ownership and lifecycle before changing code. Proceed
without routine approval when the issue supplies enough product intent.

Pause before editing when the plan requires a consequential decision involving
architecture, dependencies, persistence, permissions, security, concurrency,
destructive data changes, platform support, API availability, or material scope
expansion. Consult `drift-architect` for that narrow decision and present its
mental model to the user when approval is required.

For UI work, ask the user for the relevant Figma design selection URL containing
a `node-id` when they request that Codex start the issue. Wait for that link before invoking
`drift-figma-handout-pack`, even when the approved issue contains screenshots or
product descriptions. Complete the handout with the user and obtain approval
before implementing. Use `drift-ui-specialist` for design interpretation and
reserve routine implementation for `drift-engineer`.

## Deliver the whole change

Implement the smallest coherent product change that satisfies the issue.
Exercise engineering judgment instead of mechanically following a fixed file
list.

Before presenting the work:

1. Run the relevant build and tests and add focused coverage where needed.
2. Exercise changed behavior where practical.
3. For UI work, run the interface, capture evidence, and compare it with the
   approved design handout. Delegate final visual judgment to
   `drift-ui-specialist`.
4. After application-source writing has stopped, use `drift-documenter` with
   `drift-generate-user-guide` for user-visible changes.
5. Use `drift-reviewer` for independent specification, correctness, regression,
   maintainability, and test review.
6. Use `drift-scout` for bounded verification evidence and log analysis.
7. Fix accepted findings with `drift-engineer` and repeat affected verification.

Reviewers must not approve their own implementation. Prefer concise findings
with evidence over generic commentary. Run independent read-only review work in
parallel only when it is genuinely useful; do not spawn reviewers for duplicate
perspectives on trivial changes.

## Prepare acceptance

Commit and push the completed branch, then open a pull request tied to the
issue. Present:

- the user-visible outcome;
- acceptance-criteria status;
- build and test evidence;
- visual evidence for UI changes;
- user-guide changes;
- architecture and risk notes;
- unresolved limitations, if any.

Never merge without the user's authorization. Require full product acceptance
for large changes as defined in `.agents/WORKFLOW.md`.

If the user rejects or substantially revises the result, identify the failure
and propose the smallest generalizable improvement. Do not silently rewrite the
workflow or its skills.
