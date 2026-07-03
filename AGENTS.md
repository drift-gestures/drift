# Agent Notes

## Change Ownership

- If the user removes a style constant, dimension, animation, transition, or abstraction, do not re-add it under a new name or reintroduce the same idea elsewhere unless the user explicitly asks for it. Treat removals as intentional design direction.
- Always respect changes made by the user. If a recent user edit conflicts with an implementation idea, ask before changing it.
- Clarify before assuming when the request could reasonably be interpreted in more than one way.

## UI Discipline

- Be extra careful with UI changes. Prefer the smallest possible edit that satisfies the request.
- When changing UI, use existing values for typography, padding, spacing, border radius, colors, and dimensions. If an appropriate value does not already exist, ask before adding a new one.
- Do not introduce random or one-off style values. Avoid local aliases for shared style values unless the user explicitly asks for them.

## SwiftUI Animation Guardrails

- Keep HUD/window size changes mode-based and stable. Do not update `HUDStore` size overrides from hover, focus, countdown, or other high-frequency UI state.
- Avoid changing a parent `.frame(width:)` at the same time a child view is entering or leaving with a transition. Reserve the needed width and transition the child inside that stable space.
- For hover-only side panels such as the Timer/Pomodoro duration rail, keep the NSPanel size and parent SwiftUI frame constant while toggling the rail view.
- Small fixed cells inside rows, such as icon alignment boxes, are fine because they do not resize the HUD window or transition parent container.
