---
name: drift-figma-handout-pack
description: Turn Figma designs, screenshots, exports, and product discussion into an implementation-ready Drift UI handout. Use while shaping or building any Drift UI, UX, screen, HUD, settings flow, component, or visual change, especially when direct Figma MCP access is limited or unavailable.
---

# Prepare a Drift Figma Handout Pack

Find and read the repository-root `.agents/WORKFLOW.md`, the active `AGENTS.md`
UI rules, and relevant existing Drift UI code before preparing the handout.

Prefer running this skill through the project `drift-ui-specialist` agent so
design interpretation and final visual judgment use Sol/High. Keep routine UI
implementation with the Terra-based `drift-engineer`.

The handout bridges the gap between visual evidence and implementation intent.
It does not require Figma MCP access. Use whatever the user can provide:
screenshots, exported frames, measurements, a Figma URL, existing assets, or a
spoken description.

## Understand before specifying

- Inspect existing design tokens, components, layout conventions, and nearby
  screens.
- Treat screenshots as evidence of appearance, not complete behavior.
- Ask only about ambiguities that materially affect the result.
- Never invent motion, interaction behavior, dimensions, or new design values.
- Record whether each important detail is exact, relational, or intentionally
  flexible.

## Produce the handout

Create a compact `Design handout` section suitable for the GitHub issue. Include
only applicable information:

- linked or attached visual references and which state each shows;
- product intent and the visual hierarchy users should perceive;
- layout regions and spacing relationships;
- typography, colors, materials, icons, and reusable Drift components;
- default, hover, pressed, focused, selected, disabled, empty, loading, error,
  and permission states;
- window sizing, resizing, scrolling, and content-overflow behavior;
- mouse, keyboard, trackpad, and accessibility interactions;
- explicitly designed motion;
- exact constraints versus areas where engineering judgment is allowed;
- a visual acceptance checklist.

Prefer relationships such as alignment, grouping, and stable reserved space over
isolated pixel guesses. If an exact value is required but unavailable, surface
the gap instead of fabricating it.

## Support implementation and review

During implementation, use the approved handout as the UI contract. Preserve
existing Drift values unless the user approves a new value.

During visual review, compare captures of the running interface with both the
references and the written intent. Judge behavior across relevant states and
window sizes, not only a single static frame.

If implementation evidence reveals that the handout was ambiguous, clarify the
handout rather than silently choosing a new product direction.
