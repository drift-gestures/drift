import AppKit
import SwiftUI

/// Main-actor presentation model for foreground-event suppression availability.
@MainActor
final class EventSuppressionStatusModel: ObservableObject {
    @Published private(set) var status: EventSuppressionStatus = .waitingForPermissions

    func update(_ status: EventSuppressionStatus) {
        self.status = status
    }
}

enum AppPreferenceKey {
    static let openLiveLogAtLaunch = "drift.openLiveLogAtLaunch"
    static let virtualTrackpadEnabled = "drift.virtualTrackpadEnabled"
    static let timerListenerEnabled = "drift.timerListenerEnabled"
    static let pomodoroListenerEnabled = "drift.pomodoroListenerEnabled"
    static let excalidrawListenerEnabled = "drift.excalidrawListenerEnabled"
}

/// Thread-safe, persisted feature gates shared by Settings and input listeners.
final class FeatureListenerState: @unchecked Sendable {
    enum Feature: CaseIterable {
        case timer
        case pomodoro
        case excalidraw

        var preferenceKey: String {
            switch self {
            case .timer: AppPreferenceKey.timerListenerEnabled
            case .pomodoro: AppPreferenceKey.pomodoroListenerEnabled
            case .excalidraw: AppPreferenceKey.excalidrawListenerEnabled
            }
        }
    }

    private let lock = NSLock()
    private var enabledFeatures: Set<Feature>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabledFeatures = Set(Feature.allCases.filter { feature in
            defaults.object(forKey: feature.preferenceKey) == nil || defaults.bool(forKey: feature.preferenceKey)
        })
    }

    func isEnabled(_ feature: Feature) -> Bool {
        lock.withLock { enabledFeatures.contains(feature) }
    }

    func setEnabled(_ enabled: Bool, for feature: Feature) {
        lock.withLock {
            if enabled {
                enabledFeatures.insert(feature)
            } else {
                enabledFeatures.remove(feature)
            }
        }
        defaults.set(enabled, forKey: feature.preferenceKey)
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case timer
    case pomodoro
    case excalidraw
    case customGestures
    case virtualTrackpad

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .timer: "Timer"
        case .pomodoro: "Pomodoro"
        case .excalidraw: "Excalidraw"
        case .customGestures: "Custom Gestures"
        case .virtualTrackpad: "Virtual Trackpad"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .timer: "timer"
        case .pomodoro: "cup.and.heat.waves"
        case .excalidraw: "pencil.and.scribble"
        case .customGestures: "hand.draw"
        case .virtualTrackpad: "rectangle.and.hand.point.up.left"
        }
    }
}

/// Menu-bar-only settings window with universal and feature-specific pages.
struct SettingsView: View {
    @ObservedObject var eventSuppressionStatus: EventSuppressionStatusModel
    @ObservedObject var documents: ExcalidrawDocumentStore
    @ObservedObject var timerPreferences: TimerPreferencesStore
    @ObservedObject var pomodoroPreferences: PomodoroPreferencesStore
    @ObservedObject var customGestures: CustomGestureSettingsModel
    let timerWorker: TimerBackgroundWorker
    let setTimerListenerEnabled: (Bool) -> Void
    let setPomodoroListenerEnabled: (Bool) -> Void
    let setExcalidrawListenerEnabled: (Bool) -> Void
    let setVirtualTrackpadEnabled: (Bool) -> Void
    let retryEventSuppression: () -> Void

    @State private var selectedPage: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Section("Universal") {
                    settingsLink(.general)
                }
                Section("Features") {
                    settingsLink(.timer)
                    settingsLink(.pomodoro)
                    settingsLink(.excalidraw)
                    settingsLink(.customGestures)
                    settingsLink(.virtualTrackpad)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            switch selectedPage ?? .general {
            case .general:
                GeneralSettingsPage(
                    eventSuppressionStatus: eventSuppressionStatus,
                    retryEventSuppression: retryEventSuppression
                )
            case .timer:
                TimerSettingsPage(
                    preferences: timerPreferences,
                    setListenerEnabled: setTimerListenerEnabled
                )
            case .pomodoro:
                PomodoroSettingsPage(
                    preferences: pomodoroPreferences,
                    setListenerEnabled: setPomodoroListenerEnabled,
                    save: { durations in
                        timerWorker.savePomodoroDurations(durations)
                    }
                )
            case .excalidraw:
                ExcalidrawSettingsPage(
                    documents: documents,
                    setListenerEnabled: setExcalidrawListenerEnabled
                )
            case .customGestures:
                CustomGestureSettingsPage(model: customGestures)
            case .virtualTrackpad:
                VirtualTrackpadSettingsPage(setEnabled: setVirtualTrackpadEnabled)
            }
        }
        .frame(minWidth: 680, minHeight: 440)
    }

    private func settingsLink(_ page: SettingsPage) -> some View {
        Label(page.title, systemImage: page.systemImage)
            .tag(page)
    }
}

private struct VirtualTrackpadSettingsPage: View {
    @AppStorage(AppPreferenceKey.virtualTrackpadEnabled)
    private var isEnabled = false
    let setEnabled: (Bool) -> Void

