import AppKit
import CoreGraphics
import SwiftUI

extension Color {
    /// Accent color used for active Timer HUD ticks and text.
    static let tick = Color(
        red: 1.0,
        green: 138.0 / 255,
        blue: 40.0 / 255
    )

    /// Dimmed tick color used for inactive duration markers.
    static let tickFaded = tick.opacity(0.5)

    /// Background color used by the Timer HUD start button.
    static let timerStartbg = Color(
        red: 79 / 255,
        green: 45 / 255,
        blue: 20 / 255
    )
}

/// Shared geometry and spacing constants for Timer HUD components.
enum TimerHUDStyle {

    /// Number of labeled duration values shown in the rail.
    static let numberCount = 20
    /// Minute increment between labeled duration values.
    static let numberStep = 5
    /// Number of tick marks in the rail.
    static let tickCount = numberCount * numberStep
    /// Vertical spacing between labeled duration values.
    static let rowSpacing: CGFloat = 35
    /// Fixed height for each duration label.
    static let numberHeight: CGFloat = 20
    /// Fixed height for each tick mark.
    static let tickHeight: CGFloat = 3
    /// Vertical spacing between tick marks.
    static let tickSpacing: CGFloat = (rowSpacing + numberHeight - tickHeight * CGFloat(numberStep)) / CGFloat(numberStep)
    /// Vertical offset applied for each minute of selected duration.
    static let durationOffsetStep: CGFloat = (rowSpacing + numberHeight) / 5

    /// Fixed height of the Timer HUD window.
    static let windowHeight: CGFloat = 350
    /// Width of the tick rail portion of the HUD.
    static let timerTickWidth: CGFloat = 160
    /// Width of the control column portion of the HUD.
    static let timerButtonWidth: CGFloat = 110
    /// Horizontal gap between the tick rail and controls.
    static let timerGridGap: CGFloat = 14
    /// Width of the Pomodoro setup panel.
    static let pomodoroPanelWidth: CGFloat = 300
    /// Height of the Pomodoro setup panel.
    static let pomodoroPanelHeight: CGFloat = windowHeight
    /// Horizontal padding inside the Pomodoro setup panel.
    static let pomodoroPanelPadding: CGFloat = 26
    /// Height of a Pomodoro duration input capsule.
    static let pomodoroInputHeight: CGFloat = 32
    /// Fixed layout box for Pomodoro row symbols so text does not shift between block icons.
    static let pomodoroRowIconWidth: CGFloat = 18
    /// Multiplier used to convert normalized scroll magnitude to minutes.
    static let scrollSensitivity = 100.0
}

/// The currently mounted Timer HUD mode.
enum TimerHUDMode: Equatable {
    /// The original Timer UI is mounted.
    case timer
    /// The Pomodoro setup UI is mounted.
    case pomodoro
}

/// Pomodoro duration input identifiers.
enum PomodoroDurationField: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    /// Focus session duration.
    case focus
    /// Short break duration.
    case shortBreak
    /// Long break duration.
    case longBreak

    /// Stable identity for SwiftUI lists.
    var id: Self { self }

    /// User-facing label.
    var title: String {
        switch self {
        case .focus: "Focus duration"
        case .shortBreak: "Short break duration"
        case .longBreak: "Long break duration"
        }
    }
}

/// Editable Pomodoro durations in minutes.
struct PomodoroDurations: Codable, Equatable, Sendable {
    /// Default focus duration.
    var focus = 25
    /// Default short break duration.
    var shortBreak = 5
    /// Default long break duration.
    var longBreak = 15

    /// Creates a duration set.
    /// - Parameters:
    ///   - focus: Focus duration in minutes.
    ///   - shortBreak: Short break duration in minutes.
    ///   - longBreak: Long break duration in minutes.
    init(focus: Int = 25, shortBreak: Int = 5, longBreak: Int = 15) {
        self.focus = TimerHUDDurationFormatter.clamped(focus)
        self.shortBreak = TimerHUDDurationFormatter.clamped(shortBreak)
        self.longBreak = TimerHUDDurationFormatter.clamped(longBreak)
    }

    /// Reads or writes a duration by field.
    /// - Parameter field: The duration field to access.
    subscript(field: PomodoroDurationField) -> Int {
        get {
            switch field {
            case .focus: focus
            case .shortBreak: shortBreak
            case .longBreak: longBreak
            }
        }
        set {
            let clampedValue = TimerHUDDurationFormatter.clamped(newValue)
            switch field {
            case .focus: focus = clampedValue
            case .shortBreak: shortBreak = clampedValue
            case .longBreak: longBreak = clampedValue
            }
        }
    }
}

