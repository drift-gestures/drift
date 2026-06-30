import AppKit
import CoreGraphics
import SwiftUI

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
