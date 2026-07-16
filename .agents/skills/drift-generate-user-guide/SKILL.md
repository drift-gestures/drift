---
name: drift-generate-user-guide
description: Create, update, or audit Drift's user-facing documentation in docs/user-guide. Use after user-visible behavior changes, when preparing a Drift pull request, or when the user asks to explain the complete product from an end user's perspective.
---

# Maintain the Drift User Guide

Find and read the repository-root `.agents/WORKFLOW.md`, then inspect the shipped
behavior, relevant source, tests, existing documentation, and current screens
before writing.

Prefer running this skill through the project `drift-documenter` agent so
routine documentation work uses Luna/Medium. Do not perform documentation edits
concurrently with application-source edits.

## Document the product users experience

Maintain `docs/user-guide/` as a navigable explanation of Drift. Create the
directory and an entry-point document when they do not exist.

Write from the user's perspective:

- what the feature does and when it is useful;
- how to find, configure, and use it;
- required permissions or prerequisites;
- meaningful states and interactions;
- failure behavior and recovery;
- limitations users need to understand.

Do not mirror internal types, implementation structure, or architecture unless
an implementation fact directly helps a user operate the product safely.

## Choose the right scope

For a feature change, update only the affected guide sections and connected
navigation. For an explicit full audit, compare the complete guide against the
current application and repair missing, stale, duplicated, or contradictory
content.

Organize pages around user goals and product capabilities. Keep one obvious
starting point and link related workflows so a new user can understand the app
by reading the guide in order.

## Use trustworthy evidence

Base claims on current behavior, code, tests, and actual application output.
Do not document planned or prototype behavior as shipped functionality.

Use screenshots when they materially clarify navigation, controls, states, or
recovery. Capture the shipped interface rather than using a Figma reference as
proof of implemented behavior. Keep screenshots and their surrounding text
synchronized.

Before finishing, verify that:

- instructions match current labels and behavior;
- permission and recovery guidance is accurate;
- links and navigation are coherent;
- the changed feature is discoverable from the guide entry point;
- no internal implementation detail is presented as a user requirement.

For user-visible code changes, missing or inaccurate guide coverage is a failed
completion gate.