/// Shared duration formatting and parsing for Timer HUD duration controls.
enum TimerHUDDurationFormatter {
    /// Lowest supported duration in minutes.
    static let minimumMinutes = 0
    /// Highest supported duration in minutes.
    static let maximumMinutes = 100

    /// Formats a minute value as `MM:00`.
    /// - Parameter minutes: Duration in minutes.
    /// - Returns: A monospaced-friendly duration string.
    static func formatted(_ minutes: Int) -> String {
        String(format: "%02d:00", clamped(minutes))
    }

    /// Formats a raw second count as `MM:SS`.
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A countdown-friendly duration string.
    static func formattedSeconds(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    /// Parses either minute-only or `MM:SS` input into whole minutes.
    /// - Parameter text: User-entered duration text.
    /// - Returns: Clamped minutes, or `nil` when the text is invalid.
    static func parsed(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let minutes = parseInteger(trimmed) {
            return clamped(minutes)
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let minutes = parseInteger(parts[0]),
              let seconds = parseInteger(parts[1]),
              (0..<60).contains(seconds)
        else {
            return nil
        }

        return clamped(minutes + (seconds > 0 ? 1 : 0))
    }

    /// Clamps a minute value to the supported range.
    /// - Parameter minutes: Duration in minutes.
    /// - Returns: A supported duration.
    static func clamped(_ minutes: Int) -> Int {
        min(maximumMinutes, max(minimumMinutes, minutes))
    }

    /// Parses one integer component without accepting partially formatted input.
    /// - Parameter text: Component text to parse.
    /// - Returns: An integer when the whole component is numeric, otherwise `nil`.
    private static func parseInteger<S: StringProtocol>(_ text: S) -> Int? {
        guard !text.isEmpty else {
            return nil
        }

        var characters = Array(text)
        if characters.first == "-" {
            characters.removeFirst()
        }
        guard !characters.isEmpty,
              characters.allSatisfy(\.isNumber)
        else {
            return nil
        }

        return Int(String(text))
    }
}

/// Testable state machine for routing Timer HUD inputs to the mounted mode.
struct TimerHUDInteractionState: Equatable {
    /// Current mounted mode.
    var mode: TimerHUDMode = .timer
    /// Timer mode duration in minutes.
    var timerDuration = 0
    /// Pomodoro setup durations in minutes.
    var pomodoroDurations = PomodoroDurations()
    /// Pomodoro field currently under the pointer.
    var hoveredPomodoroField: PomodoroDurationField?
    /// Pomodoro field currently focused for typing.
    var focusedPomodoroField: PomodoroDurationField?

    /// Preferred rendered size for the current mode, or `nil` for the default Timer size.
    var sizeOverride: CGSize? {
        switch mode {
        case .timer:
            nil
        case .pomodoro:
            CGSize(
                width: TimerHUDStyle.pomodoroPanelWidth + TimerHUDStyle.timerGridGap + TimerHUDStyle.timerTickWidth,
                height: TimerHUDStyle.pomodoroPanelHeight
            )
        }
    }

    /// Switches from Timer to Pomodoro mode.
    mutating func switchToPomodoro() {
        mode = .pomodoro
        hoveredPomodoroField = nil
        focusedPomodoroField = nil
    }

    /// Switches from Pomodoro to Timer mode.
    mutating func switchToTimer() {
        mode = .timer
        hoveredPomodoroField = nil
        focusedPomodoroField = nil
    }

    /// Updates the hovered Pomodoro input field.
    /// - Parameters:
    ///   - field: The field whose hover state changed.
    ///   - isHovered: Whether the pointer is currently over the field.
    mutating func setHover(_ field: PomodoroDurationField, isHovered: Bool) {
        if isHovered {
            hoveredPomodoroField = field
        } else if hoveredPomodoroField == field {
            hoveredPomodoroField = nil
        }
    }

    /// Updates the focused Pomodoro input field.
    /// - Parameters:
    ///   - field: The field whose focus state changed.
    ///   - isFocused: Whether the field is currently focused.
    mutating func setFocus(_ field: PomodoroDurationField, isFocused: Bool) {
        if isFocused {
            focusedPomodoroField = field
        } else if focusedPomodoroField == field {
            focusedPomodoroField = nil
        }
    }

    /// Converts a gesture input magnitude into a duration step.
    /// - Parameter input: Gesture-derived Timer HUD input.
    /// - Returns: Number of minutes to add or remove.
    static func stepSize(for input: TimerHUDInput) -> Int {
        switch input.kind {
        case .scrollUp, .scrollDown:
            max(1, Int(input.magnitude * TimerHUDStyle.scrollSensitivity))
        default:
            0
        }
    }

    /// Applies input while Timer mode is mounted.
    /// - Parameter scrollAmount: Signed scroll amount in minutes.
    /// - Returns: `true` when state changed.
    mutating func receiveTimerInput(scrollAmount: Int) -> Bool {
        let nextDuration = TimerHUDDurationFormatter.clamped(timerDuration + scrollAmount)
        guard nextDuration != timerDuration else { return false }
        timerDuration = nextDuration
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        return true
    }

    /// Applies input while Pomodoro mode is mounted.
    /// - Parameter scrollAmount: Signed scroll amount in minutes.
    /// - Returns: `true` when state changed.
    mutating func receivePomodoroInput(
        scrollAmount: Int,
        lockedField: PomodoroDurationField? = nil
    ) -> Bool {
        guard let hoveredPomodoroField else { return false }
        guard hoveredPomodoroField != lockedField else { return false }

        let currentDuration = pomodoroDurations[hoveredPomodoroField]
        let nextDuration = TimerHUDDurationFormatter.clamped(currentDuration + scrollAmount)
        guard nextDuration != currentDuration else { return false }
        pomodoroDurations[hoveredPomodoroField] = nextDuration
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        return true
    }
}

/// Timer HUD transition helpers that preserve newer effects where available.
private extension View {
    /// Mode switch transition when Timer mode appears.
    @ViewBuilder
    func timerHUDLeadingModeTransition() -> some View {
        if #available(macOS 14.0, *) {
            transition(.move(edge: .leading).combined(with: .blurReplace))
        } else {
            transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    /// Mode switch transition when Pomodoro mode appears.
    @ViewBuilder
    func timerHUDTrailingModeTransition() -> some View {
        if #available(macOS 14.0, *) {
            transition(.move(edge: .trailing).combined(with: .blurReplace))
        } else {
            transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// Side rail transition for Pomodoro duration hover.
    @ViewBuilder
    func timerHUDDurationRailTransition() -> some View {
        if #available(macOS 14.0, *) {
            transition(.blurReplace)
        } else {
            transition(.opacity)
        }
    }
}

/// Root SwiftUI view for the Timer HUD.
struct TimerHUDView: View {
    /// Size used by the fade overlay to cover the visible Timer HUD area.
    let screenSize: CGSize
    /// Runtime timer coordinator.
    @ObservedObject private var backgroundTimers: BackgroundTimerCoordinator
    /// Persisted Pomodoro duration preferences.
    @ObservedObject private var pomodoroPreferences: PomodoroPreferencesStore
    /// HUD lifecycle controller.
    private let hudController: HUDController

    /// Bus that delivers Timer HUD input messages.
    @EnvironmentObject private var hudMessages: HUDMessageBus
    /// Store used to update the HUD panel size for the mounted mode.
    @EnvironmentObject private var hudStore: HUDStore
    /// Current Timer HUD interaction state.
    @State private var interactionState = TimerHUDInteractionState()
    
    @State private var justStartedPomodoro = false

    /// Creates the Timer HUD root view.
    /// - Parameters:
    ///   - screenSize: Base HUD size.
    ///   - backgroundTimers: Runtime timer coordinator.
    ///   - pomodoroPreferences: Persisted Pomodoro duration store.
    ///   - hudController: HUD lifecycle handle.
    init(
        screenSize: CGSize,
        backgroundTimers: BackgroundTimerCoordinator,
        pomodoroPreferences: PomodoroPreferencesStore,
        hudController: HUDController
    ) {
        self.screenSize = screenSize
        self.backgroundTimers = backgroundTimers
        self.pomodoroPreferences = pomodoroPreferences
        self.hudController = hudController
        _interactionState = State(
            initialValue: TimerHUDInteractionState(
                pomodoroDurations: pomodoroPreferences.durations
            )
        )
    }

    var body: some View {
        Group {
            switch interactionState.mode {
            case .timer:
                TimerHUDTimerModeView(
                    duration: interactionState.timerDuration,
                    screenSize: screenSize,
                    startTimer: startTimer
                )
                .timerHUDLeadingModeTransition()
            case .pomodoro:
                if let pomodoroSession = backgroundTimers.pomodoroSession, !justStartedPomodoro {
                    ActivePomodoroHUDModeView(
                        session: pomodoroSession,
                        remainingSeconds: backgroundTimers.pomodoroRemainingSeconds(),
                        durations: pomodoroDurationBinding,
                        hoverField: interactionState.hoveredPomodoroField,
                        setHoveredField: setHoveredPomodoroField,
                        setFocusedField: setFocusedPomodoroField,
                        togglePause: backgroundTimers.togglePomodoroPause,
                        skip: backgroundTimers.skipPomodoroBlock,
                        stop: backgroundTimers.stopPomodoro,
                    )
                    .timerHUDTrailingModeTransition()
                } else {
                    PomodoroHUDModeView(
                        durations: pomodoroDurationBinding,
                        hoverField: interactionState.hoveredPomodoroField,
                        setHoveredField: setHoveredPomodoroField,
                        setFocusedField: setFocusedPomodoroField,
                        startPomodoro: startPomodoro
                    )
                    .timerHUDTrailingModeTransition()
                }
            }
        }
        .onAppear {
            interactionState.pomodoroDurations = pomodoroPreferences.durations
            updateSizeOverride()
        }
        .onDisappear {
            hudStore.setSizeOverride(nil, for: TimerHUDDefinition.hudID)
        }
        .onChange(of: interactionState.mode) { _ in
            updateSizeOverride()
        }
        .onChange(of: interactionState.hoveredPomodoroField) { _ in
            updateSizeOverride()
        }
        .onChange(of: interactionState.focusedPomodoroField) { _ in
            updateSizeOverride()
        }
        .onChange(of: interactionState.pomodoroDurations) { durations in
            pomodoroPreferences.save(durations)
            backgroundTimers.updatePomodoroDurations(durations)
        }
        .onChange(of: backgroundTimers.pomodoroSession) { _ in
            updateSizeOverride()
        }
        .onReceive(hudMessages.messages) { message in
            receiveHUDMessage(message)
        }
    }

    /// Handles a targeted HUD message if it belongs to the Timer HUD.
    /// - Parameter targetedMessage: The message and destination HUD identifier.
    private func receiveHUDMessage(_ targetedMessage: TargetedHUDMessage) {
        guard targetedMessage.hudID == TimerHUDDefinition.hudID else { return }

        switch targetedMessage.message {
        case .timerInput(let input):
            receiveTimerHUDInput(input)
        case .timerDefaultAction:
            performDefaultAction()
        }
    }

    /// Applies Timer HUD input to the mounted mode.
    /// - Parameter input: Gesture-derived Timer HUD input.
    private func receiveTimerHUDInput(_ input: TimerHUDInput) {
        switch (interactionState.mode, input.kind) {
        case (.timer, .scrollRight):
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            withAnimation {
                interactionState.switchToPomodoro()
            }
        case (.pomodoro, .scrollLeft):
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            withAnimation {
                interactionState.switchToTimer()
            }
        case (_, .scrollUp), (_, .scrollDown):
            guard let scrollAmount = signedScrollAmount(for: input) else { return }
            withAnimation {
                switch interactionState.mode {
                case .timer:
                    _ = interactionState.receiveTimerInput(scrollAmount: scrollAmount)
                case .pomodoro:
                    _ = interactionState.receivePomodoroInput(
                        scrollAmount: scrollAmount,
                        lockedField: lockedPomodoroField
                    )
                }
            }
        default:
            return
        }
    }

    /// Converts vertical input into a signed minute delta.
    /// - Parameter input: Gesture-derived Timer HUD input.
    /// - Returns: Positive minutes for up scroll, negative minutes for down scroll.
    private func signedScrollAmount(for input: TimerHUDInput) -> Int? {
        switch input.kind {
        case .scrollUp:
            TimerHUDInteractionState.stepSize(for: input)
        case .scrollDown:
            -TimerHUDInteractionState.stepSize(for: input)
        default:
            nil
        }
    }

    /// Binding used by Pomodoro controls to edit all durations.
    private var pomodoroDurationBinding: Binding<PomodoroDurations> {
        Binding(
            get: { interactionState.pomodoroDurations },
            set: { interactionState.pomodoroDurations = $0 }
        )
    }

    /// Pomodoro field that is locked because it is currently running.
    private var lockedPomodoroField: PomodoroDurationField? {
        backgroundTimers.pomodoroSession?.currentBlock.durationField
    }

    /// Starts a background timer and closes the HUD.
    private func startTimer() {
        guard backgroundTimers.startTimer(minutes: interactionState.timerDuration) != nil else { return }
        _ = hudController.close(TimerHUDDefinition.hudID)
    }

    /// Starts a background Pomodoro and closes the HUD.
    private func startPomodoro() {
        pomodoroPreferences.save(interactionState.pomodoroDurations)
        justStartedPomodoro = true
        backgroundTimers.startPomodoro(durations: interactionState.pomodoroDurations)
        _ = hudController.close(TimerHUDDefinition.hudID)
    }

    /// Runs the visible Return-style primary action for the mounted HUD mode.
    private func performDefaultAction() {
        switch interactionState.mode {
        case .timer:
            startTimer()
        case .pomodoro:
            guard backgroundTimers.pomodoroSession == nil else { return }
            startPomodoro()
        }
    }

    /// Records Pomodoro hover state.
    /// - Parameters:
    ///   - field: Field whose hover state changed.
    ///   - isHovered: Whether the field is hovered.
    private func setHoveredPomodoroField(_ field: PomodoroDurationField, _ isHovered: Bool) {
        interactionState.setHover(field, isHovered: isHovered)
    }

    /// Records Pomodoro focus state.
    /// - Parameters:
    ///   - field: Field whose focus state changed.
    ///   - isFocused: Whether the field is focused.
    private func setFocusedPomodoroField(_ field: PomodoroDurationField, _ isFocused: Bool) {
        interactionState.setFocus(field, isFocused: isFocused)
    }

    /// Updates the active panel size to match the mounted HUD mode.
    private func updateSizeOverride() {
        hudStore.setSizeOverride(interactionState.sizeOverride, for: TimerHUDDefinition.hudID)
    }
}

/// The original Timer UI, mounted only when the current mode is Timer.
private struct TimerHUDTimerModeView: View {
    /// Currently selected duration in minutes.
    let duration: Int
    /// Size used by the fade overlay to cover the visible Timer HUD area.
    let screenSize: CGSize
    /// Starts the selected timer.
    let startTimer: () -> Void

    var body: some View {
        HStack {
            TimerHUDDurationRail(duration: duration, screenSize: screenSize)

            TimerHUDControlColumn(duration: duration, startTimer: startTimer)
                .frame(width: TimerHUDStyle.timerButtonWidth, height: TimerHUDStyle.windowHeight, alignment: .top)
        }
    }
}

/// Pomodoro setup UI, mounted only when the current mode is Pomodoro.
private struct PomodoroHUDModeView: View {
    /// Editable Pomodoro durations.
    @Binding var durations: PomodoroDurations
    /// Pomodoro field currently under the pointer.
    let hoverField: PomodoroDurationField?
    /// Hover-state callback for duration fields.
    let setHoveredField: (PomodoroDurationField, Bool) -> Void
    /// Focus-state callback for duration fields.
    let setFocusedField: (PomodoroDurationField, Bool) -> Void
    /// Starts the configured Pomodoro.
    let startPomodoro: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: TimerHUDStyle.timerGridGap) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pomodoro")
                    .font(DriftTypography.hudTitle)
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PomodoroDurationField.allCases) { field in
                        PomodoroDurationInputRow(
                            field: field,
                            duration: durationBinding(for: field),
                            setHoveredField: setHoveredField,
                            setFocusedField: setFocusedField
                        )
                    }
                }

