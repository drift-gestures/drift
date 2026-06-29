import CoreGraphics
import SwiftUI

struct HUDID: Hashable, RawRepresentable, ExpressibleByStringLiteral, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        rawValue = value
    }
}

struct HUDState: Sendable {}

struct HUDLayoutContext: Sendable {
    let mousePosition: CGPoint
    let screenFrame: CGRect
    let trackpadState: TrackpadState
}

struct HUDContext: Sendable {
    let layout: HUDLayoutContext
    let state: HUDState
}

protocol HudDefinition {
    associatedtype Content: View

    var id: HUDID { get }
    var size: CGSize { get }
    func position(in context: HUDLayoutContext) -> CGPoint
    @MainActor @ViewBuilder func content(context: HUDContext) -> Content
}
