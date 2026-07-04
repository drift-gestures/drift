import Foundation

/// One block type in a Pomodoro session.
enum PomodoroBlockKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    /// Focus work block.
    case focus
    /// Short recovery break.
    case shortBreak
    /// Long recovery break.
    case longBreak

    /// Stable identity for SwiftUI and menu items.
    var id: Self { self }

    /// User-facing block label.
    var title: String {
        switch self {
        case .focus: "Focus duration"
        case .shortBreak: "Short break duration"
        case .longBreak: "Long break duration"
        }
    }

    /// Short title for menu-bar summaries.
    var menuTitle: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    /// SF Symbol used for this Pomodoro block.
    var symbolName: String {
        switch self {
        case .focus: "figure.run"
        case .shortBreak: "figure.cooldown"
        case .longBreak: "flag.pattern.checkered"
        }
    }

    /// Matching setup field.
    var durationField: PomodoroDurationField {
        switch self {
        case .focus: .focus
        case .shortBreak: .shortBreak
        case .longBreak: .longBreak
        }
    }
}

/// A background timer managed after the HUD closes.
struct BackgroundTimerSession: Identifiable, Equatable, Sendable {
    /// Stable timer identity.
    let id: UUID
    /// Original timer length.
    let duration: TimeInterval
    /// Timestamp when this timer block started or resumed.
    var startedAt: Date
    /// Wall-clock deadline for the timer.
    var endsAt: Date
    /// Remaining seconds captured while paused.
    var pausedRemaining: TimeInterval?
    /// Whether completion has been emitted.
    var isCompleted: Bool

    /// Whether the timer is currently paused.
    var isPaused: Bool {
        pausedRemaining != nil
    }

    /// Creates a new running timer.
    init(id: UUID = UUID(), duration: TimeInterval, now: Date) {
        self.id = id
        self.duration = duration
        startedAt = now
        endsAt = now.addingTimeInterval(duration)
        pausedRemaining = nil
        isCompleted = false
    }

    /// Remaining seconds at the supplied timestamp.
    func remainingSeconds(now: Date) -> TimeInterval {
        if let pausedRemaining {
            return max(0, pausedRemaining)
        }
        guard !isCompleted else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }
}

/// One active Pomodoro session.
struct PomodoroSession: Identifiable, Equatable, Sendable {
    /// Stable session identity.
    let id: UUID
    /// Duration configuration captured from the setup HUD.
    var durations: PomodoroDurations
    /// Currently running block.
    var currentBlock: PomodoroBlockKind
    /// Number of focus blocks completed in this session.
    var completedFocusCount: Int
    /// Timestamp when this block started or resumed.
    var blockStartedAt: Date
    /// Wall-clock deadline for the current block.
    var blockEndsAt: Date
    /// Remaining seconds captured while paused.
    var pausedRemaining: TimeInterval?

    /// Whether the current block is paused.
    var isPaused: Bool {
        pausedRemaining != nil
    }

    /// Creates a new Pomodoro session beginning with a focus block.
    init(id: UUID = UUID(), durations: PomodoroDurations, now: Date) {
        self.id = id
        self.durations = durations
        currentBlock = .focus
        completedFocusCount = 0
        blockStartedAt = now
        blockEndsAt = now.addingTimeInterval(PomodoroSession.seconds(for: .focus, durations: durations))
        pausedRemaining = nil
    }

    /// Remaining seconds for the current block at the supplied timestamp.
    func remainingSeconds(now: Date) -> TimeInterval {
        if let pausedRemaining {
            return max(0, pausedRemaining)
        }
        return max(0, blockEndsAt.timeIntervalSince(now))
    }

    /// Configured duration in seconds for one block type.
    static func seconds(for block: PomodoroBlockKind, durations: PomodoroDurations) -> TimeInterval {
        max(1, TimeInterval(durations[block.durationField] * 60))
    }
}

/// Completion event emitted by the runtime coordinator.
enum BackgroundTimerRuntimeEvent: Equatable, Sendable {
    /// A plain timer completed.
    case timerCompleted(id: UUID, duration: TimeInterval)
    /// A Pomodoro block completed and the runtime advanced to the next block.
    case pomodoroBlockCompleted(sessionID: UUID, block: PomodoroBlockKind)
}