                Spacer(minLength: 0)

                DriftButton(
                    variant: .hudPrimary,
                    title: "Start",
                    systemImage: "return",
                    iconPosition: .back,
                    maxWidth: .infinity,
                    action: startPomodoro
                )
            }
            .padding(TimerHUDStyle.pomodoroPanelPadding)
            .frame(width: TimerHUDStyle.pomodoroPanelWidth, height: TimerHUDStyle.pomodoroPanelHeight)
            .background(Color.black)
            .cornerRadius(35)

            if let hoverField {
                TimerHUDDurationRail(
                    duration: durations[hoverField],
                    screenSize: CGSize(
                        width: TimerHUDStyle.timerTickWidth,
                        height: TimerHUDStyle.windowHeight
                    )
                )
                .timerHUDDurationRailTransition()
            }
        }
        .frame(width: TimerHUDStyle.pomodoroPanelWidth + TimerHUDStyle.timerGridGap + TimerHUDStyle.timerTickWidth, height: TimerHUDStyle.pomodoroPanelHeight, alignment: .topLeading)
    }

    /// Creates a binding for one Pomodoro duration field.
    /// - Parameter field: The field to bind.
    /// - Returns: A two-way duration binding.
    private func durationBinding(for field: PomodoroDurationField) -> Binding<Int> {
        Binding(
            get: { durations[field] },
            set: { durations[field] = $0 }
        )
    }
}

