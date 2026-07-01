import AppKit
import CoreGraphics
import SwiftUI

/// HUD definition for the Timer HUD surface.
struct TimerHUDDefinition: HudDefinition {
    /// Stable identifier used to register, show, hide, and message the Timer HUD.
    static let hudID = HUDID(rawValue: "timer")

    /// The Timer HUD identifier required by `HudDefinition`.
    let id = hudID
    /// Fixed Timer HUD window size, including the tick rail, gap, and controls.
    let size = CGSize(width: TimerHUDStyle.timerTickWidth + TimerHUDStyle.timerGridGap + TimerHUDStyle.timerButtonWidth, height: TimerHUDStyle.windowHeight)

    /// Positions the Timer HUD near the left side of the visible screen.
    /// - Parameter context: Layout inputs for the current screen.
    /// - Returns: The Timer HUD window origin.
    func position(in context: HUDLayoutContext) -> CGPoint {
        CGPoint(
            x: 20,
            y: context.screenFrame.maxY/2 - size.height/2
        )
    }

    /// Builds the Timer HUD SwiftUI content.
    /// - Parameter context: Render context supplied by the presenter.
    /// - Returns: The Timer HUD view.
    func content(context: HUDContext) -> some View {
        TimerHUDView(screenSize: size)
    }
}
