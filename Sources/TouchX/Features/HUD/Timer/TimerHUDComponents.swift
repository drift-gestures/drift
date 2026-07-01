import AppKit
import CoreGraphics
import SwiftUI

extension Color {
    static let tick = Color(
        red: 1.0,
        green: 138.0 / 255,
        blue: 40.0 / 255
    )

    static let tickFaded = tick.opacity(0.5)

    static let timerStartbg = Color(
        red: 79 / 255,
        green: 45 / 255,
        blue: 20 / 255
    )
}

enum TimerHUDStyle {

    static let numberCount = 20
    static let numberStep = 5
    static let tickCount = numberCount * numberStep
    static let rowSpacing: CGFloat = 35
    static let numberHeight: CGFloat = 20
    static let tickHeight: CGFloat = 3
    static let tickSpacing: CGFloat = (35 + 20 - 3 * 5) / 5
    static let durationOffsetStep: CGFloat = (35 + 20) / 5

    static let windowHeight: CGFloat = 350
    static let timerTickWidth: CGFloat = 180
    static let timerButtonWidth: CGFloat = 140
    static let timerGridGap: CGFloat = 14
    static let controlHeight: CGFloat = 58
    static let controlSpacing: CGFloat = 14
    static let startButtonHeight: CGFloat = 46

}

struct NoButtonAnimationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
            .animation(nil, value: configuration.isPressed)
    }
}

struct TimerHUDView: View {
    let screenSize: CGSize

    @EnvironmentObject private var hudMessages: HUDMessageBus
    @State private var duration: Int = 0
    @State private var loaded = false

    var body: some View {
        HStack {
            HStack {
                TimerHUDNumberColumn(
                    duration: duration,
                )
                Spacer()
                TimerHUDTickColumn(
                    duration: duration,
                )
                Spacer()
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

    private func receiveHUDMessage(_ targetedMessage: TargetedHUDMessage) {
        guard targetedMessage.hudID == TimerHUDDefinition.hudID else { return }

        switch targetedMessage.message {
        case .timerInput(let input):
            receiveTimerHUDInput(input)
        }
    }

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

    private func stepSize(for input: TimerHUDInput) -> Int {
        switch input.kind {
        case .scrollUp, .scrollDown:
            return max(1, Int(input.magnitude * 100))
        default:
            return 0
        }
    }
}

private struct TimerHUDControlColumn: View {
    let duration: Int

    var body: some View {
        VStack(spacing: TimerHUDStyle.controlSpacing) {
            HStack(spacing: 7) {
                Image(systemName: "timer")
                    .font(.system(size: 22, weight: .semibold))

                Text(formattedDuration)
                    .font(.system(size: 24, weight: .medium))
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
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.tick)
                    .frame(width: TimerHUDStyle.timerButtonWidth, height: TimerHUDStyle.startButtonHeight)
                    .background(Color.timerStartbg)
                    .clipShape(Capsule())
            }
            .buttonStyle(NoButtonAnimationStyle())

            Spacer(minLength: 0)
        }.frame(width: TimerHUDStyle.timerButtonWidth)
    }

    private var formattedDuration: String {
        String(format: "%02d:00", duration)
    }
}

private struct TimerHUDNumberColumn: View {
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
        .padding([.top], TimerHUDStyle.windowHeight / 2 - 10)
        .padding([.bottom], 20)
        .offset(y: durationOffset)
        .frame(height: TimerHUDStyle.windowHeight, alignment: .topTrailing)
    }

    private var durationOffset: CGFloat {
        -CGFloat(duration) * TimerHUDStyle.durationOffsetStep
    }
}

private struct TimerHUDTickColumn: View {
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
        .padding([.leading], 10)
        .padding([.top], TimerHUDStyle.windowHeight / 2 - 1.5)
        .padding([.bottom], 20)
        .frame(
            width: TimerHUDStyle.timerTickWidth * 0.4,
            height: TimerHUDStyle.windowHeight,
            alignment: .topLeading
        )
    }

    private var durationOffset: CGFloat {
        -CGFloat(duration) * TimerHUDStyle.durationOffsetStep
    }
}

private struct TimerHUDIndicator: View {

    var body: some View {
        VStack {
            Text("􀄦")
                .foregroundStyle(Color.tick)
        }
        .frame(width: TimerHUDStyle.timerTickWidth / 7)
    }
}

private struct TimerHUDFadeOverlay: View {
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