/// Pomodoro UI shown while a Pomodoro session is active.
private struct ActivePomodoroHUDModeView: View {
    /// Active Pomodoro session.
    let session: PomodoroSession
    /// Remaining seconds for the running block.
    let remainingSeconds: TimeInterval
    /// Editable future Pomodoro durations.
    @Binding var durations: PomodoroDurations
    /// Pomodoro field currently under the pointer.
    let hoverField: PomodoroDurationField?
    /// Hover-state callback for duration fields.
    let setHoveredField: (PomodoroDurationField, Bool) -> Void
    /// Focus-state callback for duration fields.
    let setFocusedField: (PomodoroDurationField, Bool) -> Void
    /// Toggles pause for the current block.
    let togglePause: () -> Void
    /// Skips the current block.
    let skip: () -> Void
    /// Stops the Pomodoro session.
    let stop: () -> Void


    var body: some View {
        HStack(alignment: .top, spacing: TimerHUDStyle.timerGridGap) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pomodoro")
                    .font(DriftTypography.hudTitle)
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PomodoroDurationField.allCases) { field in
                        if field == session.currentBlock.durationField {
                            ActivePomodoroDurationRow(
                                field: field,
                                displayText: TimerHUDDurationFormatter.formattedSeconds(remainingSeconds),
                                symbolName: session.currentBlock.symbolName,
                                isPaused: session.isPaused,
                                togglePause: togglePause
                            )
                        } else {
                            PomodoroDurationInputRow(
                                field: field,
                                duration: durationBinding(for: field),
                                setHoveredField: setHoveredField,
                                setFocusedField: setFocusedField
                            )
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    DriftButton(
                        variant: .hudSecondary,
                        title: "Skip",
                        systemImage: "forward.fill",
                        maxWidth: .infinity,
                        action: skip
                    )

                    DriftButton(
                        variant: .hudDestructive,
                        title: "Stop",
                        systemImage: "stop.fill",
                        maxWidth: .infinity,
                        action: stop
                    )
                }
            }
            .padding(TimerHUDStyle.pomodoroPanelPadding)
            .frame(width: TimerHUDStyle.pomodoroPanelWidth, height: TimerHUDStyle.pomodoroPanelHeight)
            .background(Color.black)
            .cornerRadius(40)

