# Architecture Issues

This file tracks architecture concerns raised during review of the current implementation.

## Issue 1: Listener Should Own The HUD

Status: fixed in code.

Original issue:

The previous implementation let `TimerHUDInputListener` recognize the gesture and emit HUD lifecycle events, but `AppDelegate` actually opened/closed the HUD by mutating `HUDStore`.

Concern:

- The listener owns the user intent but not the HUD lifecycle.
- HUD close/open state is split across listener state, `BackendEvent`, `AppDelegate`, `HUDStore`, `HUDVisibilityState`, and `HUDTestingState`.
- This makes it easy for input processing, haptic delivery, and visual teardown to disagree about whether a HUD is still active.

Desired direction:

- The listener should own HUD lifecycle decisions.
- Other layers may render, transport, or observe, but should not decide whether the HUD is open.

Resolution:

- Added `HUDController` as the listener-facing lifecycle handle.
- `TimerHUDInputListener` now calls `HUDController.open(...)`, `HUDController.close(...)`, and `HUDController.send(...)`.
- `AppDelegate.handleBackendEvent(_:)` no longer mutates HUD visibility or delivers HUD input messages; it only logs and performs app-level side effects.
- HUD active state is updated synchronously in the controller before the main-actor render update is scheduled.

## Issue 2: Why Does `SwiftBridge` Send `keyboardInteractionReceiver` During Start?

Status: clarified and partially reduced.

Current behavior:

- `AppDelegate` passes `shouldReceiveKeyboardInteraction` into `SwiftBridge`, but the predicate now asks `HUDController` whether the Timer HUD is active.
- `SwiftBridge.start()` passes `keyboardInteractionReceiver` and `shouldReceiveKeyboardInteraction` into `EventSuppressionController.start(...)`.
- The event tap can then forward selected global key-down events back into `SwiftBridge.receive(.keyboardPress(...))`.

Likely reason:

- The CoreGraphics event tap is installed by `EventSuppressionController`, so it is the only layer that can see and optionally suppress global key events before the foreground app receives them.
- Escape needs to close an active HUD even when another app is frontmost.
- If Escape is handled, the matching key-down/key-up should be suppressed so the foreground app does not also receive Escape.

Concern:

- Starting keyboard delivery through `SwiftBridge.start()` makes keyboard routing feel like event-tap configuration rather than listener-owned input policy.
- The callback loops from `EventSuppressionController` back into `SwiftBridge`, which is easy to miss when reading startup flow.
- HUD keyboard lifecycle is coupled to suppression startup, not to the active HUD/session owner.

Open question:

- Should global keyboard forwarding be modeled as a normal input source registered with the listener pipeline, while suppression remains only the low-level event filtering mechanism?

Resolution:

- Kept the callback path because `EventSuppressionController` owns the CoreGraphics event tap and must decide suppression before the foreground app receives Escape.
- Removed HUD lifecycle coupling from the keyboard predicate by routing it through `HUDController` instead of a raw `HUDVisibilityState` dependency.
- The remaining callback is low-level input transport; the listener still decides whether Escape closes the HUD.

## Issue 3: Only One HUD At A Time

Status: fixed in code.

The previous implementation modeled active HUDs as a set:

- `HUDStore.activeHUDs: Set<HUDID>`
- `HUDVisibilityState.activeHUDs: Set<HUDID>`
- `HUDWindowPresenter.windows: [HUDID: NSPanel]`
- `HUDTestingState.testingHUDs: Set<HUDID>`

Concern:

- The type model allows multiple HUDs to be active at the same time.
- Presenter logic is written to create and monitor multiple HUD windows.
- Outside-click handling loops through every visible HUD and can emit one click interaction per HUD.
- Future HUDs would inherit ambiguity around input ownership, Escape handling, close ordering, and message routing.

Desired direction:

- The app should have a single global active HUD session.
- Even `activeHUDID: HUDID?` would better represent the intended invariant.
- Opening a HUD should either fail while another HUD is active or close/replace the current HUD through one explicit policy.

Resolution:

- Replaced active HUD sets with `activeHUDID: HUDID?` in `HUDStore` and `HUDVisibilityState`.
- Changed `HUDWindowPresenter` from `[HUDID: NSPanel]` to one active panel.
- Changed `HUDTestingState` from a set to one optional testing HUD ID.
- `HUDController.open(...)` rejects opening a different HUD while another HUD is active.
