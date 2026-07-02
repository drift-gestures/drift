# Current App Lifecycle

This documents the current implementation before the proposed listener-owned HUD redesign.

The important architectural fact is that HUD lifecycle is currently split across multiple owners:

- `AppDelegate` wires the app together and applies `BackendEvent` values to HUD state.
- `TimerHUDInputListener` recognizes gestures and emits Timer-specific HUD events, but does not own the HUD.
- `HUDStore` is the main-actor source used by the presenter to show and hide HUD windows.
- `HUDVisibilityState` is a thread-safe mirror of `HUDStore.activeHUDs` for listener/event-tap code.
- `HUDTestingState` separately tracks whether a HUD was opened from temporary menu-bar testing controls.
- `HUDWindowPresenter` renders active HUD definitions as `NSPanel` windows and sends outside-click and keyboard interactions back into `SwiftBridge`.
- `TimerHUDView` receives frontend HUD messages through `HUDMessageBus` and performs Timer HUD haptics.

## Type Ownership

```mermaid
flowchart TB
    AppDelegate["AppDelegate\n@MainActor\nComposition root"]

    ActivityLog["ActivityLogStore\nLive log state"]
    SwiftBridge["SwiftBridge\nInput coordinator\nOwns ListenerPipeline + suppression"]
    CBridge["CTrackpadBridge\nPrivate multitouch bridge"]
    Suppression["EventSuppressionController\nCoreGraphics event tap"]
    Pipeline["ListenerPipeline\nOrdered listener execution\nTracks claimed listener"]
    TimerListener["TimerHUDInputListener\nGesture state machine\nEmits BackendEvent"]

    HUDStore["HUDStore\n@MainActor ObservableObject\nactiveHUDs/customStates/trackpadState"]
    Visibility["HUDVisibilityState\nThread-safe active HUD mirror"]
    Testing["HUDTestingState\nThread-safe testing-open marker"]
    MessageBus["HUDMessageBus\n@MainActor PassthroughSubject"]
    Presenter["HUDWindowPresenter\n@MainActor\nOwns NSPanel instances + monitors"]
    TimerDef["TimerHUDDefinition\nHudDefinition id/size/position/content"]
    TimerView["TimerHUDView\nSwiftUI view\nSubscribes to HUDMessageBus\nTriggers haptics"]
    LogWindow["LoggingView\nReads ActivityLogStore + HUDStore"]
    Menu["Menu bar\nTemporary Timer HUD toggle"]

    AppDelegate --> ActivityLog
    AppDelegate --> SwiftBridge
    AppDelegate --> HUDStore
    AppDelegate --> Visibility
    AppDelegate --> Testing
    AppDelegate --> MessageBus
    AppDelegate --> Presenter
    AppDelegate --> Menu
    AppDelegate --> LogWindow

    SwiftBridge --> CBridge
    SwiftBridge --> Suppression
    SwiftBridge --> Pipeline
    Pipeline --> TimerListener

    TimerListener -.reads.-> Visibility
    TimerListener -.reads/writes.-> Testing

    HUDStore --> Visibility
    Presenter --> HUDStore
    Presenter --> MessageBus
    Presenter --> TimerDef
    TimerDef --> TimerView
    TimerView --> MessageBus
```

## App Startup