            if let hoverField,
               hoverField != session.currentBlock.durationField {
                TimerHUDDurationRail(
                    duration: durations[hoverField],
                    screenSize: CGSize(
                        width: TimerHUDStyle.timerTickWidth,
                        height: TimerHUDStyle.windowHeight
                    )
                )
                .timerHUDDurationRailTransition()
            }
        }
        .frame(width: TimerHUDStyle.pomodoroPanelWidth + TimerHUDStyle.timerGridGap + TimerHUDStyle.timerTickWidth, height: TimerHUDStyle.pomodoroPanelHeight, alignment: .topLeading)
    }

    /// Creates a binding for one editable future Pomodoro duration.
    private func durationBinding(for field: PomodoroDurationField) -> Binding<Int> {
        Binding(
            get: { durations[field] },
            set: { durations[field] = $0 }
        )
    }
}

/// Non-editable Pomodoro row for the currently running block.
private struct ActivePomodoroDurationRow: View {
    /// Duration field represented by this row.
    let field: PomodoroDurationField
    /// Text shown for the current block.
    let displayText: String
    /// SF Symbol for the current block.
    let symbolName: String
    /// Whether the block is paused.
    let isPaused: Bool
    /// Toggle pause action.
    let togglePause: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(field.title)
                .drawingGroup()
                .font(DriftTypography.hudFieldLabel)
                .foregroundStyle(Color.tick)

