import XCTest
@testable import drift

@MainActor
final class BackgroundTimerCoordinatorTests: XCTestCase {
    func testTimerCompletesFromWallClockAndCanRepeat() throws {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })
        var events: [BackgroundTimerRuntimeEvent] = []
        coordinator.eventHandler = { events.append($0) }

        let id = coordinator.startTimer(minutes: 1)
        now = now.addingTimeInterval(61)
        coordinator.tick()

        XCTAssertEqual(events, [.timerCompleted(id: try XCTUnwrap(id), duration: 60)])
        XCTAssertEqual(coordinator.timers.count, 1)
        XCTAssertTrue(try XCTUnwrap(coordinator.timers.first).isCompleted)

        coordinator.repeatTimer(id: try XCTUnwrap(id))

        XCTAssertEqual(coordinator.timers.count, 1)
        XCTAssertFalse(try XCTUnwrap(coordinator.timers.first).isCompleted)
        XCTAssertNotEqual(coordinator.timers.first?.id, id)
    }

    func testPausedTimerDoesNotCompleteUntilResumed() throws {
        var now = Date(timeIntervalSinceReferenceDate: 2_000)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })
        var events: [BackgroundTimerRuntimeEvent] = []
        coordinator.eventHandler = { events.append($0) }

        let id = try XCTUnwrap(coordinator.startTimer(minutes: 1))
        now = now.addingTimeInterval(30)
        coordinator.toggleTimerPause(id: id)
        now = now.addingTimeInterval(120)
        coordinator.tick()

        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(try XCTUnwrap(coordinator.timers.first).isPaused)

        coordinator.toggleTimerPause(id: id)
        now = now.addingTimeInterval(31)
        coordinator.tick()

        XCTAssertEqual(events, [.timerCompleted(id: id, duration: 60)])
    }

    func testNextTimerRemainingSecondsUsesEarliestUnfinishedTimer() {
        var now = Date(timeIntervalSinceReferenceDate: 2_500)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })

        _ = coordinator.startTimer(minutes: 10)
        _ = coordinator.startTimer(minutes: 3)
        now = now.addingTimeInterval(65)

        XCTAssertEqual(coordinator.nextTimerRemainingSeconds(), 115)
    }

    func testNextTimerRemainingSecondsUsesRunningTimerBeforePausedTimer() throws {
        var now = Date(timeIntervalSinceReferenceDate: 2_700)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })

        let pausedID = try XCTUnwrap(coordinator.startTimer(minutes: 1))
        now = now.addingTimeInterval(55)
        coordinator.toggleTimerPause(id: pausedID)

        _ = coordinator.startTimer(minutes: 1)
        now = now.addingTimeInterval(10)

        XCTAssertEqual(coordinator.nextTimerRemainingSeconds(), 50)
    }

    func testPomodoroUsesClassicFourFocusCycle() throws {
        var now = Date(timeIntervalSinceReferenceDate: 3_000)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })
        let durations = PomodoroDurations(focus: 1, shortBreak: 1, longBreak: 1)

        coordinator.startPomodoro(durations: durations)

        for focusIndex in 1...4 {
            now = now.addingTimeInterval(61)
            coordinator.tick()

            let expectedBreak: PomodoroBlockKind = focusIndex == 4 ? .longBreak : .shortBreak
            XCTAssertEqual(coordinator.pomodoroSession?.currentBlock, expectedBreak)
            XCTAssertEqual(coordinator.pomodoroSession?.completedFocusCount, focusIndex)

            if focusIndex < 4 {
                now = now.addingTimeInterval(61)
                coordinator.tick()
                XCTAssertEqual(coordinator.pomodoroSession?.currentBlock, .focus)
            }
        }
    }

    func testPomodoroPreferenceStorePersistsDurations() throws {
        let suiteName = "drift-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PomodoroPreferencesStore(defaults: defaults)
        store.save(PomodoroDurations(focus: 45, shortBreak: 10, longBreak: 30))

        let reloadedStore = PomodoroPreferencesStore(defaults: defaults)

        XCTAssertEqual(reloadedStore.durations, PomodoroDurations(focus: 45, shortBreak: 10, longBreak: 30))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPausedPomodoroDoesNotCompleteUntilResumed() throws {
        var now = Date(timeIntervalSinceReferenceDate: 20_000)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })
        var events: [BackgroundTimerRuntimeEvent] = []
        coordinator.eventHandler = { events.append($0) }

        coordinator.startPomodoro(durations: PomodoroDurations(focus: 1, shortBreak: 1, longBreak: 1))
        now = now.addingTimeInterval(30)
        coordinator.togglePomodoroPause()
        now = now.addingTimeInterval(120)
        coordinator.tick()

        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(try XCTUnwrap(coordinator.pomodoroSession).isPaused)

        coordinator.togglePomodoroPause()
        now = now.addingTimeInterval(31)
        coordinator.tick()

        XCTAssertEqual(events, [.pomodoroBlockCompleted(sessionID: try XCTUnwrap(coordinator.pomodoroSession?.id), block: .focus)])
    }

    func testResumingPomodoroRestartsTicker() throws {
        var now = Date(timeIntervalSinceReferenceDate: 21_000)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })
        var events: [BackgroundTimerRuntimeEvent] = []
        coordinator.eventHandler = { events.append($0) }

        let durations = PomodoroDurations(focus: 1, shortBreak: 1, longBreak: 1)
        coordinator.startPomodoro(durations: durations)
        coordinator.togglePomodoroPause()
        coordinator.togglePomodoroPause()

        now = now.addingTimeInterval(61)
        coordinator.tick()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(coordinator.pomodoroSession?.currentBlock, .shortBreak)
    }

    func testPausedPomodoroWithActiveTimerStillUpdates() throws {
        var now = Date(timeIntervalSinceReferenceDate: 22_000)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })
        var events: [BackgroundTimerRuntimeEvent] = []
        coordinator.eventHandler = { events.append($0) }

        coordinator.startPomodoro(durations: PomodoroDurations(focus: 25, shortBreak: 5, longBreak: 15))
        coordinator.togglePomodoroPause()

        let timerID = try XCTUnwrap(coordinator.startTimer(minutes: 1))
        now = now.addingTimeInterval(61)
        coordinator.tick()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first, .timerCompleted(id: timerID, duration: 60))
        XCTAssertNotNil(coordinator.pomodoroSession)
        XCTAssertTrue(try XCTUnwrap(coordinator.pomodoroSession).isPaused)
    }

    func testIdleTickDoesNotPublishObjectChange() throws {
        var now = Date(timeIntervalSinceReferenceDate: 23_000)
        let coordinator = BackgroundTimerCoordinator(nowProvider: { now })

        coordinator.startPomodoro(durations: PomodoroDurations(focus: 25, shortBreak: 5, longBreak: 15))
        coordinator.togglePomodoroPause()

        var changeCount = 0
        let cancellable = coordinator.objectWillChange.sink { changeCount += 1 }

        now = now.addingTimeInterval(60)
        coordinator.tick()

        XCTAssertEqual(changeCount, 0, "Idle tick while paused should not publish")

        cancellable.cancel()
    }
}
