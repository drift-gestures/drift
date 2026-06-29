# TouchX codebase map

Solid arrows show active runtime flow. Dotted arrows show type/build dependencies or code that is available but currently unregistered.

```mermaid
flowchart LR
    subgraph macosLayer ["macOS and process entry"]
        multitouchFramework["MultitouchSupport.framework: private API producing raw TXMTFinger arrays"]
        eventSystem["Core Graphics event system: foreground scroll and mouse events"]
        pasteboard["NSPasteboard: clipboard source used only if Quick Actions is activated"]
        mainFile["App/main.swift: creates NSApplication, installs AppDelegate, runs accessory process"]
    end

    subgraph cLayer ["C trackpad boundary"]
        cHeader["TouchXMultitouch.h: stable TXMTContact and TXMTTrackpadSnapshot C API"]
        cListener["TouchXMultitouch.c: loads private symbols, receives TXMTFinger arrays, derives center scale rotation, emits snapshots"]
        bridgingHeader["TouchX-Bridging-Header.h: exposes the C API to the native Xcode Swift target"]
    end

    subgraph appLayer ["Application composition"]
        appDelegate["AppDelegate.swift: owns stores and SwiftBridge, registers listeners as an empty ordered array, creates menu and log window"]
        infoPlist["Info.plist: native app identity and runtime metadata"]
        packageFile["Package.swift and Xcode project: compile Swift app plus TouchXMultitouch C target"]
    end

    subgraph coreModels ["Core models"]
        snapshotModels["TrackpadSnapshot.swift: ContactVector, FingerContact, phase, snapshot, latest TrackpadState"]
        listenerModels["ListenerModels.swift: Listener protocol, GestureStatus, ListenerDecision, suppression axis and direction"]
        backendEvents["BackendEvent.swift: empty semantic event enum until concrete listeners are added"]
        hudModels["HUDModels.swift: HUDID, HUDState, layout context, HUD context, HudDefinition protocol"]
        backendNames["GestureModels.swift: active and inactive backend display names"]
    end

    subgraph inputInfrastructure ["Infrastructure/Input"]
        cBridge["CTrackpadBridge.swift: starts C listener and immediately copies borrowed C snapshots into Swift values"]
        swiftBridge["SwiftBridge.swift: serial orchestration of snapshots, listeners, suppression, logging, and frontend delivery"]
        listenerPipeline["ListenerPipeline.swift: invokes listeners in order, stops propagation, arbitrates claims, keeps cancelled listeners receiving reset frames"]
        suppressor["EventSuppressionController.swift: CGEvent tap that removes only requested scroll axes and directions or consumes requested presses"]
        listenerFolder["Listeners folder: intentionally empty; future gesture listeners each receive their own file"]
    end

    subgraph frontendState ["Frontend state and testing UI"]
        activityLog["ActivityLogStore.swift: main-actor in-memory log, 300-entry cap, sampled snapshots, listener status and claim transitions"]
        loggingView["LoggingView.swift: displays backend health, latest frame phase and contacts, active HUD count, and chronological log rows"]
        hudStore["HUDStore.swift: global active HUD IDs, optional custom states, and latest trackpad state"]
        logWindow["NSWindow plus NSHostingController: live testing window created by AppDelegate"]
    end

    subgraph dormantQuickActions ["Quick Actions frontend components: compiled but currently unregistered"]
        quickModels["QuickActionModels.swift: sections, items, directional layout types, and masonry placement models"]
        clipboardStore["ClipboardHistoryStore.swift: optional 0.5 second pasteboard polling and twelve-item in-memory history"]
        quickSurface["QuickActionSurface.swift: section switcher and progress indicator composition"]
        clipboardView["ClipboardHistoryView.swift: mirrored masonry cards and copy-back interaction"]
        emojiView["EmojiPickerView.swift: mirrored emoji grid prototype"]
        emptyHudFolder["QuickActions/HUDs folder: empty; no concrete Quick Actions HUD exists"]
    end

    subgraph verification ["Build and verification"]
        tests["ListenerArchitectureTests.swift: verifies registration order, stop propagation, claim cancellation, and cancelled-listener reset delivery"]
        xcodeProject["TouchX.xcodeproj: native macOS app target and source membership"]
    end

    multitouchFramework -->|"Raw contact frame"| cListener
    cHeader -.->|"Declares structs and callback"| cListener
    cListener -->|"Borrowed TXMTTrackpadSnapshot"| cBridge
    cBridge -->|"Owned TrackpadSnapshot"| swiftBridge

    mainFile -->|"Starts"| appDelegate
    appDelegate -->|"Starts and stops"| swiftBridge
    appDelegate -->|"Creates"| activityLog
    appDelegate -->|"Creates"| hudStore
    appDelegate -->|"Hosts"| loggingView
    loggingView -->|"Rendered inside"| logWindow
    loggingView -->|"Observes"| activityLog
    loggingView -->|"Observes"| hudStore

    swiftBridge -->|"Processes synchronously"| listenerPipeline
    listenerPipeline -->|"Current suppression set"| swiftBridge
    swiftBridge -->|"Updates event tap policy"| suppressor
    suppressor -->|"Filters requested components"| eventSystem
    swiftBridge -->|"Records snapshots and listener activity"| activityLog
    swiftBridge -->|"Updates latest trackpad state"| hudStore
    swiftBridge -.->|"Forwards emitted semantic events; none currently exist"| backendEvents

    cBridge -.->|"Constructs"| snapshotModels
    listenerPipeline -.->|"Consumes snapshot and decision types"| snapshotModels
    listenerPipeline -.->|"Uses"| listenerModels
    listenerModels -.->|"May emit"| backendEvents
    suppressor -.->|"Reads SuppressionRequest"| listenerModels
    hudStore -.->|"Stores"| hudModels
    hudStore -.->|"Stores latest"| snapshotModels
    activityLog -.->|"Displays"| backendNames
    activityLog -.->|"Samples"| snapshotModels
    listenerFolder -.->|"Future ordered registration"| listenerPipeline
    appDelegate -.->|"Currently passes listeners: []"| listenerFolder

    bridgingHeader -.->|"Xcode import path"| cBridge
    packageFile -.->|"SwiftPM module import path"| cBridge
    packageFile -.->|"Builds"| cListener
    infoPlist -.->|"Configures"| appDelegate
    xcodeProject -.->|"Builds native target"| appDelegate
    xcodeProject -.->|"Compiles C source"| cListener

    clipboardStore -.->|"Polls only when start is called"| pasteboard
    quickModels -.-> clipboardView
    quickModels -.-> emojiView
    quickModels -.-> quickSurface
    clipboardStore -.-> clipboardView
    quickSurface -.-> clipboardView
    quickSurface -.-> emojiView
    emptyHudFolder -.->|"No registration or runtime edge"| quickSurface

    tests -.-> listenerPipeline
    tests -.-> listenerModels
    tests -.-> snapshotModels

    classDef dormant fill:#f5f5f5,stroke:#888,stroke-dasharray:5 5,color:#555
    class quickModels,clipboardStore,quickSurface,clipboardView,emojiView,emptyHudFolder dormant
```

## Important current-state notes

- `AppDelegate` registers `listeners: []`, so there are no built-in gestures.
- `BackendEvent` has no cases because no listener currently emits a semantic event.
- The Quick Actions models and views still compile, but nothing creates or presents them.
- C owns snapshot reduction; Swift immediately copies borrowed C memory before processing it.
