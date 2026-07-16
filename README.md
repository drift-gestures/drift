# drift

drift is a macOS menu-bar utility for trackpad gestures, floating HUDs, and custom actions. It uses a private multitouch bridge to observe raw trackpad contacts and a Core Graphics event tap to coordinate foreground-event suppression and HUD keyboard input.

## What is built

- Native macOS menu-bar app using Swift, SwiftUI, and AppKit, with a live in-memory diagnostics log and an optional virtual trackpad view.
- Custom gestures saved locally and recognized while the configured advanced activation key is held. A full-screen overlay indicates that advanced gestures are being listened for; click it to stop listening until the activation modifiers are released.
- Custom gesture actions: keyboard shortcuts, application launches, URL opening, and executable scripts with arguments.
- Timer and Pomodoro HUD, including background timer coordination, notifications, and menu-bar status items.
- Excalidraw HUD with a bundled web host served locally by the app, local document storage, launcher/search/editor modes, and gesture-driven navigation.

## Runtime architecture

`AppDelegate` starts the HUD registry and background workers, then starts `SwiftBridge`. The bridge owns the private multitouch input source, ordered listener pipeline, and foreground-event suppression controller.

Listeners in `Sources/drift/Infrastructure/Input/Listeners` are registered in this order:

1. `CustomGestureListener` recognizes saved gestures while advanced activation is active and emits the selected custom action.
2. `TimerHUDInputListener` opens and controls the Timer/Pomodoro HUD when its feature toggles are enabled.
3. `ExcalidrawHUDInputListener` opens and controls the Excalidraw launcher, search, and editor when enabled.

Listeners run synchronously in registration order. A listener can claim the current interaction, request typed foreground-event suppression, and emit semantic events. `EventSuppressionController` preserves any scroll component that was not requested for suppression. `HUDController` owns the single active HUD session; `HUDRegistry` supplies the Timer and Excalidraw definitions and their app-owned background workers; `HUDWindowPresenter` renders the active definition in a floating AppKit window.

### Permissions and recovery

Raw trackpad observation uses the private `MultitouchSupport.framework` bridge. Foreground-event suppression and global keyboard handling require both macOS **Input Monitoring** and **Accessibility** permissions. drift requests missing permissions once per run and polls while it waits for approval.

If an event tap is disabled by macOS or either permission is revoked, drift fails open: it removes the tap and stops suppressing foreground input rather than blocking it. The Settings → General page reports **Disabled** and provides **Retry**, which makes one explicit fresh installation attempt after permissions have been restored. Gesture observation may still be available when suppression is unavailable, but any feature that needs interception will not suppress the foreground app.

### Custom action security

Custom actions are user-configured, device-local automation. Keyboard shortcuts are posted through the HID event tap; application and URL actions ask macOS to open the selected target; script actions launch the chosen executable directly with its configured argument list. Scripts run with the same user privileges as drift and are not sandboxed, confirmed, or restricted to a safe allow-list. Only save scripts and arguments you trust, and review them before enabling a gesture.

## Excalidraw host

The Excalidraw editor is a production HUD feature, not an external service: drift serves the bundled web assets on a local server and stores drawings locally. Building the native app rebuilds those assets through the Xcode build phase.

A current clean checkout prerequisite is Node.js/npm and an installed host dependency tree:

```sh
cd Web/ExcalidrawHost
npm ci
cd ../..
```

The build phase runs `npm run build`; it does not install dependencies. The clean-checkout workflow is being made reproducible in [issue #22](https://github.com/drift-gestures/drift/issues/22).

## Build and test

Open the native application project:

```sh
open drift.xcodeproj
```

In Xcode, select the `drift` scheme and **My Mac**, then Run. Ensure the Excalidraw prerequisites above are installed first.

The CI-compatible command-line checks are:

```sh
xcodebuild -project drift.xcodeproj -scheme drift -configuration Debug -destination 'platform=macOS' build
xcodebuild -project drift.xcodeproj -scheme drift -destination 'platform=macOS' test
```

To create a Release `.app` bundle and zip:

```sh
Scripts/create-app-bundle.sh
```

The script writes `build/drift.app` and `build/drift.zip` after the Xcode build, including the Excalidraw host build phase.

## First run

1. Launch drift and open **Settings** from the menu bar.
2. Grant **Input Monitoring** and **Accessibility** in System Settings → Privacy & Security when prompted.
3. If Settings reports Input Suppression as Disabled after permissions change, choose **Retry**.
4. Use the menu bar to open the live log or either HUD; configure custom gestures in Settings before using advanced activation.

## Current limitations and prototypes

- The private multitouch bridge is intentionally isolated and experimental; availability can vary across macOS releases and hardware.
- Event suppression depends on both macOS permissions and can be unavailable even while raw-trackpad diagnostics continue.
- The Excalidraw host build currently depends on locally installed Node/npm dependencies; see [#22](https://github.com/drift-gestures/drift/issues/22).
- Quick Actions, clipboard history, and emoji picker code are compiled prototypes with no listener, HUD registry entry, or user-visible entry point. They are not production features; their disposition is tracked in [issue #23](https://github.com/drift-gestures/drift/issues/23).
