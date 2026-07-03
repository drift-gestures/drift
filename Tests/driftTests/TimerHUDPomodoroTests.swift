import XCTest
@testable import drift

final class TimerHUDPomodoroTests: XCTestCase {
    func testDurationFormatterAcceptsMinuteAndClockInput() {
        XCTAssertEqual(TimerHUDDurationFormatter.parsed("25"), 25)
        XCTAssertEqual(TimerHUDDurationFormatter.parsed("25:00"), 25)
        XCTAssertEqual(TimerHUDDurationFormatter.parsed("05:00"), 5)
        XCTAssertEqual(TimerHUDDurationFormatter.parsed("1000"), 100)
        XCTAssertEqual(TimerHUDDurationFormatter.parsed("-3"), 0)
        XCTAssertNil(TimerHUDDurationFormatter.parsed(""))
        XCTAssertNil(TimerHUDDurationFormatter.parsed("abc"))
        XCTAssertNil(TimerHUDDurationFormatter.parsed("10:90"))
        XCTAssertNil(TimerHUDDurationFormatter.parsed("1:2:3"))
        XCTAssertNil(TimerHUDDurationFormatter.parsed("10:"))
        XCTAssertNil(TimerHUDDurationFormatter.parsed(":10"))
        XCTAssertNil(TimerHUDDurationFormatter.parsed("--3"))
        XCTAssertNil(TimerHUDDurationFormatter.parsed("3-1"))
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
        XCTAssertNil(state.focusedPomodoroField)
    }

    func testPomodoroModeIgnoresVerticalScrollWithoutHoveredInput() {
        var state = TimerHUDInteractionState(mode: .pomodoro, timerDuration: 30)

        let didUpdate = state.receivePomodoroInput(scrollAmount: 25)

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(state.mode, .pomodoro)
        XCTAssertEqual(state.timerDuration, 30)
        XCTAssertEqual(state.pomodoroDurations.focus, 25)
    }

    func testPomodoroModeIgnoresFocusedInputWhenItIsNotHovered() {
        var state = TimerHUDInteractionState(mode: .pomodoro, timerDuration: 30)
        state.setFocus(.shortBreak, isFocused: true)

        let didUpdate = state.receivePomodoroInput(scrollAmount: 10)

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(state.pomodoroDurations.shortBreak, 5)
        XCTAssertNil(state.hoveredPomodoroField)
        XCTAssertEqual(state.focusedPomodoroField, .shortBreak)
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
        XCTAssertNil(state.focusedPomodoroField)
    }

    private func input(
        _ kind: TimerHUDInput.Kind,
        magnitude: Double = 0.04,
        frame: Int = 1
    ) -> TimerHUDInput {
        TimerHUDInput(kind: kind, magnitude: magnitude, frame: frame)
    }
}
