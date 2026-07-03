# drift

drift is a macOS menu-bar utility for testing raw trackpad input.

## What is built

- Native macOS menu-bar app using Swift, SwiftUI, and AppKit.
- A live, in-memory log window that reports raw frames, listener state transitions, semantic events, and HUD state.
- No shell-command profiles or gesture-to-command execution.
- An isolated C listener that dynamically loads Apple's private `MultitouchSupport.framework` and reduces each raw contact frame to `TXMTTrackpadSnapshot`.
- No registered gesture listeners by default.

## Input architecture

1. The C listener copies private `TXMTFinger[]` frames into a C-side `TXMTTrackpadSnapshot`. It does not recognize gestures or suppress events.
2. `CTrackpadBridge` copies the borrowed C snapshot into a Swift-owned `TrackpadSnapshot`.
3. `ListenerPipeline` calls listener structs synchronously in registration order. A decision may stop the current frame, claim the contact sequence, request typed suppression, and emit semantic backend events.
4. `EventSuppressionController` applies the exact axis and direction requested by listeners while preserving unsuppressed scroll components.
5. `SwiftBridge` sends emitted semantic events to the frontend. `HUDStore` owns active-HUD and custom frontend state, while `HudDefinition` defines HUD content, size, and placement.

Each future listener belongs in `Sources/drift/Infrastructure/Input/Listeners` and is explicitly registered in order. The folder is intentionally empty right now.

Implementation notes live beside the types and behavior they describe as code comments.

## UI implementation rules

- Clarify before assuming when a UI request is ambiguous.
- Respect changes made by the user. If the user removes a style constant, dimension, animation, transition, or abstraction, keep it removed unless there is an explicit request to bring it back.
- Be extra careful with UI changes and prefer the smallest edit that satisfies the request.
- Use existing values for typography, padding, spacing, border radius, colors, and dimensions. If an appropriate value does not already exist, ask before adding one.
- Do not introduce random or one-off style values. Avoid local aliases for shared style values unless explicitly requested.

## SwiftUI animation guardrails

- If a style constant, dimension, animation, transition, or abstraction is removed, keep it removed unless there is an explicit request to bring it back. Removals are treated as intentional design direction.
- Keep HUD/window size changes mode-based and stable. Do not update `HUDStore` size overrides from hover, focus, countdown, or other high-frequency UI state.
- Avoid changing a parent `.frame(width:)` at the same time a child view is entering or leaving with a transition. Reserve the needed width and transition the child inside that stable space.
- For hover-only side panels such as the Timer/Pomodoro duration rail, keep the NSPanel size and parent SwiftUI frame constant while toggling the rail view.
- Small fixed cells inside rows, such as icon alignment boxes, are fine because they do not resize the HUD window or transition parent container.

## Build in Xcode

Open the native application project:

```sh
open drift.xcodeproj
```

In Xcode, select the `drift` scheme and `My Mac`, then press Play. Open the `.xcodeproj` directly, not `Package.swift` or `.swiftpm/xcode/package.xcworkspace`. The package workspace launches a bare executable and cannot provide the macOS app bundle required by the menu-bar app.

## Command-line build

The project can also be checked with Swift Package Manager:

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift build --disable-sandbox
```

The extra environment variable keeps compiler cache files inside the project. `--disable-sandbox` avoids SwiftPM's package sandbox, which can be blocked inside restricted automation environments.

To create a local `.app` bundle:

```sh
Scripts/create-app-bundle.sh
```

The app bundle will be created at:

```text
build/drift.app
```

## First self-test

1. Open `build/drift.app`.
2. If suppression is unavailable, open System Settings and grant drift permissions under Privacy & Security:
   - Accessibility
   - Input Monitoring, if macOS shows it
3. drift opens its Live Log window. Touch or move fingers on the trackpad.
4. Confirm the window reports raw frames, contacts, center, scale, and rotation.

## Current v1 limitations

- The private multitouch bridge is intentionally isolated and experimental.
- No gestures or HUDs are registered by default.
- The Live Log is intentionally in-memory and clears when drift quits.
