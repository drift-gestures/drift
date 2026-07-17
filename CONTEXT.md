# Drift Domain Language

This context defines the product language used across drift’s input, drawing, and window-management capabilities.

## Input Suppression

**Foreground-event suppression**:
The drift capability that prevents selected pointer, scroll, or keyboard events from reaching the foreground application.
_Avoid_: Input blocking, event swallowing

**Initial permission setup**:
The period before Foreground-event suppression has first become available in an app process. Missing permissions may be checked automatically during this period.
_Avoid_: Suppression disabled, runtime recovery

**Suppression disabled**:
A fail-open safety state in which drift does not suppress foreground events or attempt automatic recovery. It remains in effect until Manual retry or a new app process.
_Avoid_: Frozen, permission lost, restart required

**Manual retry**:
An explicit user request to leave Suppression disabled through one attempt to make Foreground-event suppression available again. A failed attempt remains Suppression disabled.
_Avoid_: Automatic retry, cooldown

## Excalidraw Persistence

**Excalidraw launcher**:
The transient HUD used to search, choose, or create drawings. It hands drawing requests to Drawing windows and never owns an editor.
_Avoid_: Drawing window, editor window

**Drawing window**:
A normal macOS document window that owns one open Excalidraw drawing and participates in Dock, Command-Tab, Window menu, resizing, minimization, and full-screen behavior.
_Avoid_: Excalidraw HUD, editor HUD

**Open drawing**:
A drawing with a live Drawing window. A drawing can have at most one Drawing window, and opening it again focuses that window.
_Avoid_: Duplicate editor, duplicate window

**Excalidraw menu request**:
An action that opens the Excalidraw menu and has no drawing-window side effect.
_Avoid_: Toggle request, drawing request

**Launcher execute request**:
The existing downward continuation of the same swipe-and-hold gesture that executes the active launcher selection while its lifecycle remains progressing.
_Avoid_: Menu request, second gesture, repeated gesture

**New drawing request**:
An action that creates a new drawing and opens it in a new Drawing window.
_Avoid_: Toggle request, reopen request

**Existing drawing request**:
An action targeting a specific saved drawing. It visibly restores and focuses that drawing’s existing Drawing window, does nothing further when already focused, or opens the drawing when it is not already open.
_Avoid_: Toggle request, duplicate window

**Drawing close request**:
An explicit request from a Drawing window’s red traffic-light control or Command-W to begin its Save-gated close. Focus changes, outside clicks, Escape, menus, and gestures are not close requests.
_Avoid_: Dismissal, toggle, deactivation

**Drawing snapshot**:
The complete, self-contained Excalidraw document used as drift’s unit of durable persistence. Saving never depends on an earlier incremental change message having arrived.
_Avoid_: Patch, delta, change set

**Drawing thumbnail**:
Eventually consistent preview data generated independently after a Drawing snapshot is saved. Its generation or failure never delays or invalidates drawing persistence, and the launcher may show the last successfully generated thumbnail.
_Avoid_: Save payload, drawing checkpoint

**Background autosave**:
An opportunistic Drawing snapshot save while editing. Its failure is retried by later changes and does not surface separate error UI because Save-gated close remains the durability boundary.
_Avoid_: Close save, guaranteed save

**Unsaved drawing**:
An Open drawing whose in-memory state is newer than its last successful Background autosave. Its Drawing window shows the standard macOS edited indicator.
_Avoid_: Save error, corrupted drawing

**Close-save request**:
A one-time request to persist a fresh Drawing snapshot during Save-gated close. It times out after ten seconds; Retry immediately supersedes it, and superseded work cannot commit or close the window.
_Avoid_: Incremental revision, background autosave

**Unsafe close**:
An explicitly confirmed close available only after a Close-save request fails or times out. It abandons changes since the last successful Background autosave and closes without establishing durability.
_Avoid_: Cancel, normal close, Force Quit

**Save-gated close**:
A normal drawing-window close or normal app quit that always captures and durably saves a fresh Drawing snapshot before completing, regardless of autosave debounce or in-flight state. A failed or timed-out Close-save request preserves the Drawing window and offers Retry, Return to Drawing, or a separately confirmed Unsafe close.
_Avoid_: Best-effort save, teardown save

**Quit save barrier**:
The normal-quit boundary that waits for every Open drawing to resolve its own Save-gated close. Retry continues the pending quit after successful saves, Return to Drawing cancels termination and restores every Drawing window, and each separately confirmed Unsafe close resolves only its own drawing.
_Avoid_: Sequential teardown, partial quit

**Unclean termination**:
A Force Quit, crash, power loss, or other process ending that cannot complete a Save-gated close. Drift preserves the last successful Background autosave but does not guarantee the latest in-memory state.
_Avoid_: Normal quit, close failure
