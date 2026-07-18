import AppKit
import SwiftUI

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
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case customGestures
    case virtualTrackpad

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .customGestures: "Custom Gestures"
        case .virtualTrackpad: "Virtual Trackpad"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .customGestures: "hand.draw"
        case .virtualTrackpad: "rectangle.and.hand.point.up.left"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var eventSuppressionStatus: EventSuppressionStatusModel
    @ObservedObject var customGestures: CustomGestureSettingsModel
    let setVirtualTrackpadEnabled: (Bool) -> Void
    let retryEventSuppression: () -> Void

    @State private var selectedPage: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Section("Universal") { settingsLink(.general) }
                Section("Features") {
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
            case .customGestures:
                CustomGestureSettingsPage(model: customGestures)
            case .virtualTrackpad:
                VirtualTrackpadSettingsPage(setEnabled: setVirtualTrackpadEnabled)
            }
        }
        .frame(minWidth: 680, minHeight: 440)
    }

    private func settingsLink(_ page: SettingsPage) -> some View {
        Label(page.title, systemImage: page.systemImage).tag(page)
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
        Form { content }
            .formStyle(.grouped)
            .navigationTitle(title)
    }
}

private struct GeneralSettingsPage: View {
    @ObservedObject var eventSuppressionStatus: EventSuppressionStatusModel
    let retryEventSuppression: () -> Void
    @AppStorage(AppPreferenceKey.openLiveLogAtLaunch) private var openLiveLogAtLaunch = true

    var body: some View {
        SettingsPageLayout(title: "General") {
            Section("Input Suppression") {
                LabeledContent("Status") { Text(statusTitle) }
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

private struct VirtualTrackpadSettingsPage: View {
    @AppStorage(AppPreferenceKey.virtualTrackpadEnabled) private var isEnabled = false
    let setEnabled: (Bool) -> Void

    var body: some View {
        SettingsPageLayout(title: "Virtual Trackpad") {
            Section("Window") {
                Toggle("Show virtual trackpad map", isOn: $isEnabled)
                    .onChange(of: isEnabled) { setEnabled($0) }
            }
        }
    }
}
