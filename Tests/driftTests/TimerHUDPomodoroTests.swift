import XCTest
@testable import drift

final class TimerHUDPomodoroTests: XCTestCase {
    func testDurationFormatterClampsFormattedMinutes() {
        XCTAssertEqual(TimerHUDDurationFormatter.formatted(25), "25:00")
        XCTAssertEqual(TimerHUDDurationFormatter.formatted(1000), "100:00")
        XCTAssertEqual(TimerHUDDurationFormatter.formatted(-3), "00:00")
    }

    func testScrollSensitivityConvertsMagnitudeToMinutes() {
        XCTAssertEqual(
            TimerHUDInteractionState.stepSize(for: input(.scrollUp, magnitude: 0.25)),
            25
        )
    }

    func testTimerModeVerticalScrollUpdatesTimerDuration() {
        var state = TimerHUDInteractionState()

        let didUpdate = state.receiveTimerInput(scrollAmount: 25)

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(state.mode, .timer)
        XCTAssertEqual(state.timerDuration, 25)
    }

    func testTimerModeRightScrollSwitchesToPomodoro() {
        var state = TimerHUDInteractionState()

        state.switchToPomodoro()

        XCTAssertEqual(state.mode, .pomodoro)
        XCTAssertNil(state.hoveredPomodoroField)
    }

    func testPomodoroModeIgnoresVerticalScrollWithoutHoveredInput() {
        var state = TimerHUDInteractionState(mode: .pomodoro, timerDuration: 30)

        let didUpdate = state.receivePomodoroInput(scrollAmount: 25)

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(state.mode, .pomodoro)
        XCTAssertEqual(state.timerDuration, 30)
        XCTAssertEqual(state.pomodoroDurations.focus, 25)
    }

    func testPomodoroModeVerticalScrollUpdatesHoveredInputOnly() {
        var state = TimerHUDInteractionState(mode: .pomodoro, timerDuration: 30)
        state.setHover(.shortBreak, isHovered: true)

        let didUpdate = state.receivePomodoroInput(scrollAmount: 10)

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(state.mode, .pomodoro)
        XCTAssertEqual(state.timerDuration, 30)
        XCTAssertEqual(state.pomodoroDurations.focus, 25)
        XCTAssertEqual(state.pomodoroDurations.shortBreak, 15)
        XCTAssertEqual(state.pomodoroDurations.longBreak, 15)
    }

    func testPomodoroModeDoesNotUpdateLockedActiveField() {
        var state = TimerHUDInteractionState(mode: .pomodoro)
        state.setHover(.focus, isHovered: true)

        let didUpdate = state.receivePomodoroInput(scrollAmount: 10, lockedField: .focus)

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(state.pomodoroDurations.focus, 25)
    }

    func testPomodoroModeLeftScrollSwitchesBackToTimer() {
        var state = TimerHUDInteractionState(mode: .pomodoro)
        state.setHover(.focus, isHovered: true)

        state.switchToTimer()

        XCTAssertEqual(state.mode, .timer)
        XCTAssertNil(state.hoveredPomodoroField)
    }

    private func input(
        _ kind: TimerHUDInput.Kind,
        magnitude: Double = 0.04,
        frame: Int = 1
    ) -> TimerHUDInput {
        TimerHUDInput(kind: kind, magnitude: magnitude, frame: frame)
    }
}
