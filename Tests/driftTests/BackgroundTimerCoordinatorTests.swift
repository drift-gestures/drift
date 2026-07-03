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

        XCTAssertEqual(events, [.timerCompleted(id: try XCTUnwrap(id))])
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

        XCTAssertEqual(events, [.timerCompleted(id: id)])
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
}
