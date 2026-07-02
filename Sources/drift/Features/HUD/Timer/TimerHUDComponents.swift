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
    static let timerButtonWidth: CGFloat = 140
    /// Horizontal gap between the tick rail and controls.
    static let timerGridGap: CGFloat = 14
    /// Height of the current-duration control capsule.
    static let controlHeight: CGFloat = 58
    /// Vertical spacing between controls in the control column.
    static let controlSpacing: CGFloat = 14
    /// Height of the start button.
    static let startButtonHeight: CGFloat = 46

}

/// Button style that disables the default pressed opacity/animation changes.
struct NoButtonAnimationStyle: ButtonStyle {
    /// Returns the button label without applying a pressed-state animation.
    /// - Parameter configuration: SwiftUI button style configuration.
    /// - Returns: The unanimated button label.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
            .animation(nil, value: configuration.isPressed)
    }
}

/// Root SwiftUI view for the Timer HUD.
struct TimerHUDView: View {
    /// Size used by the fade overlay to cover the visible Timer HUD area.
    let screenSize: CGSize

    /// Bus that delivers Timer HUD input messages.
    @EnvironmentObject private var hudMessages: HUDMessageBus
    /// Currently selected duration in minutes.
    @State private var duration: Int = 0
    /// Whether the initial appearance animation has completed.
    @State private var loaded = false

    var body: some View {
        HStack {
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
            .cornerRadius(40)
            .scaleEffect(loaded ? 1 : 0.8)
            .opacity(loaded ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) {
                    loaded = true
                }
            }
            .onReceive(hudMessages.messages) { message in
                receiveHUDMessage(message)
            }
            TimerHUDControlColumn(duration: duration)
                .frame(width: TimerHUDStyle.timerButtonWidth, height: TimerHUDStyle.windowHeight, alignment: .top)
        }
    }

    /// Handles a targeted HUD message if it belongs to the Timer HUD.
    /// - Parameter targetedMessage: The message and destination HUD identifier.
    private func receiveHUDMessage(_ targetedMessage: TargetedHUDMessage) {
        guard targetedMessage.hudID == TimerHUDDefinition.hudID else { return }

        switch targetedMessage.message {
        case .timerInput(let input):
            receiveTimerHUDInput(input)
        }
    }

    /// Applies Timer HUD input to the selected duration.
    /// - Parameter input: Gesture-derived Timer HUD input.
    private func receiveTimerHUDInput(_ input: TimerHUDInput) {
        let nextDuration: Int
        switch input.kind {
        case .scrollUp:
            nextDuration = min(100, duration + stepSize(for: input))
        case .scrollDown:
            nextDuration = max(0, duration - stepSize(for: input))
        default:
            return
        }

        guard nextDuration != duration else { return }
        
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation {
            duration = nextDuration
        }
    }

    /// Converts a gesture input magnitude into a duration step.
    /// - Parameter input: The gesture-derived input to size.
    /// - Returns: The number of minutes to add or remove.
    private func stepSize(for input: TimerHUDInput) -> Int {
        switch input.kind {
        case .scrollUp, .scrollDown:
            return max(1, Int(input.magnitude * 100))
        default:
            return 0
        }
    }
}

/// Control column showing the current duration and start button.
private struct TimerHUDControlColumn: View {
    /// Currently selected duration in minutes.
    let duration: Int

    var body: some View {
        VStack(spacing: TimerHUDStyle.controlSpacing) {
            HStack(spacing: 7) {
                Image(systemName: "timer")
                    .font(.system(size: 22, weight: .semibold))

                Text(formattedDuration)
                    .font(.system(size: 22, weight: .medium))
                    .monospacedDigit()
                    .transaction { transaction in
                            transaction.animation = nil
                        }
            }
            .foregroundStyle(Color.tick)
            .frame(maxWidth: .infinity)
            .frame(height: TimerHUDStyle.controlHeight)
            .background(Color.black)
            .clipShape(Capsule())

            Button(action: {}) {
                Text("Start")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.tick)
                    .frame(width: TimerHUDStyle.timerButtonWidth, height: TimerHUDStyle.startButtonHeight)
                    .background(Color.timerStartbg)
                    .clipShape(Capsule())
            }
            .buttonStyle(NoButtonAnimationStyle())

            Spacer(minLength: 0)
        }.frame(width: TimerHUDStyle.timerButtonWidth)
    }

    /// Current duration formatted as minutes and seconds.
    private var formattedDuration: String {
        String(format: "%02d:00", duration)
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
                    .font(.system(size: 20))
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
