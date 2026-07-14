---
status: accepted
---

# Support macOS 13 with availability-gated enhancements

drift supports macOS 13 as its minimum deployment target. Features introduced by later macOS releases must be guarded by availability checks and provide a functional fallback on supported earlier releases, rather than raising the deployment target; this preserves the app's supported-platform commitment while allowing newer system enhancements where present.