```mermaid
sequenceDiagram
    participant app as NSApplication
    participant appDelegate as appDelegate: AppDelegate
    participant activityLog as activityLog: ActivityLogStore
    participant hudVisibilityState as hudVisibilityState: HUDVisibilityState
    participant hudTestingState as hudTestingState: HUDTestingState
    participant hudMessages as hudMessages: HUDMessageBus
    participant hudStore as hudStore: HUDStore
    participant swiftBridge as swiftBridge: SwiftBridge
    participant listenerPipeline as listeners: ListenerPipeline
    participant timerListener as TimerHUDInputListener
    participant suppressionController as suppressionController: EventSuppressionController
    participant cBridge as cBridge: CTrackpadBridge
    participant menu as menu/status item: NSMenu + NSStatusItem
    participant hudPresenter as hudPresenter: HUDWindowPresenter
    participant logWindow as logWindow: NSWindow

    app->>appDelegate: instantiate AppDelegate
    appDelegate->>activityLog: eager let init ActivityLogStore()
    appDelegate->>hudVisibilityState: eager let init HUDVisibilityState()
    appDelegate->>hudTestingState: eager let init HUDTestingState()
    appDelegate->>hudMessages: eager let init HUDMessageBus()
    appDelegate->>hudStore: lazy var not initialized yet
    appDelegate->>hudPresenter: lazy var not initialized yet
    appDelegate->>swiftBridge: lazy var not initialized yet

    app->>appDelegate: applicationDidFinishLaunching
    appDelegate->>activityLog: record launch diagnostic
    appDelegate->>swiftBridge: first access lazy swiftBridge
    appDelegate->>timerListener: init TimerHUDInputListener(hudVisibilityState, hudTestingState)
    appDelegate->>swiftBridge: init SwiftBridge(activityLog, listeners, eventReceiver, snapshotReceiver, keyboard predicate)
    swiftBridge->>cBridge: stored let init CTrackpadBridge()
    swiftBridge->>listenerPipeline: stored let init ListenerPipeline(listeners)
    swiftBridge->>suppressionController: stored let init EventSuppressionController()

    appDelegate->>swiftBridge: start()
    swiftBridge->>suppressionController: start(keyboardInteractionReceiver, shouldReceiveKeyboardInteraction)
    suppressionController->>suppressionController: request missing Input Monitoring / Accessibility permissions once
    suppressionController->>suppressionController: start permission polling timer
    suppressionController->>suppressionController: install CoreGraphics event tap if permitted
    swiftBridge->>cBridge: start(snapshotHandler: receive(_:))
    cBridge->>cBridge: TXMTLoad()
    cBridge->>cBridge: TXMTStart(callback)
    swiftBridge->>activityLog: set backend status

    appDelegate->>menu: configureMenuBar()

    appDelegate->>hudPresenter: first access lazy hudPresenter
    appDelegate->>hudStore: first access lazy hudStore\ninit HUDStore(visibilityState)
    hudPresenter->>hudPresenter: init HUDWindowPresenter(hudStore, hudMessages, definitions, interactionReceiver)
    appDelegate->>hudPresenter: start()
    hudPresenter->>hudStore: subscribe to $activeHUDs
    hudPresenter->>hudPresenter: syncWindows(activeHUDs: current set)

    appDelegate->>logWindow: openLiveLog()\ncreate live-log NSWindow if nil
```

## Trackpad Snapshot Lifecycle

```mermaid
sequenceDiagram
    participant C as driftMultitouch C callback
    participant CBridge as CTrackpadBridge
    participant Bridge as SwiftBridge
    participant Pipeline as ListenerPipeline
    participant Timer as TimerHUDInputListener
    participant Suppression as EventSuppressionController
    participant Main as MainActor task
    participant Store as HUDStore
    participant Delegate as AppDelegate

    C->>CBridge: TXMTTrackpadSnapshot pointer
    CBridge->>CBridge: copy contacts into TrackpadSnapshot
    CBridge->>Bridge: receive(.trackpadSnapshot(snapshot))
    Bridge->>Bridge: lock processingLock
    Bridge->>Pipeline: process(interaction)
    Pipeline->>Timer: onInteraction(.trackpadSnapshot)
    Timer-->>Pipeline: ListenerDecision(events, suppressions, claimInteraction)
    Pipeline-->>Bridge: ListenerPipelineResult
    Bridge->>Suppression: update(persistent suppressions)
    Bridge->>Bridge: unlock processingLock
    Bridge->>Main: Task { @MainActor ... }
    Main->>Store: updateTrackpad(snapshot)
    Main->>Delegate: result.events.forEach(eventReceiver)
```

Key details:

- Listener processing is synchronous under `SwiftBridge.processingLock`.
- UI/log/event delivery happens later in a `Task { @MainActor in ... }`.
- This means listener state and suppression updates can advance before `AppDelegate.handleBackendEvent(_:)` mutates `HUDStore`.
- `HUDStore.updateTrackpad(_:)` updates layout/render state independently of HUD lifecycle.

## Listener Pipeline Claim Lifecycle

```mermaid
stateDiagram-v2
    [*] --> NoClaim
    NoClaim --> NoClaim: listener returns no claim
    NoClaim --> Claimed: listener returns claimInteraction=true
    Claimed --> Claimed: non-ending interaction\nsent only to claimed listener
    Claimed --> NoClaim: interaction.endsCurrentClaim

    NoClaim --> Stopped: listener returns stopPropagation=true
    Stopped --> NoClaim: next interaction

    state Claimed {
        [*] --> OwnerOnly
        OwnerOnly: claimedListenerIndex is set
        OwnerOnly: other possible/progressing listeners are cancelled
        OwnerOnly: cancelled listeners still receive reset snapshots
    }
```

