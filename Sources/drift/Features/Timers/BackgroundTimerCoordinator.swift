import Combine
import Foundation

/// Owns background timer and Pomodoro runtime state after HUD setup closes.
@MainActor
final class BackgroundTimerCoordinator: ObservableObject {
    /// Active or completed plain timers.
    @Published private(set) var timers: [BackgroundTimerSession] = []
    /// Active Pomodoro session, if one is running.
    @Published private(set) var pomodoroSession: PomodoroSession?

    /// Callback for completion events that need UI, sound, or notification side effects.
    var eventHandler: ((BackgroundTimerRuntimeEvent) -> Void)?

    /// Clock used by production runtime and tests.
    private let nowProvider: () -> Date
    /// Repeating timer used to refresh derived countdown state.
    private var ticker: Timer?

    /// Creates a coordinator.
    /// - Parameter nowProvider: Clock provider, injectable for tests.
    init(nowProvider: @escaping () -> Date = Date.init) {
        self.nowProvider = nowProvider
    }

    /// Starts a plain background timer.
    /// - Parameter minutes: Timer length in whole minutes.
    /// - Returns: The timer ID, or `nil` when duration is zero.
    @discardableResult
    func startTimer(minutes: Int) -> UUID? {
        let clampedMinutes = TimerHUDDurationFormatter.clamped(minutes)
        guard clampedMinutes > 0 else { return nil }

        let timer = BackgroundTimerSession(
            duration: TimeInterval(clampedMinutes * 60),
            now: nowProvider()
        )
        timers.append(timer)
        ensureTicker()
        return timer.id
    }

    /// Cancels and removes a timer.
    func cancelTimer(id: UUID) {
        timers.removeAll { $0.id == id }
        stopTickerIfIdle()
    }

    /// Dismisses a completed timer after its alert is handled.
    func dismissTimer(id: UUID) {
        cancelTimer(id: id)
    }

    /// Starts a fresh timer using the completed timer's original duration.
    func repeatTimer(id: UUID) {
        guard let existing = timers.first(where: { $0.id == id }) else { return }
        cancelTimer(id: id)
        _ = startTimer(minutes: Int(existing.duration / 60))
    }

    /// Toggles a timer between paused and running.
    func toggleTimerPause(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              !timers[index].isCompleted
        else {
            return
        }

        let now = nowProvider()
        if let pausedRemaining = timers[index].pausedRemaining {
            timers[index].startedAt = now
            timers[index].endsAt = now.addingTimeInterval(pausedRemaining)
            timers[index].pausedRemaining = nil
        } else {
            timers[index].pausedRemaining = timers[index].remainingSeconds(now: now)
        }
        objectWillChange.send()
        ensureTicker()
    }

    /// Starts or replaces the active Pomodoro session.
    /// - Parameter durations: Block durations captured from setup.
    func startPomodoro(durations: PomodoroDurations) {
        guard durations.focus > 0 else { return }
        pomodoroSession = PomodoroSession(durations: durations, now: nowProvider())
        ensureTicker()
    }

    /// Saves duration changes into the active Pomodoro for future blocks.
    /// - Parameter durations: New duration configuration.
    func updatePomodoroDurations(_ durations: PomodoroDurations) {
        guard var session = pomodoroSession else { return }
        session.durations = durations
        pomodoroSession = session
    }

    /// Toggles the active Pomodoro block between paused and running.
    func togglePomodoroPause() {
        guard var session = pomodoroSession else { return }

        let now = nowProvider()
        if let pausedRemaining = session.pausedRemaining {
            session.blockStartedAt = now
            session.blockEndsAt = now.addingTimeInterval(pausedRemaining)
            session.pausedRemaining = nil
        } else {
            session.pausedRemaining = session.remainingSeconds(now: now)
        }
        pomodoroSession = session
        ensureTicker()
    }

    /// Skips the current Pomodoro block.
    func skipPomodoroBlock() {
        guard var session = pomodoroSession else { return }
        advancePomodoroSession(&session, now: nowProvider())
        pomodoroSession = session
        ensureTicker()
    }

    /// Restarts the current Pomodoro block.
    func resetPomodoroBlock() {
        guard var session = pomodoroSession else { return }
        let now = nowProvider()
        let duration = PomodoroSession.seconds(for: session.currentBlock, durations: session.durations)
        session.blockStartedAt = now
        session.blockEndsAt = now.addingTimeInterval(duration)
        session.pausedRemaining = nil
        pomodoroSession = session
        ensureTicker()
    }

    /// Stops the active Pomodoro session.
    func stopPomodoro() {
        pomodoroSession = nil
        stopTickerIfIdle()
    }

    /// Returns remaining seconds for a timer.
    func remainingSeconds(for timer: BackgroundTimerSession) -> TimeInterval {
        timer.remainingSeconds(now: nowProvider())
    }

    /// Returns remaining seconds for the active Pomodoro block.
    func pomodoroRemainingSeconds() -> TimeInterval {
        pomodoroSession?.remainingSeconds(now: nowProvider()) ?? 0
    }

    /// Manually advances runtime state. Tests can call this directly.
    func tick() {
        let now = nowProvider()
        var emittedEvents: [BackgroundTimerRuntimeEvent] = []

        for index in timers.indices {
            guard !timers[index].isPaused,
                  !timers[index].isCompleted,
                  timers[index].remainingSeconds(now: now) <= 0
            else {
                continue
            }
            timers[index].isCompleted = true
            emittedEvents.append(.timerCompleted(id: timers[index].id))
        }

        if var session = pomodoroSession,
           !session.isPaused,
           session.remainingSeconds(now: now) <= 0 {
            let completedBlock = session.currentBlock
            let sessionID = session.id
            advancePomodoroSession(&session, now: now)
            pomodoroSession = session
            emittedEvents.append(.pomodoroBlockCompleted(sessionID: sessionID, block: completedBlock))
        }

        objectWillChange.send()
        emittedEvents.forEach { eventHandler?($0) }
        stopTickerIfIdle()
    }

    /// Starts the repeating refresh timer when runtime work exists.
    private func ensureTicker() {
        guard ticker == nil,
              !timers.isEmpty || pomodoroSession != nil
        else {
            return
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    /// Tears down ticking when no active work needs it.
    private func stopTickerIfIdle() {
        let hasActiveTimers = timers.contains { !$0.isCompleted && !$0.isPaused }
        let hasPomodoro = pomodoroSession != nil
        guard !hasActiveTimers && !hasPomodoro else { return }

        ticker?.invalidate()
        ticker = nil
    }

    /// Advances a Pomodoro session to its next block.
    private func advancePomodoroSession(_ session: inout PomodoroSession, now: Date) {
        let nextBlock: PomodoroBlockKind
        var focusCount = session.completedFocusCount

        switch session.currentBlock {
        case .focus:
            focusCount += 1
            nextBlock = focusCount.isMultiple(of: 4) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            nextBlock = .focus
        }

        session.completedFocusCount = focusCount
        session.currentBlock = nextBlock
        session.blockStartedAt = now
        session.blockEndsAt = now.addingTimeInterval(PomodoroSession.seconds(for: nextBlock, durations: session.durations))
        session.pausedRemaining = nil
    }
}
