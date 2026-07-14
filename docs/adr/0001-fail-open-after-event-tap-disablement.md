---
status: accepted
---

# Fail open after event-tap disablement

When CoreGraphics disables drift’s active event tap, or runtime permission monitoring observes that its permissions were revoked, drift enters Suppression disabled: it stops automatic permission checks, clears suppression state, and completely tears down the current tap session. It never re-enables or reuses that tap because macOS permission queries can remain stale after revocation, as observed while investigating issue #16.

Initial permission setup may continue polling before suppression first becomes available. Recovery from Suppression disabled requires a Manual retry or a new app process; Manual retry checks permissions, attempts to create a fresh event tap once, and resumes permission monitoring only after successful installation.
