import CoreGraphics
import SwiftUI

/// A stable identifier for a HUD surface.
struct HUDID: Hashable, RawRepresentable, ExpressibleByStringLiteral, Sendable {
    /// The string value used as the HUD's registry key.
    let rawValue: String

    /// Creates an identifier from its persisted or registry string.
    /// - Parameter rawValue: The unique string key for the HUD.
    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates an identifier from a string literal.
    /// - Parameter value: The literal string key for the HUD.
    init(stringLiteral value: StringLiteralType) {
        rawValue = value
    }
}

/// Origin of a HUD session.
enum HUDSessionSource: Sendable {
    /// A real listener-owned gesture opened the HUD.
    case listener
    /// A temporary testing injection opened the HUD.
    case testing
}

/// Placeholder for per-HUD state stored by `HUDStore`.
struct HUDState: Sendable {}

/// Runtime information used to size and position HUD windows.
struct HUDLayoutContext: Sendable {
    /// The current mouse location in screen coordinates.
    let mousePosition: CGPoint
    /// The visible frame of the screen that owns the HUD.
    let screenFrame: CGRect
    /// The latest trackpad state available to layout code.
    let trackpadState: TrackpadState
}

/// All runtime information passed into a HUD definition when rendering content.
struct HUDContext: Sendable {
    /// Layout inputs such as screen geometry, pointer location, and trackpad state.
    let layout: HUDLayoutContext
    /// The custom state associated with the HUD instance.
    let state: HUDState
}

/// Describes a HUD surface that can be presented in its own floating window.
protocol HudDefinition {
    /// The SwiftUI view type produced by this HUD.
    associatedtype Content: View

    /// The stable identifier used to register, show, hide, and route messages to the HUD.
    var id: HUDID { get }
    /// The fixed content size for the HUD window.
    var size: CGSize { get }
    /// Computes the HUD window origin for the supplied layout context.
    /// - Parameter context: The current screen, pointer, and trackpad layout inputs.
    /// - Returns: The top-left origin to use for the HUD window.
    func position(in context: HUDLayoutContext) -> CGPoint
    /// Builds the HUD's SwiftUI content for the supplied runtime context.
    /// - Parameter context: Layout and custom state for this render pass.
    /// - Returns: The HUD content view.
    @MainActor @ViewBuilder func content(context: HUDContext) -> Content
}