            HStack(spacing: 4) {
                Image(systemName: symbolName)
                    .font(DriftTypography.hudFieldIcon)
                    .foregroundStyle(Color.tick)
                    .frame(width: TimerHUDStyle.pomodoroRowIconWidth, alignment: .center)

                Text(displayText)
                    .drawingGroup()
                    .font(DriftTypography.hudFieldValue)
                    .monospacedDigit()
                    .foregroundStyle(Color.tick)

                Spacer(minLength: 0)

                DriftButton(
                    variant: .hudInlineIcon,
                    systemImage: isPaused ? "play.fill" : "pause.fill",
                    width: 20,
                    action: togglePause
                )
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: TimerHUDStyle.pomodoroInputHeight)
            .background(Color.timerStartbg)
            .clipShape(Capsule())
        }
        .padding([.top, .bottom], 5)
    }
}

/// One editable Pomodoro duration row.
private struct PomodoroDurationInputRow: View {
    /// Duration field represented by this row.
    let field: PomodoroDurationField
    /// Duration in minutes.
    @Binding var duration: Int
    /// Hover-state callback.
    let setHoveredField: (PomodoroDurationField, Bool) -> Void
    /// Focus-state callback.
    let setFocusedField: (PomodoroDurationField, Bool) -> Void

    /// Text currently shown while editing.
    @State private var draft = ""
    /// Whether the pointer is currently over this input.
    @State private var isHovered = false
    /// Whether the text field is currently focused.
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(field.title)
                .drawingGroup()
                .font(DriftTypography.hudFieldLabel)
                .foregroundStyle(Color.white.opacity(contentOpacity))

            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(DriftTypography.hudFieldIcon)
                    .foregroundStyle(Color.white.opacity(contentOpacity))
                    .frame(width: TimerHUDStyle.pomodoroRowIconWidth, alignment: .center)

