import AppKit
import CoreGraphics
import SwiftUI

private enum TimerHUDStyle {
    static let tick = Color(
        red: 1.0,
        green: 138.0 / 255,
        blue: 40.0 / 255
    )
    static let tickFaded = tick.opacity(0.5)

    static let numberCount = 20
    static let numberStep = 5
    static let tickCount = numberCount * numberStep
    static let rowSpacing: CGFloat = 35
    static let numberHeight: CGFloat = 20
    static let tickHeight: CGFloat = 3
    static let tickSpacing: CGFloat = (35 + 20 - 3 * 5) / 5
    static let durationOffsetStep: CGFloat = (35 + 20) / 5
}

struct TimerHUDView: View {
    let screenSize: CGSize

    @EnvironmentObject private var hudMessages: HUDMessageBus
    @State private var duration: Int = 0
    @State private var loaded = false

    var body: some View {
        HStack {
            TimerHUDNumberColumn(
                duration: duration,
                screenSize: screenSize
            )
            TimerHUDTickColumn(
                duration: duration,
                screenSize: screenSize
            )
            TimerHUDIndicator(screenSize: screenSize)
        }
        .frame(width: screenSize.width, height: screenSize.height)
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

private struct TimerHUDNumberColumn: View {
    let duration: Int
    let screenSize: CGSize

    var body: some View {
        VStack(alignment: .trailing, spacing: TimerHUDStyle.rowSpacing) {
            ForEach(Array(0..<TimerHUDStyle.numberCount), id: \.self) { index in
                let value = index * TimerHUDStyle.numberStep
                Text(String(value))
                    .foregroundStyle(value <= duration ? TimerHUDStyle.tick : TimerHUDStyle.tickFaded)
                    .font(.system(size: 20))
                    .frame(height: TimerHUDStyle.numberHeight)
            }
        }
        .drawingGroup()
        .padding([.top], screenSize.height / 2 - 10)
        .padding([.bottom], 20)
        .offset(y: durationOffset)
        .frame(height: screenSize.height, alignment: .topTrailing)
    }

    private var durationOffset: CGFloat {
        -CGFloat(duration) * TimerHUDStyle.durationOffsetStep
    }
}

private struct TimerHUDTickColumn: View {
    let duration: Int
    let screenSize: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: TimerHUDStyle.tickSpacing) {
            ForEach(0..<TimerHUDStyle.tickCount, id: \.self) { index in
                Rectangle()
                    .frame(height: TimerHUDStyle.tickHeight)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(index <= duration ? TimerHUDStyle.tick : TimerHUDStyle.tickFaded)
                    .cornerRadius(1)
            }
        }
        .offset(y: durationOffset)
        .padding([.leading], 10)
        .padding([.top], screenSize.height / 2 - 1.5)
        .padding([.bottom], 20)
        .frame(
            width: screenSize.width * 0.4,
            height: screenSize.height,
            alignment: .topLeading
        )
    }

    private var durationOffset: CGFloat {
        -CGFloat(duration) * TimerHUDStyle.durationOffsetStep
    }
}

private struct TimerHUDIndicator: View {
    let screenSize: CGSize

    var body: some View {
        VStack {
            Text("􀄦")
                .foregroundStyle(TimerHUDStyle.tick)
        }
        .frame(width: screenSize.width / 6)
    }
}

private struct TimerHUDFadeOverlay: View {
    let screenSize: CGSize

    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                stops: [
                    .init(color: Color(red: 0, green: 0, blue: 0), location: 0.01),
                    .init(color: Color(red: 0, green: 0, blue: 0, opacity: 0), location: 0.5),
                    .init(color: Color(red: 0, green: 0, blue: 0, opacity: 0), location: 0.5),
                    .init(color: Color(red: 0, green: 0, blue: 0), location: 0.99),
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: screenSize.width, height: screenSize.height)
    }
}