`Interaction.endsCurrentClaim` currently returns `true` for:

- `TrackpadSnapshot` with phase `.ended`
- `.clickOutside`
- Escape key via `.keyboardPress`

## Timer HUD Listener State Machine

```mermaid
stateDiagram-v2
    [*] --> waiting

    waiting --> possible: 2 fingers\nstart in bottom-left region
    waiting --> progressing: HUDTestingState active\n2 fingers and phase != ended
    waiting --> waiting: unrelated input

    possible --> possible: movement below activation threshold\nreturns scroll + escape suppressions
    possible --> progressing: upward dominant movement >= threshold\nemits timerHUDActivationRequested\nclaims interaction
    possible --> waiting: phase ended\nsets cancelled then reset()
    possible --> cancelled: rule broken
    possible --> waiting: Escape\nsets cancelled then reset()

    progressing --> progressing: classifies scroll/pinch\nemits timerHUDInput(input)\nclaims interaction
    progressing --> progressing: movement below input threshold\nclaims interaction
    progressing --> waiting: testing source but HUDTestingState inactive\nreset()
    progressing --> waiting: Escape\nreset() + emits timerHUDCloseRequested
    progressing --> waiting: clickOutside\nreset() + emits timerHUDCloseRequested

    cancelled --> waiting: ended snapshot
    ended --> waiting: ended snapshot
```

The listener has these internal fields:

- `gestureStatus`: `.waiting`, `.possible`, `.progressing`, `.cancelled`, `.ended`
- `pendingCenter`: previous normalized contact center used for deltas
- `pendingScale`: previous scale used for pinch deltas
- `activationSource`: `.activationGesture` or `.testingHUD`
- `hudVisibilityState`: mirror used to decide whether Escape should close a visible HUD
- `hudTestingState`: testing-only marker used to start input without the real bottom-left activation gesture

## Real Timer HUD Activation Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant CBridge as CTrackpadBridge
    participant Bridge as SwiftBridge
    participant Pipeline as ListenerPipeline
    participant Listener as TimerHUDInputListener
    participant Suppression as EventSuppressionController
    participant Delegate as AppDelegate
    participant Store as HUDStore
    participant Visibility as HUDVisibilityState
    participant Presenter as HUDWindowPresenter
    participant Window as NSPanel + NSHostingView
    participant View as TimerHUDView

    User->>CBridge: two-finger gesture starts bottom-left
    CBridge->>Bridge: TrackpadSnapshot(.began/.changed)
    Bridge->>Pipeline: process(snapshot)
    Pipeline->>Listener: waiting -> possible
    Listener-->>Pipeline: no event yet

    User->>CBridge: upward dominant movement crosses threshold
    CBridge->>Bridge: TrackpadSnapshot(.changed)
    Bridge->>Pipeline: process(snapshot)
    Pipeline->>Listener: possible -> progressing
    Listener-->>Pipeline: claimInteraction + suppress scroll/escape + timerHUDActivationRequested
    Bridge->>Suppression: update(scroll + escape suppressions)
    Bridge->>Delegate: later on MainActor, handleBackendEvent(timerHUDActivationRequested)
    Delegate->>Testing: deactivate(timer)
    Delegate->>Store: activate(timer)
    Store->>Visibility: setActiveHUDs([timer])
    Delegate->>Delegate: perform activation haptic
    Store-->>Presenter: $activeHUDs publishes [timer]
    Presenter->>Presenter: makeWindow(TimerHUDDefinition)
    Presenter->>Window: create borderless nonactivating NSPanel
    Presenter->>View: inject HUDStore + HUDMessageBus
    Presenter->>Window: orderFrontRegardless()
    Presenter->>Presenter: start mouse/key monitors
