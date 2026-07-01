# Codex Project Notes

These notes capture the current drift coding preferences from the Timer HUD rewrite.

## Gesture Lifecycle

- Treat `gestureStatus` as the listener's source of truth.
- Drive listener behavior by state first:
  - `.waiting`: check only whether a gesture can become possible.
  - `.possible`: check only whether that gesture progresses or cancels.
  - `.progressing`: emit HUD scroll/pinch inputs.
  - `.cancelled` / `.ended`: do not emit new events.
- Keep activation recognition and HUD input handling independent. Do not add extra mode flags such as `interactionKind` when `gestureStatus` already explains the lifecycle.
- Do not make listeners depend on frontend HUD visibility. The Timer HUD listener should not need `isTimerHUDOpen`.
- Store only the gesture data needed for deltas, such as `pendingCenter` and `pendingScale`.
- Do not store coordinate workaround state like `verticalDirection` in a listener. Coordinate normalization belongs before listeners receive `TrackpadSnapshot`.

## Trackpad Phases

- `TrackpadSnapshot.phase` should represent contact-list continuity, not just whether any finger remains on the trackpad.
- A sequence should end if the active `FingerContact` list changes, including count or identity changes.
- After an ended sequence, a new contact list should begin as a new gesture rather than continuing as `.changed`.

## Timer HUD Behavior

- Timer HUD activation and Timer HUD adjustment are separate concerns:
  - activation opens/claims the HUD,
  - only a progressing gesture sends timer input events.
- Keep Timer HUD input focused on scroll/pinch classification after activation has progressed.
- Do not re-enable haptics in `TimerHUDDefinition` unless explicitly asked; the current Timer HUD rewrite leaves duration-change haptics commented out.

## When Editing This Area

- Preserve the architecture from `drift architecture.pdf`: possible -> progressing/cancelled -> ended/waiting.
- Prefer simple guards and direct state transitions over extra inferred state.
- Avoid mixing UI state, gesture recognition, and event emission in one branch.