    var body: some View {
        SettingsPageLayout(title: "Virtual Trackpad") {
            Section("Window") {
                Toggle("Show virtual trackpad map", isOn: $isEnabled)
                    .onChange(of: isEnabled) { enabled in
                        setEnabled(enabled)
                    }
            }
            Section {
                Text("Displays each active finger in a different color with a live movement trail.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsPageLayout<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}

private struct GeneralSettingsPage: View {
    @ObservedObject var eventSuppressionStatus: EventSuppressionStatusModel
    let retryEventSuppression: () -> Void
    @AppStorage(AppPreferenceKey.openLiveLogAtLaunch)
    private var openLiveLogAtLaunch = true

    var body: some View {
        SettingsPageLayout(title: "General") {
            Section("Input Suppression") {
                LabeledContent("Status") {
                    Text(statusTitle)
                        .foregroundStyle(
                            eventSuppressionStatus.status == .disabled
                                ? Color.orange
                                : Color.primary
                        )
                }
                if eventSuppressionStatus.status == .disabled {
                    Button("Retry", action: retryEventSuppression)
                }
            }
            Section("Application") {
                Toggle("Open Live Log at launch", isOn: $openLiveLogAtLaunch)
            }
        }
    }

    private var statusTitle: String {
        switch eventSuppressionStatus.status {
        case .waitingForPermissions: "Waiting for permissions"
        case .available: "Available"
        case .disabled: "Disabled"
        }
    }
}

private struct TimerSettingsPage: View {
    @ObservedObject var preferences: TimerPreferencesStore
    @AppStorage(AppPreferenceKey.timerListenerEnabled)
    private var isListenerEnabled = true
    let setListenerEnabled: (Bool) -> Void
    @State private var defaultDuration: Int

    init(preferences: TimerPreferencesStore, setListenerEnabled: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.setListenerEnabled = setListenerEnabled
        _defaultDuration = State(initialValue: preferences.defaultDuration)
    }

    var body: some View {
        SettingsPageLayout(title: "Timer") {
            Section("Feature") {
                Toggle("Enable Timer gesture", isOn: $isListenerEnabled)
                    .onChange(of: isListenerEnabled) { _, enabled in
                        setListenerEnabled(enabled)
                    }
            }
            Section("Defaults") {
                Stepper(
                    "Default duration: \(defaultDuration) min",
                    value: $defaultDuration,
                    in: TimerHUDDurationFormatter.minimumMinutes...TimerHUDDurationFormatter.maximumMinutes
                )
                .onChange(of: defaultDuration) { _, duration in
                    preferences.saveDefaultDuration(duration)
                }
            }
        }
    }
}

private struct PomodoroSettingsPage: View {
    @ObservedObject var preferences: PomodoroPreferencesStore
    @AppStorage(AppPreferenceKey.pomodoroListenerEnabled)
    private var isListenerEnabled = true
    let setListenerEnabled: (Bool) -> Void
    let save: (PomodoroDurations) -> Void
    @State private var durations: PomodoroDurations

    init(
        preferences: PomodoroPreferencesStore,
        setListenerEnabled: @escaping (Bool) -> Void,
        save: @escaping (PomodoroDurations) -> Void
    ) {
        self.preferences = preferences
        self.setListenerEnabled = setListenerEnabled
        self.save = save
        _durations = State(initialValue: preferences.durations)
    }

    var body: some View {
        SettingsPageLayout(title: "Pomodoro") {
            Section("Feature") {
                Toggle("Enable Pomodoro gesture", isOn: $isListenerEnabled)
                    .onChange(of: isListenerEnabled) { _, enabled in
                        setListenerEnabled(enabled)
                    }
            }
            Section("Durations") {
                ForEach(PomodoroDurationField.allCases) { field in
                    Stepper(
                        "\(field.title): \(durations[field]) min",
                        value: Binding(
                            get: { durations[field] },
                            set: { value in
                                durations[field] = value
                            }
                        ),
                        in: TimerHUDDurationFormatter.minimumMinutes...TimerHUDDurationFormatter.maximumMinutes
                    )
                }
            }
        }
        .onChange(of: durations) { _, durations in
            save(durations)
        }
    }
}

private struct ExcalidrawSettingsPage: View {
    @ObservedObject var documents: ExcalidrawDocumentStore
    @AppStorage(AppPreferenceKey.excalidrawListenerEnabled)
    private var isListenerEnabled = true
    let setListenerEnabled: (Bool) -> Void
    @State private var quickSwipeAction: ExcalidrawQuickSwipeAction

    init(documents: ExcalidrawDocumentStore, setListenerEnabled: @escaping (Bool) -> Void) {
        self.documents = documents
        self.setListenerEnabled = setListenerEnabled
        _quickSwipeAction = State(initialValue: documents.preferences.quickSwipeAction)
    }

    var body: some View {
        SettingsPageLayout(title: "Excalidraw") {
            Section("Feature") {
                Toggle("Enable Excalidraw gesture", isOn: $isListenerEnabled)
                    .onChange(of: isListenerEnabled) { _, enabled in
                        setListenerEnabled(enabled)
                    }
            }
            Section("Quick Swipe") {
                Picker(
                    "Action",
                    selection: $quickSwipeAction
                ) {
                    Text("Open Last Draft").tag(ExcalidrawQuickSwipeAction.openLastDraft)
                    Text("Create New").tag(ExcalidrawQuickSwipeAction.createNew)
                    Text("Open Last File").tag(ExcalidrawQuickSwipeAction.openLastFile)
                }
                .onChange(of: quickSwipeAction) { _, action in
                    saveQuickSwipeAction(action)
                }
            }

            Section("Drawings") {
                LabeledContent("Folder") {
                    Text(documents.preferences.drawingsFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Choose Folder…", action: chooseFolder)
            }
        }
    }

    private func saveQuickSwipeAction(_ action: ExcalidrawQuickSwipeAction) {
        try? documents.savePreferences(
            drawingsFolder: documents.preferences.drawingsFolder,
            quickSwipeAction: action
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = documents.preferences.drawingsFolder
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        try? documents.savePreferences(
            drawingsFolder: folder,
            quickSwipeAction: documents.preferences.quickSwipeAction
        )
    }
}