```

Important timing:

- The listener claims the gesture and suppression is updated synchronously.
- `HUDStore.activate(timer)` happens asynchronously later on the main actor.
- `HUDVisibilityState` only changes when `HUDStore.activate(_:)` runs.
- The window appears only after `HUDWindowPresenter` observes `HUDStore.$activeHUDs`.

## Timer HUD Input And Haptic Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant Bridge as SwiftBridge
    participant Listener as TimerHUDInputListener
    participant Delegate as AppDelegate
    participant Bus as HUDMessageBus
    participant View as TimerHUDView
    participant Haptics as NSHapticFeedbackManager

    User->>Bridge: further two-finger movement while listener is progressing
    Bridge->>Listener: onInteraction(.trackpadSnapshot)
    Listener->>Listener: classifyInput(from pendingCenter/pendingScale)
    Listener-->>Bridge: timerHUDInput(input) + claim + suppressions
    Bridge->>Delegate: later on MainActor, handleBackendEvent(timerHUDInput)
    Delegate->>Bus: send(.timerInput(input), to: timer)
    Bus-->>View: .onReceive(hudMessages.messages)
    View->>View: receiveHUDMessage(targetedMessage)
    View->>View: guard hudID == TimerHUDDefinition.hudID
    View->>View: receiveTimerHUDInput(input)
    View->>Haptics: perform(.levelChange)
    View->>View: animate duration state change
```

This means Timer HUD adjustment haptics are frontend-owned in the current implementation. The backend/listener emits `timerHUDInput`, but the haptic that repeats during scrolling lives inside `TimerHUDView.receiveTimerHUDInput(_:)`.

## Menu Testing HUD Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant Menu as Menu Bar
    participant Delegate as AppDelegate
    participant Testing as HUDTestingState
    participant Store as HUDStore
    participant Visibility as HUDVisibilityState
    participant Presenter as HUDWindowPresenter
    participant Listener as TimerHUDInputListener

    User->>Menu: Show Timer HUD
    Menu->>Delegate: toggleTimerHUD()
    Delegate->>Testing: activate(timer)
    Delegate->>Store: activate(timer)
    Store->>Visibility: setActiveHUDs([timer])
    Store-->>Presenter: $activeHUDs publishes [timer]
    Presenter->>Presenter: create Timer HUD panel

    User->>Listener: two-finger trackpad input anywhere
    Listener->>Testing: isActive(timer)?
    Testing-->>Listener: true
    Listener->>Listener: waiting -> progressing\nactivationSource = testingHUD
    Listener-->>Delegate: later timerHUDInput events
```

Menu close is similarly direct:

```mermaid
sequenceDiagram
    participant User
    participant Delegate as AppDelegate
    participant Testing as HUDTestingState
    participant Store as HUDStore
    participant Visibility as HUDVisibilityState
    participant Presenter as HUDWindowPresenter

    User->>Delegate: toggleTimerHUD() while active
    Delegate->>Testing: deactivate(timer)
    Delegate->>Store: deactivate(timer)
    Store->>Visibility: setActiveHUDs([])
    Store-->>Presenter: $activeHUDs publishes []
    Presenter->>Presenter: closeWindow(timer)
    Presenter->>Presenter: stop monitors if no windows remain
```

This path bypasses `BackendEvent` entirely. It is a test-only injection that directly mutates HUD lifecycle state from `AppDelegate`.

## Click Outside Close Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant Presenter as HUDWindowPresenter
    participant Bridge as SwiftBridge
    participant Pipeline as ListenerPipeline
    participant Listener as TimerHUDInputListener
    participant Suppression as EventSuppressionController
    participant Delegate as AppDelegate
    participant Testing as HUDTestingState
    participant Store as HUDStore
    participant Visibility as HUDVisibilityState
    participant Window as NSPanel / Hosting View

    User->>Presenter: mouse down outside Timer HUD window
    Presenter->>Presenter: handleMouseDown(at:)
    Presenter->>Bridge: receive(.clickOutside(timer))
    Bridge->>Pipeline: process(clickOutside)
    Pipeline->>Listener: onClickOutside(timer)
    Listener->>Testing: deactivate(timer)
    Listener->>Listener: reset()\ngestureStatus = waiting
    Listener-->>Pipeline: emittedEvents = [timerHUDCloseRequested]
    Pipeline->>Pipeline: clickOutside ends current claim\nclearClaim()
    Pipeline-->>Bridge: result
    Bridge->>Suppression: update([])
    Bridge->>Delegate: later on MainActor, handleBackendEvent(timerHUDCloseRequested)
    Delegate->>Testing: deactivate(timer)
    Delegate->>Store: deactivate(timer)
    Store->>Visibility: setActiveHUDs([])
    Store-->>Presenter: $activeHUDs publishes []
    Presenter->>Window: orderOut(nil)
    Presenter->>Window: contentView = nil
    Presenter->>Window: close()
```

Current behavior to notice:

