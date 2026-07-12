import CoreGraphics
import Foundation

/// Main-actor owner for advanced-gesture training and safe recognition tests.
@MainActor
final class CustomGestureRecordingSession: ObservableObject {
    enum Mode {
        case idle
        case recording(positionallyAware: Bool)
        case testing(AdvancedGesture)
    }

    @Published private(set) var recordings: [AdvancedGestureRecording] = []
    @Published private(set) var previewSnapshot: TrackpadSnapshot?
    @Published private(set) var currentPaths: [Int: [CGPoint]] = [:]
    @Published private(set) var testResult: String?
    @Published private(set) var rejectedTakeMessage: String?

    private let modeState: CustomGestureModeState
    private let captureState: CustomGestureCaptureState
    private var mode: Mode = .idle
    private var snapshots: [TrackpadSnapshot] = []
    private var pendingEndFrame: Int?
    private var pendingFinishTask: Task<Void, Never>?

    init(modeState: CustomGestureModeState, captureState: CustomGestureCaptureState) {
        self.modeState = modeState
        self.captureState = captureState
    }

    func beginRecording(positionallyAware: Bool, existing: [AdvancedGestureRecording]) {
        mode = .recording(positionallyAware: positionallyAware)
        recordings = Array(existing.prefix(5))
        resetAttempt()
        testResult = nil
        captureState.setActive(true)
    }

    func beginTesting(_ gesture: AdvancedGesture) {
        mode = .testing(gesture)
        resetAttempt()
        testResult = "Hold the activation binding and perform the gesture."
        captureState.setActive(true)
    }

    func end() {
        mode = .idle
        resetAttempt()
        captureState.setActive(false)
    }

    func removeRecording(at index: Int) {
        guard recordings.indices.contains(index) else { return }
        recordings.remove(at: index)
    }

    func receive(_ snapshot: TrackpadSnapshot) {
        guard captureState.isActive else { return }
        previewSnapshot = snapshot.contacts.isEmpty ? nil : snapshot

        guard modeState.isAdvancedModeActive else {
            if !snapshots.isEmpty { resetAttempt() }
            return
        }

        switch snapshot.phase {
        case .began:
            if let pendingEndFrame {
                clearPendingFinish()
                if pendingEndFrame == snapshot.frame {
                    snapshots.append(snapshot)
                    appendPreviewContacts(from: snapshot)
                    return
                }
                finishAttempt()
            }
            snapshots = [snapshot]
            currentPaths.removeAll(keepingCapacity: true)
            appendPreviewContacts(from: snapshot)
            rejectedTakeMessage = nil
        case .changed:
            finalizePendingEndIfNeeded()
            guard !snapshots.isEmpty else { return }
            snapshots.append(snapshot)
            appendPreviewContacts(from: snapshot)
        case .ended:
            guard !snapshots.isEmpty else { return }
            snapshots.append(snapshot)
            schedulePendingFinish(for: snapshot.frame)
        }
    }

    /// The bridge briefly ends and restarts a sequence in the same hardware frame whenever finger
    /// identities change. Delaying completion lets that synthetic boundary be merged into one take.
    private func schedulePendingFinish(for frame: Int) {
        clearPendingFinish()
        pendingEndFrame = frame
        pendingFinishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.finalizePendingEnd(frame: frame)
        }
    }

    private func finalizePendingEndIfNeeded() {
        guard pendingEndFrame != nil else { return }
        clearPendingFinish()
        finishAttempt()
    }

    private func finalizePendingEnd(frame: Int) {
        guard pendingEndFrame == frame else { return }
        pendingEndFrame = nil
        pendingFinishTask = nil
        finishAttempt()
    }

    private func clearPendingFinish() {
        pendingFinishTask?.cancel()
        pendingFinishTask = nil
        pendingEndFrame = nil
    }

    private func finishAttempt() {
        defer { resetAttempt(keepPreview: true) }
        switch mode {
        case .idle:
            break
        case .recording(let positionallyAware):
            guard recordings.count < 5 else { return }
            guard let recording = AdvancedGestureRecognizer.recording(
                from: snapshots,
                positionallyAware: positionallyAware
            ) else {
                rejectedTakeMessage = "That take was too short. Try again."
                return
            }
            recordings.append(recording)
            rejectedTakeMessage = nil
        case .testing(let gesture):
            let recording = AdvancedGestureRecognizer.recording(from: snapshots, positionallyAware: true)
            let match = recording.flatMap {
                AdvancedGestureRecognizer.bestMatch(recording: $0, gestures: [gesture])
            }
            if let match, match.distance <= gesture.acceptanceThreshold {
                testResult = "Matched \(gesture.name)."
            } else {
                testResult = "No match. Try the gesture again."
            }
        }
    }

    private func resetAttempt(keepPreview: Bool = false) {
        clearPendingFinish()
        snapshots.removeAll(keepingCapacity: true)
        currentPaths.removeAll(keepingCapacity: true)
        if !keepPreview { previewSnapshot = nil }
    }

    /// Adds one preview point per physical contact so finger-count changes cannot move a shared
    /// centroid and draw a line across unrelated positions.
    private func appendPreviewContacts(from snapshot: TrackpadSnapshot) {
        for contact in snapshot.contacts {
            currentPaths[contact.identifier, default: []].append(
                CGPoint(
                    x: contact.normalizedPosition.x,
                    y: contact.normalizedPosition.y
                )
            )
        }
    }
}

/// Main-actor adapter that publishes the thread-safe gesture library to Settings.
@MainActor
final class CustomGestureSettingsModel: ObservableObject {
    @Published private(set) var library: CustomGestureLibrary
    let recordingSession: CustomGestureRecordingSession
    private let store: CustomGestureStore

    init(store: CustomGestureStore, recordingSession: CustomGestureRecordingSession) {
        self.store = store
        self.recordingSession = recordingSession
        library = store.snapshot()
    }

    func save(_ gesture: BasicGesture) {
        store.upsert(gesture)
        refresh()
    }

    func save(_ gesture: AdvancedGesture) {
        store.upsert(gesture)
        refresh()
    }

    func remove(id: UUID) {
        store.removeGesture(id: id)
        refresh()
    }

    func setActivationModifiers(_ modifiers: Set<KeyboardModifier>) {
        guard !modifiers.isEmpty else { return }
        var library = store.snapshot()
        library.advancedActivationModifiers = modifiers
        store.replace(with: library)
        refresh()
    }

    private func refresh() {
        library = store.snapshot()
    }
}