                Text(draft)
                    .drawingGroup()
                    .font(DriftTypography.hudFieldValue)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(contentOpacity))
                    .focused($isFocused)
                    .onSubmit {
                        commitDraft()
                    }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: TimerHUDStyle.pomodoroInputHeight)
            .background(isFocused || isHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.10))
            .overlay {
                Capsule()
                    .stroke(isFocused ? Color.tick.opacity(0.85) : Color.clear, lineWidth: 2)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .overlay {
                CursorView(cursor: .resizeUpDown)
                    .clipShape(Capsule())
            }
        }
        .padding([.top, .bottom], 5)
        .contentShape(Rectangle())
        .onHover { isHovered in
            self.isHovered = isHovered
            withAnimation {
                setHoveredField(field, isHovered)
            }
        }
        .onAppear {
            draft = TimerHUDDurationFormatter.formatted(duration)
        }
        .onDisappear {
            withAnimation {
                setHoveredField(field, false)
            }
        }
        .onChange(of: duration) { newDuration in
            if !isFocused {
                draft = TimerHUDDurationFormatter.formatted(newDuration)
            }
        }
        .onChange(of: isFocused) { focused in
            withAnimation {
                setFocusedField(field, focused)
            }
            if focused {
                draft = TimerHUDDurationFormatter.formatted(duration)
            } else {
                commitDraft()
            }
        }
    }

    /// Text and icon opacity for default, hover, and focused states.
    private var contentOpacity: Double {
        isHovered || isFocused ? 1 : 0.7
    }

    /// Commits the editable text, reverting invalid input.
    private func commitDraft() {
        guard let parsedDuration = TimerHUDDurationFormatter.parsed(draft) else {
            draft = TimerHUDDurationFormatter.formatted(duration)
            return
        }

        if parsedDuration != duration {
            duration = parsedDuration
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        draft = TimerHUDDurationFormatter.formatted(duration)
    }
}

/// Transparent AppKit view that owns the cursor rect for SwiftUI controls.
private struct CursorView: NSViewRepresentable {
    /// Cursor to show while the pointer is inside the view bounds.
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectView {
        let view = CursorRectView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorRectView, context: Context) {
        nsView.cursor = cursor
    }
}

/// Non-interactive view that registers a cursor rect without stealing clicks.
private final class CursorRectView: NSView {
    /// Cursor to show for this view's bounds.
    var cursor: NSCursor = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Shared scrolling rail used by Timer and Pomodoro duration selection.
private struct TimerHUDDurationRail: View {
    /// Currently selected duration in minutes.
    let duration: Int
    /// Size used by the fade overlay to cover the visible rail area.
    let screenSize: CGSize

    var body: some View {
        HStack(spacing: 8) {
            TimerHUDNumberColumn(
                duration: duration,
            )
            TimerHUDTickColumn(
                duration: duration,
            )
            TimerHUDIndicator()
        }
        .padding([.leading, .trailing], 20)
        .frame(width: TimerHUDStyle.timerTickWidth, height: TimerHUDStyle.windowHeight)
        .background(Color.black)
        .overlay {
            TimerHUDFadeOverlay(screenSize: screenSize)
        }
        .cornerRadius(35)
    }
}

/// Control column showing the current duration and start button.
private struct TimerHUDControlColumn: View {
    /// Currently selected duration in minutes.
    let duration: Int
    /// Starts the selected timer.
    let startTimer: () -> Void

