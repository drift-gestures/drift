import CoreGraphics
import Foundation

/// A two-dimensional value reported by the multitouch bridge.
struct ContactVector: Hashable, Sendable {
    /// The horizontal component of the vector.
    let x: Double
    /// The vertical component of the vector.
    let y: Double
}

/// One finger contact copied from a private-framework multitouch frame.
struct FingerContact: Identifiable, Hashable, Sendable {
    /// A stable contact identifier for the lifetime of the touch.
    let identifier: Int
    /// The raw contact state reported by the underlying C bridge.
    let state: Int
    /// The per-hand finger identifier supplied by the multitouch framework.
    let fingerID: Int
    /// The hand identifier supplied by the multitouch framework.
    let handID: Int
    /// The finger position normalized into the trackpad's unit coordinate space.
    let normalizedPosition: ContactVector
    /// The normalized velocity vector for the contact.
    let normalizedVelocity: ContactVector
    /// The absolute contact position reported by the hardware bridge.
    let absolutePosition: ContactVector
    /// The absolute velocity vector reported by the hardware bridge.
    let absoluteVelocity: ContactVector
    /// The contact's approximate touch size.
    let size: Double
    /// The contact's reported angle in radians.
    let angle: Double
    /// The major axis length of the contact ellipse.
    let majorAxis: Double
    /// The minor axis length of the contact ellipse.
    let minorAxis: Double
    /// The reported contact density or pressure-like value.
    let density: Double

    /// The SwiftUI identity for the contact, backed by the bridge identifier.
    var id: Int { identifier }
}

/// The lifecycle phase for a trackpad snapshot stream.
enum TrackpadPhase: String, Sendable {
    /// A new gesture or contact sequence has begun.
    case began
    /// An existing gesture or contact sequence changed.
    case changed
    /// The gesture or contact sequence ended.
    case ended
}

/// A complete Swift-owned copy of the C bridge's `TXMTTrackpadSnapshot`.
struct TrackpadSnapshot: Sendable {
    /// All finger contacts present in this frame.
    let contacts: [FingerContact]
    /// The source timestamp for the frame.
    let timestamp: TimeInterval
    /// The monotonically increasing frame number reported by the bridge.
    let frame: Int
    /// The lifecycle phase represented by this frame.
    let phase: TrackpadPhase
    /// The normalized center point of the active contacts.
    let center: CGPoint
    /// The aggregate scale value reported for the active contacts.
    let scale: Double
    /// The aggregate rotation, in radians, reported for the active contacts.
    let rotation: Double

    /// The number of contacts contained in the snapshot.
    var fingerCount: Int { contacts.count }
}

/// The latest trackpad state shared with HUD layout and diagnostics.
struct TrackpadState: Sendable {
    /// The newest snapshot received from the bridge, or `nil` before input begins.
    var latestSnapshot: TrackpadSnapshot?

    /// An empty trackpad state used before any snapshots are available.
    static let idle = TrackpadState(latestSnapshot: nil)
}