- `TimerHUDInputListener.onClickOutside(_:)` resets to `.waiting` before the HUD has been closed by `AppDelegate` and `HUDWindowPresenter`.
- `HUDTestingState` is deactivated both in the listener and again in `AppDelegate.handleBackendEvent(_:)`.
- `HUDVisibilityState` is not changed by the listener; it changes only when `HUDStore.deactivate(_:)` runs later.
- `clickOutside` ends the pipeline claim immediately.

## Escape Close Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant EventTap as EventSuppressionController
    participant Presenter as HUDWindowPresenter
    participant Bridge as SwiftBridge
    participant Listener as TimerHUDInputListener
    participant Delegate as AppDelegate
    participant Store as HUDStore
    participant Presenter2 as HUDWindowPresenter

    User->>EventTap: Escape key down
    EventTap->>EventTap: if key should be forwarded, build KeyboardPressInteraction
    EventTap->>Bridge: receive(.keyboardPress(escape))
    Bridge->>Listener: onKeyboardPress(escape)
    Listener->>Listener: reset/cancel depending on gestureStatus
    Listener-->>Bridge: suppress Escape; maybe emit timerHUDCloseRequested
    Bridge-->>EventTap: suppressions
    EventTap->>EventTap: suppress keyDown and matching keyUp when requested
    Bridge->>Delegate: later handleBackendEvent(timerHUDCloseRequested)
    Delegate->>Store: deactivate(timer)
    Store-->>Presenter2: close Timer HUD window

    User->>Presenter: local/global key monitor may also see keyDown
    Presenter->>Bridge: receive(.keyboardPress(escape))
```

Escape can enter the listener through two routes:

- `EventSuppressionController` global event tap, gated by `shouldReceiveKeyboardInteraction`.
- `HUDWindowPresenter` local/global keyboard monitors while HUD windows are visible.

The listener suppresses Escape when it handles it. In local monitor code, Escape returns `nil` immediately for local key events.

## HUD Rendering Lifecycle

```mermaid
sequenceDiagram
    participant Store as HUDStore
    participant Presenter as HUDWindowPresenter
    participant Def as AnyHUDDefinition / TimerHUDDefinition
    participant Panel as NSPanel
    participant Host as NSHostingView
    participant View as TimerHUDView
    participant Bus as HUDMessageBus

    Store-->>Presenter: activeHUDs contains timer
    Presenter->>Def: position(in: HUDLayoutContext)
    Presenter->>Def: content(context: HUDContext)
    Def-->>Presenter: TimerHUDView(screenSize: size)
    Presenter->>View: inject environmentObject(HUDStore)
    Presenter->>View: inject environmentObject(HUDMessageBus)
    Presenter->>Host: NSHostingView(rootView: rootView)
    Presenter->>Panel: contentView = hostingView
    Presenter->>Panel: orderFrontRegardless()
    View->>View: onAppear animation sets loaded = true
    View->>Bus: onReceive(messages)
```

Closing is the inverse:

```mermaid
sequenceDiagram
    participant Store as HUDStore
    participant Presenter as HUDWindowPresenter
    participant Panel as NSPanel

    Store-->>Presenter: activeHUDs no longer contains timer
    Presenter->>Presenter: windows.removeValue(forKey: timer)
    Presenter->>Panel: orderOut(nil)
    Presenter->>Panel: contentView = nil
    Presenter->>Panel: close()
    Presenter->>Presenter: stop monitors if windows is empty
```

`contentView = nil` is important because `NSPanel.isReleasedWhenClosed` is `false`. Without detaching the hosting view, the SwiftUI view tree and its `.onReceive` subscription can survive the visible window close.

## Event Suppression Lifecycle

```mermaid
sequenceDiagram
    participant Listener as ListenerPipeline result
    participant Bridge as SwiftBridge
    participant Suppression as EventSuppressionController
    participant Tap as CoreGraphics Event Tap
    participant App as Foreground App

    Listener-->>Bridge: suppressions = scroll/key/press requests
    Bridge->>Suppression: update(suppressions)
    Tap->>Suppression: scrollWheel / mouse / key event
    Suppression->>Suppression: filter(type:event:)
    alt matching scroll suppression
        Suppression->>Suppression: zero requested axis fields
        Suppression-->>App: modified event or nil if both axes are zero
    else matching press suppression
        Suppression->>Suppression: suppress down and matching up
        Suppression-->>App: nil
    else matching key suppression
        Suppression->>Suppression: suppress down and matching up
        Suppression-->>App: nil
    else no match
        Suppression-->>App: original event
    end