    var body: some View {
        VStack(spacing: TimerHUDStyle.timerGridGap/2) {
            DriftButton(
                variant: .hudDark,
                title: formattedDuration,
                systemImage: "timer",
                iconPosition: .front,
                height: 40,
                maxWidth: .infinity,
            )
            .transaction { transaction in
                transaction.animation = nil
            }
            .drawingGroup()
            
            DriftButton(
                variant: .hudPrimary,
                title: "Start",
                systemImage: "return",
                iconPosition: .back,
                maxWidth: .infinity,
                action: startTimer
            )

            Spacer(minLength: 0)
        }.frame(width: TimerHUDStyle.timerButtonWidth)
    }

    /// Current duration formatted as minutes and seconds.
    private var formattedDuration: String {
        TimerHUDDurationFormatter.formatted(duration)
    }
}

/// Label style for Timer HUD controls with independently sized icons.
private struct TimerHUDControlLabelStyle: LabelStyle {
    /// Icon font used beside control text.
    let iconFont: Font

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(iconFont)
            configuration.title
        }
    }
}

/// Scrolling column of labeled minute values.
private struct TimerHUDNumberColumn: View {
    /// Currently selected duration in minutes.
    let duration: Int


    var body: some View {
        VStack(alignment: .trailing, spacing: TimerHUDStyle.rowSpacing) {
            ForEach(Array(0..<TimerHUDStyle.numberCount), id: \.self) { index in
                let value = index * TimerHUDStyle.numberStep
                Text(String(value))
                    .foregroundStyle(value <= duration ? Color.tick : Color.tickFaded)
                    .font(DriftTypography.timerRailNumber)
                    .frame(height: TimerHUDStyle.numberHeight)
            }
        }
        .drawingGroup()
        .padding([.trailing], 3)
        .padding([.top], TimerHUDStyle.windowHeight / 2 - 10)
        .padding([.bottom], 20)
        .offset(y: durationOffset)
        .frame(height: TimerHUDStyle.windowHeight, alignment: .topTrailing)
    }

    /// Vertical offset that keeps the selected duration aligned with the indicator.
    private var durationOffset: CGFloat {
        -CGFloat(duration) * TimerHUDStyle.durationOffsetStep
    }
}

/// Scrolling column of tick marks representing one-minute increments.
private struct TimerHUDTickColumn: View {
    /// Currently selected duration in minutes.
    let duration: Int

    var body: some View {
        VStack(alignment: .leading, spacing: TimerHUDStyle.tickSpacing) {
            ForEach(0..<TimerHUDStyle.tickCount, id: \.self) { index in
                Rectangle()
                    .frame(height: TimerHUDStyle.tickHeight)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(index <= duration ? Color.tick : Color.tickFaded)
                    .cornerRadius(1)
            }
        }
        .offset(y: durationOffset)
        .padding([.top], TimerHUDStyle.windowHeight / 2 - 1.5)
        .padding([.bottom], 20)
        .frame(
            width: TimerHUDStyle.timerTickWidth * 0.35,
            height: TimerHUDStyle.windowHeight,
            alignment: .topLeading
        )
    }

    /// Vertical offset that keeps the selected tick aligned with the indicator.
    private var durationOffset: CGFloat {
        -CGFloat(duration) * TimerHUDStyle.durationOffsetStep
    }
}

/// Fixed indicator that marks the currently selected duration on the tick rail.
private struct TimerHUDIndicator: View {

    var body: some View {
        VStack {
            Text("􀄦")
                .foregroundStyle(Color.tick)
        }
        .frame(width: TimerHUDStyle.timerTickWidth / 9)
    }
}

/// Vertical fade overlay that hides tick and number overflow at the rail edges.
private struct TimerHUDFadeOverlay: View {
    /// Size of the overlay area.
    let screenSize: CGSize

    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                stops: [
                    .init(color: Color(red: 0, green: 0, blue: 0), location: 0.05),
                    .init(color: Color(red: 0, green: 0, blue: 0, opacity: 0), location: 0.5),
                    .init(color: Color(red: 0, green: 0, blue: 0, opacity: 0), location: 0.5),
                    .init(color: Color(red: 0, green: 0, blue: 0), location: 0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: screenSize.width, height: screenSize.height)
    }
}
