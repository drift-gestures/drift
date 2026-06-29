import AppKit
import CoreGraphics
import SwiftUI

let colors = [
    "tick": Color(
        red: 255/255,
        green: 138/255,
        blue: 40/255,
    ),
    "tick-faded": Color(
        red: 255/255,
        green: 138/255,
        blue: 40/255,
        opacity: 0.5
    )
]

extension Color {
    static let tick = Color(
        red: 1.0,
        green: 138.0 / 255,
        blue: 40.0 / 255
    )

    static let tickFaded = tick.opacity(0.5)
}

struct TimerHUDDefinition: HudDefinition {
    static let hudID = HUDID(rawValue: "timer")

    let id = hudID
    let size = CGSize(width: 180, height: 350)

    func position(in context: HUDLayoutContext) -> CGPoint {
        CGPoint(
            x: 20,
            y: context.screenFrame.maxY/2 - size.height/2
        )
    }

    func content(context: HUDContext) -> some View {
        TimerHUDView(screenSize: size)
    }
}

private struct TimerHUDView: View {
    
    let screenSize: CGSize;
    @EnvironmentObject private var hudStore: HUDStore
    @State var duration: Int = 0;
    @State private var loaded = false
    
    var body: some View {

        HStack {
            VStack(alignment: .trailing, spacing: 35) {
                ForEach(Array(0..<20), id: \.self) { i in
                    Text(
                        String(i*5),
                    ).foregroundStyle(
                        ((i*5 <= duration) ? colors["tick"] : colors["tick-faded"])!
                    ).font(.system(size: 20))
                        .frame(height: 20)
                }
            }
            .drawingGroup()
            .padding([.top], screenSize.height/2-10)
            .padding([.bottom], 20)
            .offset(y: CGFloat(-duration*(35+20)/5))
            .frame(height: screenSize.height, alignment: .topTrailing)
            VStack(alignment: .leading, spacing: (35+20-3*5)/5) {
                ForEach(0..<20*5, id: \.self) { i in
                    Rectangle()
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(
                            ((i <= duration) ? colors["tick"] : colors["tick-faded"])!
                        )
                        .cornerRadius(1)
                }
            }
            .offset(y: CGFloat(-duration*(35+20)/5))
            .padding([.leading], 10)
            .padding([.top], screenSize.height/2-1.5)
            .padding([.bottom], 20)
            .frame(width: screenSize.width*(0.4), height: screenSize.height, alignment: .topLeading)
            VStack() {
                Text("􀄦").foregroundStyle(colors["tick"]!)
            }
            .frame(width: screenSize.width/6)
        }

        .frame(width: screenSize.width, height: screenSize.height)
        .background(Color.black)
        .overlay() {
            Rectangle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color(red: 0, green: 0, blue: 0), location: 0.01),
                        .init(color: Color(red: 0, green: 0, blue: 0, opacity: 0), location: 0.5),
                        .init(color: Color(red: 0, green: 0, blue: 0, opacity: 0), location: 0.5),
                        .init(color: Color(red: 0, green: 0, blue: 0), location: 0.99   ),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: screenSize.width, height: screenSize.height)
        }
        .cornerRadius(40)
        .scaleEffect(loaded ? 1 : 0.8)
        .opacity(loaded ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                loaded = true
            }
        }
        .onReceive(hudStore.$latestTimerHUDInput.compactMap { $0 }) { input in
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
