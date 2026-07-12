import AppKit
import SwiftUI

enum AppPreferenceKey {
    static let openLiveLogAtLaunch = "drift.openLiveLogAtLaunch"
    static let virtualTrackpadEnabled = "drift.virtualTrackpadEnabled"
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
    @ObservedObject var documents: ExcalidrawDocumentStore
    @ObservedObject var timerPreferences: TimerPreferencesStore
    @ObservedObject var pomodoroPreferences: PomodoroPreferencesStore
    @ObservedObject var customGestures: CustomGestureSettingsModel
    let timerWorker: TimerBackgroundWorker
    let setVirtualTrackpadEnabled: (Bool) -> Void

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
                GeneralSettingsPage()
            case .timer:
                TimerSettingsPage(
                    preferences: timerPreferences
                )
            case .pomodoro:
                PomodoroSettingsPage(
                    preferences: pomodoroPreferences,
                    save: { durations in
                        timerWorker.savePomodoroDurations(durations)
                    }
                )
            case .excalidraw:
                ExcalidrawSettingsPage(documents: documents)
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
    @AppStorage(AppPreferenceKey.openLiveLogAtLaunch)
    private var openLiveLogAtLaunch = true

    var body: some View {
        SettingsPageLayout(title: "General") {
            Section("Application") {
                Toggle("Open Live Log at launch", isOn: $openLiveLogAtLaunch)
            }
        }
    }
}

private struct TimerSettingsPage: View {
    @ObservedObject var preferences: TimerPreferencesStore
    @State private var defaultDuration: Int

    init(preferences: TimerPreferencesStore) {
        self.preferences = preferences
        _defaultDuration = State(initialValue: preferences.defaultDuration)
    }

    var body: some View {
        SettingsPageLayout(title: "Timer") {
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
    let save: (PomodoroDurations) -> Void
    @State private var durations: PomodoroDurations

    init(
        preferences: PomodoroPreferencesStore,
        save: @escaping (PomodoroDurations) -> Void
    ) {
        self.preferences = preferences
        self.save = save
        _durations = State(initialValue: preferences.durations)
    }

    var body: some View {
        SettingsPageLayout(title: "Pomodoro") {
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
    @State private var quickSwipeAction: ExcalidrawQuickSwipeAction

    init(documents: ExcalidrawDocumentStore) {
        self.documents = documents
        _quickSwipeAction = State(initialValue: documents.preferences.quickSwipeAction)
    }

    var body: some View {
        SettingsPageLayout(title: "Excalidraw") {
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
