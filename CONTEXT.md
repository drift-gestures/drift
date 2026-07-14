# Input Suppression

This context defines drift’s foreground-input suppression capability and its safety behavior when macOS disables that capability.

## Language

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
