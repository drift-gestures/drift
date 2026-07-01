import CoreGraphics
import Foundation

struct ContactVector: Hashable, Sendable {
    let x: Double
    let y: Double
}

/// One contact copied out of a private-framework frame.
struct FingerContact: Identifiable, Hashable, Sendable {
    let identifier: Int
    let state: Int
    let fingerID: Int
    let handID: Int
    let normalizedPosition: ContactVector
    let normalizedVelocity: ContactVector
    let absolutePosition: ContactVector
    let absoluteVelocity: ContactVector
    let size: Double
    let angle: Double
    let majorAxis: Double
    let minorAxis: Double
    let density: Double

    var id: Int { identifier }
}

enum TrackpadPhase: String, Sendable {
    case began
    case changed
    case ended
}

/// A complete Swift-owned copy of the C bridge's `TXMTTrackpadSnapshot`.
struct TrackpadSnapshot: Sendable {
    let contacts: [FingerContact]
    let timestamp: TimeInterval
    let frame: Int
    let phase: TrackpadPhase
    let center: CGPoint
    let scale: Double
    let rotation: Double

    var fingerCount: Int { contacts.count }
}

struct TrackpadState: Sendable {
    var latestSnapshot: TrackpadSnapshot?

    static let idle = TrackpadState(latestSnapshot: nil)
}