```

Suppression state is replaced after every processed interaction. For keyboard interactions, `SwiftBridge.persistentSuppressions(from:for:)` removes one-shot key suppressions after processing the key press while preserving non-key suppressions.

## App Shutdown

```mermaid
sequenceDiagram
    participant App as NSApplication
    participant Delegate as AppDelegate
    participant Bridge as SwiftBridge
    participant Suppression as EventSuppressionController
    participant CBridge as CTrackpadBridge

    App->>Delegate: applicationWillTerminate
    Delegate->>Bridge: stop()
    Bridge->>Bridge: lock processingLock
    Bridge->>Suppression: update([])
    Bridge->>Bridge: unlock processingLock
    Bridge->>CBridge: stop()
    CBridge->>CBridge: TXMTStop()
    Bridge->>Suppression: stop()
    Suppression->>Suppression: stop permission checks
    Suppression->>Suppression: remove event tap + clear callbacks
```

## Current Race-Prone Boundaries

```mermaid
flowchart LR
    Listener["TimerHUDInputListener\nSynchronous gesture state"] -->|emits BackendEvent| Bridge["SwiftBridge"]
    Bridge -->|Task @MainActor later| Delegate["AppDelegate.handleBackendEvent"]
    Delegate -->|mutates| Store["HUDStore.activeHUDs"]
    Store -->|sync mirror| Visibility["HUDVisibilityState"]
    Store -->|publishes| Presenter["HUDWindowPresenter"]
    Presenter -->|tears down later| View["TimerHUDView .onReceive"]
    Delegate -->|sends input| Bus["HUDMessageBus"]
    Bus -->|message delivery| View

    Testing["HUDTestingState"] -.direct menu mutation.-> Listener
    Testing -.also mutated by listener close.-> Listener
    Testing -.also mutated by AppDelegate close.-> Delegate
```

The main lifecycle tension is that listener state, suppression state, HUD visibility state, and SwiftUI view lifetime do not change in one synchronous ownership boundary.

Specific current split points:

- Listener close handlers emit `timerHUDCloseRequested`, but actual `HUDStore.deactivate(_:)` happens later in `AppDelegate`.
- Listener close handlers call `reset()` immediately, before presenter teardown has completed.
- `HUDVisibilityState` follows `HUDStore`, not listener intent.
- `HUDTestingState` is mutated by both the menu path and listener close path.
- Timer HUD input messages are delivered through `HUDMessageBus` to any still-subscribed `TimerHUDView`.
- Timer HUD scroll haptics happen only in `TimerHUDView.receiveTimerHUDInput(_:)`.

## File Map

```mermaid
flowchart TB
    subgraph App
        A["Sources/drift/App/AppDelegate.swift"]
        Main["Sources/drift/App/main.swift"]
    end

    subgraph Input
        B["Sources/drift/Infrastructure/Input/SwiftBridge.swift"]
        C["Sources/drift/Infrastructure/Input/CTrackpadBridge.swift"]
        D["Sources/drift/Infrastructure/Input/EventSuppressionController.swift"]
        E["Sources/drift/Infrastructure/Input/ListenerPipeline.swift"]
        F["Sources/drift/Infrastructure/Input/Listeners/TimerHUDInputListener.swift"]
    end

    subgraph Models
        G["Sources/drift/Core/Models/ListenerModels.swift"]
        H["Sources/drift/Core/Models/BackendEvent.swift"]
        I["Sources/drift/Core/Models/HUDModels.swift"]
        J["Sources/drift/Core/Models/TrackpadSnapshot.swift"]
        K["Sources/drift/Core/Models/GestureModels.swift"]
    end

    subgraph HUD
        L["Sources/drift/Features/HUD/HUDStore.swift"]
        M["Sources/drift/Features/HUD/HUDTestingSupport.swift"]
        N["Sources/drift/Features/HUD/HUDWindowPresenter.swift"]
        O["Sources/drift/Features/HUD/Timer/TimerHUDDefinition.swift"]
        P["Sources/drift/Features/HUD/Timer/TimerHUDComponents.swift"]
    end

    A --> B
    A --> L
    A --> M
    A --> N
    B --> C
    B --> D
    B --> E
    E --> F
    F --> G
    F --> H
    N --> I
    O --> I
    P --> L
```
