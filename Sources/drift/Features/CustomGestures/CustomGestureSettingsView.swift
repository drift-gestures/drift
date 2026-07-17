import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CustomGestureSettingsPage: View {
    @ObservedObject var model: CustomGestureSettingsModel
    @State private var basicEditorGesture: BasicGesture?
    @State private var advancedEditorGesture: AdvancedGesture?

    var body: some View {
        Form {
            Section("Advanced activation") {
                LabeledContent("Hold while gesturing") {
                    KeyBindingRecorder(
                        mode: .modifiers,
                        value: Binding(
                            get: {
                                KeyBindingValue(
                                    keyCode: nil,
                                    modifiers: model.library.advancedActivationModifiers
                                )
                            },
                            set: { model.setActivationModifiers($0.modifiers) }
                        )
                    )
                }
                Text("While this binding is held, advanced gestures are listened to and basic gestures are paused.")
                    .foregroundStyle(.secondary)
            }

            Section("Basic gestures") {
                if model.library.basicGestures.isEmpty {
                    Text("No basic gestures yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.library.basicGestures) { gesture in
                    GestureRow(
                        name: gesture.name,
                        detail: gesture.kind.summary,
                        action: gesture.action.summary,
                        edit: { basicEditorGesture = gesture },
                        delete: { model.remove(id: gesture.id) }
                    )
                }
                Button {
                    basicEditorGesture = BasicGesture.defaultGesture
                } label: {
                    Label("Add Basic Gesture…", systemImage: "plus")
                }
            }

            Section("Advanced gestures") {
                if model.library.advancedGestures.isEmpty {
                    Text("No advanced gestures yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.library.advancedGestures) { gesture in
                    GestureRow(
                        name: gesture.name,
                        detail: "\(gesture.recordings.count) recordings · \(gesture.isPositionallyAware ? "Position aware" : "Works anywhere")",
                        action: gesture.action.summary,
                        edit: { advancedEditorGesture = gesture },
                        delete: { model.remove(id: gesture.id) }
                    )
                }
                Button {
                    advancedEditorGesture = AdvancedGesture.defaultGesture
                } label: {
                    Label("Add Advanced Gesture…", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Custom Gestures")
        .sheet(item: $basicEditorGesture) { gesture in
            BasicGestureEditor(gesture: gesture) {
                model.save($0)
                basicEditorGesture = nil
            }
        }
        .sheet(item: $advancedEditorGesture) { gesture in
            AdvancedGestureEditor(
                gesture: gesture,
                session: model.recordingSession
            ) {
                model.save($0)
                advancedEditorGesture = nil
            }
        }
    }
}

private struct GestureRow: View {
    let name: String
    let detail: String
    let action: String
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                Text("\(detail) · \(action)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Edit \(name)")
            .help("Edit \(name)")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .accessibilityLabel("Delete \(name)")
            .help("Delete \(name)")
        }
    }
}

private enum BasicGestureCategory: String, CaseIterable, Identifiable {
    case swipe = "Edge Swipe"
    case pinch = "Pinch"
    case rotate = "Rotate"
    var id: Self { self }
}

private struct BasicGestureEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var gesture: BasicGesture
    @State private var category: BasicGestureCategory
    @State private var edge: TrackpadEdge
    @State private var swipeDirection: GestureDirection
    @State private var pinchDirection: PinchDirection
    @State private var rotationDirection: RotationDirection
    let save: (BasicGesture) -> Void

    init(gesture: BasicGesture, save: @escaping (BasicGesture) -> Void) {
        _gesture = State(initialValue: gesture)
        self.save = save
        switch gesture.kind {
        case .edgeSwipe(let edge, let direction):
            _category = State(initialValue: .swipe)
            _edge = State(initialValue: edge)
            _swipeDirection = State(initialValue: direction)
            _pinchDirection = State(initialValue: .inward)
            _rotationDirection = State(initialValue: .clockwise)
        case .pinch(let direction):
            _category = State(initialValue: .pinch)
            _edge = State(initialValue: .bottom)
            _swipeDirection = State(initialValue: .up)
            _pinchDirection = State(initialValue: direction)
            _rotationDirection = State(initialValue: .clockwise)
        case .rotate(let direction):
            _category = State(initialValue: .rotate)
            _edge = State(initialValue: .bottom)
            _swipeDirection = State(initialValue: .up)
            _pinchDirection = State(initialValue: .inward)
            _rotationDirection = State(initialValue: direction)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gesture") {
                    TextField("Name", text: $gesture.name)
                    Picker("Type", selection: $category) {
                        ForEach(BasicGestureCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    gestureControls
                }
                Section("Recognition") {
                    LabeledContent("Activation threshold", value: gesture.activationThreshold.formatted(.number.precision(.fractionLength(2))))
                    Slider(value: $gesture.activationThreshold, in: resolvedKind.activationThresholdRange)
                    if category == .swipe {
                        LabeledContent("Edge proximity", value: gesture.edgeProximity.formatted(.number.precision(.fractionLength(2))))
                        Slider(value: $gesture.edgeProximity, in: 0.01...0.25)
                    }
                }
                GestureScopeEditor(
                    scopedApplicationBundleIdentifiers: $gesture.scopedApplicationBundleIdentifiers
                )
                Section("Action") {
                    GestureActionEditor(action: $gesture.action)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Basic Gesture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        gesture.kind = resolvedKind
                        save(gesture)
                    }
                    .disabled(
                        gesture.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        !gesture.action.isConfigured
                    )
                }
            }
        }
        .frame(minWidth: 680, minHeight: 440)
    }

    @ViewBuilder
    private var gestureControls: some View {
        switch category {
        case .swipe:
            Picker("Starting edge", selection: $edge) {
                Text("Top").tag(TrackpadEdge.top)
                Text("Bottom").tag(TrackpadEdge.bottom)
                Text("Left").tag(TrackpadEdge.left)
                Text("Right").tag(TrackpadEdge.right)
            }
            Picker("Starting zone", selection: $gesture.edgeSegment) {
                ForEach(EdgeSegment.allCases, id: \.self) {
                    Text($0.title(for: edge)).tag($0)
                }
            }
            Picker("Direction", selection: $swipeDirection) {
                Text("Up").tag(GestureDirection.up)
                Text("Down").tag(GestureDirection.down)
                Text("Left").tag(GestureDirection.left)
                Text("Right").tag(GestureDirection.right)
            }
            Text("Edge swipes use exactly two fingers.")
                .foregroundStyle(.secondary)
        case .pinch:
            Picker("Direction", selection: $pinchDirection) {
                Text("Inward").tag(PinchDirection.inward)
                Text("Outward").tag(PinchDirection.outward)
            }
        case .rotate:
            Picker("Direction", selection: $rotationDirection) {
                Text("Clockwise").tag(RotationDirection.clockwise)
                Text("Counterclockwise").tag(RotationDirection.counterclockwise)
            }
        }
    }

    private var resolvedKind: BasicGestureKind {
        switch category {
        case .swipe: .edgeSwipe(edge: edge, direction: swipeDirection)
        case .pinch: .pinch(direction: pinchDirection)
        case .rotate: .rotate(direction: rotationDirection)
        }
    }
}

private enum AdvancedSensitivity: String, CaseIterable, Identifiable {
    case loose = "Loose"
    case balanced = "Balanced"
    case strict = "Strict"
    var id: Self { self }

    var threshold: Double {
        switch self {
        case .loose: 0.20
        case .balanced: 0.12
        case .strict: 0.07
        }
    }

    static func nearest(to threshold: Double) -> Self {
        allCases.min { abs($0.threshold - threshold) < abs($1.threshold - threshold) } ?? .balanced
    }
}

private struct AdvancedGestureEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var gesture: AdvancedGesture
    @State private var sensitivity: AdvancedSensitivity
    @State private var showsRecorder = false
    @State private var showsTest = false
    @ObservedObject var session: CustomGestureRecordingSession
    let save: (AdvancedGesture) -> Void

    init(
        gesture: AdvancedGesture,
        session: CustomGestureRecordingSession,
        save: @escaping (AdvancedGesture) -> Void
    ) {
        _gesture = State(initialValue: gesture)
        _sensitivity = State(initialValue: .nearest(to: gesture.acceptanceThreshold))
        self.session = session
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gesture") {
                    TextField("Name", text: $gesture.name)
                    Toggle("Positionally aware", isOn: $gesture.isPositionallyAware)
                    Text(gesture.isPositionallyAware
                         ? "The gesture must be performed in the recorded trackpad area."
                         : "The gesture can be performed anywhere on the trackpad.")
                        .foregroundStyle(.secondary)
                }
                Section("Recordings") {
                    if gesture.recordings.isEmpty {
                        LabeledContent("Saved examples", value: "\(gesture.recordings.count) of 5")
                        Button {
                            showsRecorder = true
                        } label: {
                            Label("Record Examples…", systemImage: "record.circle")
                        }
                    } else {
                        LabeledContent("Saved examples") {
                            HStack {
                                Text("\(gesture.recordings.count) of 5")
                                Button {
                                    showsRecorder = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Manage recordings")
                                .help("Manage recordings")
                            }
                        }
                    }
                    Text("Three examples are required. Two additional examples are optional.")
                        .foregroundStyle(.secondary)
                }
                Section("Matching") {
                    Picker("Sensitivity", selection: $sensitivity) {
                        ForEach(AdvancedSensitivity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                GestureScopeEditor(
                    scopedApplicationBundleIdentifiers: $gesture.scopedApplicationBundleIdentifiers
                )
                Section("Action") {
                    GestureActionEditor(action: $gesture.action)
                    Button("Test Gesture Safely…") { showsTest = true }
                        .disabled(gesture.recordings.count < 3)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Advanced Gesture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        gesture.acceptanceThreshold = sensitivity.threshold
                        save(gesture)
                    }
                    .disabled(
                        gesture.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        gesture.recordings.count < 3 ||
                        !gesture.action.isConfigured
                    )
                }
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .onChange(of: gesture.isPositionallyAware) { _ in
            gesture.recordings.removeAll()
        }
        .sheet(isPresented: $showsRecorder) {
            AdvancedGestureRecordingSheet(
                session: session,
                positionallyAware: gesture.isPositionallyAware,
                existing: gesture.recordings,
                activationName: "the advanced activation binding"
            ) { recordings in
                gesture.recordings = recordings
                showsRecorder = false
            }
        }
        .sheet(isPresented: $showsTest) {
            AdvancedGestureTestSheet(session: session, gesture: testGesture)
        }
    }

    private var testGesture: AdvancedGesture {
        var result = gesture
        result.acceptanceThreshold = sensitivity.threshold
        return result
    }
}

private struct AdvancedGestureRecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: CustomGestureRecordingSession
    let positionallyAware: Bool
    let existing: [AdvancedGestureRecording]
    let activationName: String
    let done: ([AdvancedGestureRecording]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Record") {
                    GestureTrackpadPreview(snapshot: session.previewSnapshot, paths: session.currentPaths)
                    Text("Hold \(activationName), perform the gesture, then lift your fingers.")
                    LabeledContent("Accepted examples", value: "\(session.recordings.count) of 5")
                    if session.recordings.count < 3 {
                        Text("\(3 - session.recordings.count) more required.")
                            .foregroundStyle(.secondary)
                    } else if session.recordings.count < 5 {
                        Text("Ready to save. You may record \(5 - session.recordings.count) more optional examples.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("All five examples have been recorded.")
                            .foregroundStyle(.secondary)
                    }
                    if let message = session.rejectedTakeMessage {
                        Text(message).foregroundStyle(.red)
                    }
                }
                if !session.recordings.isEmpty {
                    Section("Examples") {
                        ForEach(session.recordings.indices, id: \.self) { index in
                            HStack {
                                Text("Example \(index + 1)")
                                Spacer()
                                Button(role: .destructive) {
                                    session.removeRecording(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Remove Example \(index + 1)")
                                .help("Remove Example \(index + 1)")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Record Gesture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        session.end()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let recordings = session.recordings
                        session.end()
                        done(recordings)
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .onAppear {
            session.beginRecording(positionallyAware: positionallyAware, existing: existing)
        }
        .onDisappear { session.end() }
    }
}

private struct AdvancedGestureTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: CustomGestureRecordingSession
    let gesture: AdvancedGesture

    var body: some View {
        NavigationStack {
            Form {
                Section("Safe test") {
                    GestureTrackpadPreview(snapshot: session.previewSnapshot, paths: session.currentPaths)
                    Text("Hold the advanced activation binding and perform \(gesture.name). The assigned action will not run.")
                    if let result = session.testResult { Text(result) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Test Gesture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        session.end()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .onAppear { session.beginTesting(gesture) }
        .onDisappear { session.end() }
    }
}

private struct GestureTrackpadPreview: View {
    let snapshot: TrackpadSnapshot?
    let paths: [Int: [CGPoint]]

    var body: some View {
        Canvas { context, size in
            let surface = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: surface, cornerRadius: 18),
                with: .color(Color(nsColor: .controlBackgroundColor))
            )
            context.stroke(
                Path(roundedRect: surface.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 18),
                with: .color(.secondary.opacity(0.45))
            )
            for path in paths.values where path.count > 1 {
                var gesturePath = Path()
                gesturePath.move(to: map(path[0], into: surface))
                for point in path.dropFirst() { gesturePath.addLine(to: map(point, into: surface)) }
                context.stroke(gesturePath, with: .color(.accentColor), lineWidth: 3)
            }
            for contact in snapshot?.contacts ?? [] {
                let point = map(
                    CGPoint(x: contact.normalizedPosition.x, y: contact.normalizedPosition.y),
                    into: surface
                )
                let rect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: rect), with: .color(.accentColor))
            }
        }
        .frame(width: 240, height: 150)
        .accessibilityLabel("Live gesture recording preview")
    }

    private func map(_ point: CGPoint, into surface: CGRect) -> CGPoint {
        CGPoint(
            x: surface.minX + min(max(point.x, 0), 1) * surface.width,
            y: surface.minY + (1 - min(max(point.y, 0), 1)) * surface.height
        )
    }
}

private enum GestureActionType: String, CaseIterable, Identifiable {
    case shortcut = "Keyboard Shortcut"
    case application = "Open Application"
    case url = "Open URL"
    case script = "Run Script"
    var id: Self { self }
}

private struct GestureScopeEditor: View {
    @Binding var scopedApplicationBundleIdentifiers: Set<String>

    var body: some View {
        Section("Scope") {
            LabeledContent(
                "Runs in",
                value: scopedApplicationBundleIdentifiers.isEmpty
                    ? "All Apps"
                    : "\(scopedApplicationBundleIdentifiers.count) selected"
            )
            ForEach(scopedApplicationBundleIdentifiers.sorted(), id: \.self) { bundleIdentifier in
                HStack {
                    Text(applicationName(bundleIdentifier))
                    Spacer()
                    Button(role: .destructive) {
                        scopedApplicationBundleIdentifiers.remove(bundleIdentifier)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Remove \(applicationName(bundleIdentifier))")
                    .help("Remove \(applicationName(bundleIdentifier))")
                }
            }
            Button {
                scopedApplicationBundleIdentifiers.formUnion(
                    chooseApplicationBundleIdentifiers(allowsMultipleSelection: true)
                )
            } label: {
                Label("Add Application…", systemImage: "plus")
            }
            if !scopedApplicationBundleIdentifiers.isEmpty {
                Button("Use All Apps") {
                    scopedApplicationBundleIdentifiers.removeAll()
                }
            }
        }
    }
}

private struct GestureActionEditor: View {
    @Binding var action: CustomGestureAction

    var body: some View {
        Picker("Action", selection: actionType) {
            ForEach(GestureActionType.allCases) { Text($0.rawValue).tag($0) }
        }
        switch action {
        case .keyboardShortcut, .keyboardShortcutSequence:
            KeyboardShortcutSequenceEditor(action: $action)
        case .openApplication(let bundleIdentifier):
            LabeledContent("Application") {
                if bundleIdentifier.isEmpty {
                    Button(action: chooseApplication) {
                        Label("Choose Application…", systemImage: "plus")
                    }
                } else {
                    HStack {
                        Text(applicationName(bundleIdentifier))
                        Button(action: chooseApplication) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Choose a different application")
                        .help("Choose a different application")
                    }
                }
            }
        case .openURL:
            TextField("URL", text: url)
        case .runScript(let executableURL, _):
            LabeledContent("Script") {
                if executableURL == GestureActionDefaults.unselectedScriptURL {
                    Button(action: chooseScript) {
                        Label("Choose Script…", systemImage: "plus")
                    }
                } else {
                    HStack {
                        Text(executableURL.lastPathComponent)
                        Button(action: chooseScript) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Choose a different script")
                        .help("Choose a different script")
                    }
                }
            }
            TextField("Arguments", text: scriptArguments)
        }
    }

    private var actionType: Binding<GestureActionType> {
        Binding(
            get: {
                switch action {
                case .keyboardShortcut, .keyboardShortcutSequence: .shortcut
                case .openApplication: .application
                case .openURL: .url
                case .runScript: .script
                }
            },
            set: { type in
                switch type {
                case .shortcut:
                    action = .keyboardShortcut(keyCode: 49, modifiers: [.command])
                case .application:
                    action = .openApplication(bundleIdentifier: "")
                case .url:
                    action = .openURL(url: "")
                case .script:
                    action = .runScript(
                        executableURL: GestureActionDefaults.unselectedScriptURL,
                        arguments: []
                    )
                }
            }
        )
    }

    private var scriptArguments: Binding<String> {
        Binding(
            get: {
                guard case .runScript(_, let arguments) = action else { return "" }
                return arguments.joined(separator: " ")
            },
            set: { value in
                guard case .runScript(let url, _) = action else { return }
                action = .runScript(
                    executableURL: url,
                    arguments: value.split(whereSeparator: \.isWhitespace).map(String.init)
                )
            }
        )
    }

    private var url: Binding<String> {
        Binding(
            get: {
                guard case .openURL(let value) = action else { return "" }
                return value
            },
            set: { value in
                action = .openURL(url: value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
    }

    private func chooseApplication() {
        guard let bundleIdentifier = chooseApplicationBundleIdentifiers(
            allowsMultipleSelection: false
        ).first else { return }
        action = .openApplication(bundleIdentifier: bundleIdentifier)
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action = .runScript(executableURL: url, arguments: [])
    }
}

private struct KeyboardShortcutSequenceEditor: View {
    @Binding var action: CustomGestureAction
    @State private var stepRecorderIDs: [UUID]
    @State private var activeRecorderID: UUID?

    private static let maximumStepCount = 7
    private static let defaultInterStepInterval: TimeInterval = 0.2

    init(action: Binding<CustomGestureAction>) {
        _action = action
        _stepRecorderIDs = State(
            initialValue: (0..<Self.stepCount(for: action.wrappedValue)).map { _ in UUID() }
        )
    }

    var body: some View {
        Section("Shortcut Steps") {
            ForEach(shortcutSteps.indices, id: \.self) { index in
                HStack {
                    Text("Step \(index + 1)")
                    Spacer()
                    KeyBindingRecorder(
                        mode: .shortcut,
                        value: shortcutBinding(at: index),
                        startsRecording: activeRecorderID == recorderID(at: index),
                        recorderID: recorderID(at: index),
                        activeRecorderID: $activeRecorderID
                    )
                    Button { moveStep(from: index, to: index - 1) } label: {
                        Image(systemName: "arrow.up")
                    }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(index == shortcutSteps.startIndex)
                        .accessibilityLabel("Move Step \(index + 1) Up")
                        .help("Move Step \(index + 1) Up")
                    Button { moveStep(from: index, to: index + 1) } label: {
                        Image(systemName: "arrow.down")
                    }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(index == shortcutSteps.index(before: shortcutSteps.endIndex))
                        .accessibilityLabel("Move Step \(index + 1) Down")
                        .help("Move Step \(index + 1) Down")
                    Button(role: .destructive) { removeStep(at: index) } label: {
                        Image(systemName: "trash")
                    }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .disabled(shortcutSteps.count == 1)
                        .accessibilityLabel("Remove Step \(index + 1)")
                        .help("Remove Step \(index + 1)")
                }
            }
            Button(action: addStep) {
                Label("Add Keyboard Action Step", systemImage: "plus")
            }
                .disabled(shortcutSteps.count >= Self.maximumStepCount)

            if shortcutSteps.count > 1 {
                LabeledContent("Interval (ms)") {
                    TextField("Interval", value: interStepIntervalMilliseconds, format: .number)
                }
            }
        }
        .onChange(of: shortcutSteps.count) { _ in
            synchronizeRecorderIDs()
        }
    }

    private static func stepCount(for action: CustomGestureAction) -> Int {
        switch action {
        case .keyboardShortcut:
            1
        case .keyboardShortcutSequence(let steps, _):
            steps.count
        case .openApplication, .openURL, .runScript:
            0
        }
    }

    private var shortcutSteps: [KeyboardShortcut] {
        switch action {
        case .keyboardShortcut(let keyCode, let modifiers):
            [KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)]
        case .keyboardShortcutSequence(let steps, _):
            steps
        case .openApplication, .openURL, .runScript:
            []
        }
    }

    private var interStepInterval: TimeInterval {
        if case .keyboardShortcutSequence(_, let interval) = action {
            return interval
        }
        return Self.defaultInterStepInterval
    }

    private var interStepIntervalMilliseconds: Binding<Int> {
        Binding(
            get: { Int((interStepInterval * 1_000).rounded()) },
            set: { setSteps(shortcutSteps, interval: TimeInterval(max(0, $0)) / 1_000) }
        )
    }

    private func shortcutBinding(at index: Int) -> Binding<KeyBindingValue> {
        Binding(
            get: {
                let shortcut = shortcutSteps[index]
                return KeyBindingValue(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
            },
            set: { value in
                guard let keyCode = value.keyCode else { return }
                var steps = shortcutSteps
                steps[index] = KeyboardShortcut(keyCode: keyCode, modifiers: value.modifiers)
                setSteps(steps)
                activeRecorderID = nil
            }
        )
    }

    private func addStep() {
        guard shortcutSteps.count < Self.maximumStepCount else { return }
        let newRecorderID = UUID()
        stepRecorderIDs.append(newRecorderID)
        setSteps(shortcutSteps + [KeyboardShortcut(keyCode: 49, modifiers: [])])
        activeRecorderID = newRecorderID
    }

    private func removeStep(at index: Int) {
        guard shortcutSteps.count > 1 else { return }
        activeRecorderID = nil
        var steps = shortcutSteps
        steps.remove(at: index)
        stepRecorderIDs.remove(at: index)
        setSteps(steps)
    }

    private func moveStep(from source: Int, to destination: Int) {
        guard shortcutSteps.indices.contains(source), shortcutSteps.indices.contains(destination) else { return }
        activeRecorderID = nil
        var steps = shortcutSteps
        steps.swapAt(source, destination)
        stepRecorderIDs.swapAt(source, destination)
        setSteps(steps)
    }

    private func recorderID(at index: Int) -> UUID {
        stepRecorderIDs[index]
    }

    private func synchronizeRecorderIDs() {
        let stepCount = shortcutSteps.count
        if stepRecorderIDs.count < stepCount {
            stepRecorderIDs += (stepRecorderIDs.count..<stepCount).map { _ in UUID() }
        } else if stepRecorderIDs.count > stepCount {
            stepRecorderIDs = Array(stepRecorderIDs.prefix(stepCount))
        }
        if let activeRecorderID, !stepRecorderIDs.contains(activeRecorderID) {
            self.activeRecorderID = nil
        }
    }

    private func setSteps(_ steps: [KeyboardShortcut], interval: TimeInterval? = nil) {
        action = .keyboardShortcutSequence(
            steps: steps,
            interStepInterval: interval ?? interStepInterval
        )
    }
}

private extension BasicGesture {
    static var defaultGesture: BasicGesture {
        BasicGesture(
            id: UUID(),
            name: "New Basic Gesture",
            kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.10,
            edgeProximity: 0.10,
            action: .keyboardShortcut(keyCode: 49, modifiers: [.command])
        )
    }
}

private extension AdvancedGesture {
    static var defaultGesture: AdvancedGesture {
        AdvancedGesture(
            id: UUID(),
            name: "New Advanced Gesture",
            recordings: [],
            isPositionallyAware: false,
            acceptanceThreshold: AdvancedSensitivity.balanced.threshold,
            action: .keyboardShortcut(keyCode: 49, modifiers: [.command])
        )
    }
}

private extension BasicGestureKind {
    var summary: String {
        switch self {
        case .edgeSwipe(let edge, let direction): "\(edge.rawValue.capitalized) edge swipe \(direction.rawValue)"
        case .pinch(let direction): "Pinch \(direction.rawValue)"
        case .rotate(let direction): "Rotate \(direction.rawValue)"
        }
    }
}

private extension CustomGestureAction {
    var isConfigured: Bool {
        switch self {
        case .keyboardShortcut, .keyboardShortcutSequence:
            return true
        case .openApplication(let bundleIdentifier):
            return !bundleIdentifier.isEmpty
        case .openURL:
            return urlToOpen != nil
        case .runScript(let url, _):
            return url != GestureActionDefaults.unselectedScriptURL
        }
    }

    var summary: String {
        switch self {
        case .keyboardShortcut(let keyCode, let modifiers):
            return KeyBindingValue(keyCode: keyCode, modifiers: modifiers).displayName
        case .keyboardShortcutSequence(let steps, _):
            return steps.map {
                KeyBindingValue(keyCode: $0.keyCode, modifiers: $0.modifiers).displayName
            }.joined(separator: " → ")
        case .openApplication(let bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return "Open application"
            }
            return "Open \(url.deletingPathExtension().lastPathComponent)"
        case .openURL(let url): return "Open \(url)"
        case .runScript(let url, _): return "Run \(url.lastPathComponent)"
        }
    }
}

private enum GestureActionDefaults {
    static let unselectedScriptURL = URL(fileURLWithPath: "/__drift_unselected_script__")
}

private func applicationName(_ bundleIdentifier: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        return bundleIdentifier
    }
    return url.deletingPathExtension().lastPathComponent
}

@MainActor
private func chooseApplicationBundleIdentifiers(
    allowsMultipleSelection: Bool
) -> Set<String> {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = allowsMultipleSelection
    guard panel.runModal() == .OK else { return [] }
    return Set(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
}

private extension EdgeSegment {
    func title(for edge: TrackpadEdge) -> String {
        switch (edge, self) {
        case (.top, .leading), (.bottom, .leading): "Left"
        case (.top, .middle), (.bottom, .middle): "Middle"
        case (.top, .trailing), (.bottom, .trailing): "Right"
        case (.left, .leading), (.right, .leading): "Bottom"
        case (.left, .middle), (.right, .middle): "Middle"
        case (.left, .trailing), (.right, .trailing): "Top"
        }
    }
}
