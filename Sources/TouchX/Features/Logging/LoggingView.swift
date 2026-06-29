import SwiftUI

/// Live testing console for raw snapshots, listener state transitions, and semantic backend events.
struct LoggingView: View {
    @ObservedObject var activityLog: ActivityLogStore
    @ObservedObject var hudStore: HUDStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            liveState
            Divider()
            entryList
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { activityLog.record("Live Log window opened.", category: .system) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Live Log").font(.title2.weight(.semibold))
                Text("Raw frames → listeners → semantic events")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear") { activityLog.clear() }
        }
        .padding()
    }

    private var liveState: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Input backend", value: activityLog.activeBackendName.rawValue)
            Text(activityLog.backendMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                LabeledContent("Last event", value: activityLog.lastInputDescription)
                LabeledContent("Active HUDs", value: "\(hudStore.activeHUDs.count)")
            }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                LabeledContent("Frame", value: activityLog.latestSnapshot.map { "\($0.frame)" } ?? "—")
                LabeledContent("Phase", value: activityLog.latestSnapshot?.phase.rawValue ?? "idle")
                LabeledContent("Contacts", value: activityLog.latestSnapshot.map { "\($0.fingerCount)" } ?? "0")
            }
        }
        .font(.callout)
        .padding()
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if activityLog.entries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No activity yet").font(.headline)
                            Text("Use the trackpad or mouse to start logging input.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 72)
                    } else {
                        ForEach(activityLog.entries) { entry in
                            LogEntryRow(entry: entry).id(entry.id)
                            Divider()
                        }
                    }
                }
            }
            .onReceive(activityLog.$entries) { entries in
                guard let newest = entries.first else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newest.id, anchor: .top)
                }
            }
        }
    }
}

private struct LogEntryRow: View {
    let entry: ActivityLogStore.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.timestamp, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(entry.category.rawValue.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(categoryColor)
                .frame(width: 58, alignment: .leading)
            Text(entry.message).font(.callout).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var categoryColor: Color {
        switch entry.category {
        case .system: .secondary
        case .input: .blue
        case .listener: .orange
        case .action: .purple
        }
    }
}
