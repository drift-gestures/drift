# Agent Notes

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
- After completing a task that changes the codebase, provide one consolidated architecture-level change map in the final response. List the functions, views, stores, services, or other code owners that were modified, indicate their location within the architecture, and show how responsibility flows between them. Include one Mermaid flowchart. Do not produce architecture maps after individual edits or in intermediate progress updates.

## UI Discipline

- Be extra careful with UI changes. Prefer the smallest possible edit that satisfies the request.
- When changing UI, use existing values for typography, padding, spacing, border radius, colors, and dimensions. If an appropriate value does not already exist, ask before adding a new one.
- Do not introduce random or one-off style values. Avoid local aliases for shared style values unless the user explicitly asks for them.

## SwiftUI Animation Guardrails

- Do not add animations, transitions, or motion effects on your own. Only add or change them when the user explicitly asks. Leave animation code completely to the user, because its SwiftUI and animation behaviours are very weird.
- Keep HUD/window size changes mode-based and stable. Do not update `HUDStore` size overrides from hover, focus, countdown, or other high-frequency UI state.
- Avoid changing a parent `.frame(width:)` at the same time a child view is entering or leaving with a transition. Reserve the needed width and transition the child inside that stable space.
