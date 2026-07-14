import Foundation

/// Which side of the chassis an impact came from, used to scope a tap action.
///
/// `.any` matches impacts from either side (and is the only side that can match when the chassis
/// map is uncalibrated, since side classification needs a calibration).
enum ImpactSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case left
    case right

    var id: Self { self }

    /// A human-readable label for pickers and summaries.
    var displayName: String {
        switch self {
        case .any: "Either side"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// Which impact force a tap action requires, or `nil`/`.any` for any force.
enum ImpactIntensityFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case tap
    case slap

    var id: Self { self }

    var displayName: String {
        switch self {
        case .any: "Tap or slap"
        case .tap: "Tap"
        case .slap: "Slap"
        }
    }

    /// Whether this filter accepts a concrete detected intensity.
    /// - Parameter intensity: The classified intensity of a detected impact.
    /// - Returns: `true` when the filter is `.any` or matches the intensity exactly.
    func matches(_ intensity: ImpactIntensity) -> Bool {
        switch self {
        case .any: true
        case .tap: intensity == .tap
        case .slap: intensity == .slap
        }
    }
}

/// The condition that fires a tap action: a force, a side, and how many impacts in quick succession.
struct TapActionTrigger: Codable, Equatable, Sendable {
    /// Required impact force, or `.any`.
    var intensity: ImpactIntensityFilter
    /// Required chassis side, or `.any`.
    var side: ImpactSide
    /// Number of impacts in the burst (single/double/triple), clamped to `1...3`.
    var count: Int

    /// A short human-readable description used in list rows.
    var summary: String {
        let countWord = switch count {
        case 1: "Single"
        case 2: "Double"
        case 3: "Triple"
        default: "\(count)×"
        }
        let force = intensity == .any ? "tap/slap" : intensity.displayName.lowercased()
        let sideText = side == .any ? "" : " (\(side.displayName.lowercased()))"
        return "\(countWord) \(force)\(sideText)"
    }
}

/// A user-configured binding from a tap/slap trigger to an action.
struct TapActionBinding: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var trigger: TapActionTrigger
    var action: CustomGestureAction

    init(id: UUID = UUID(), name: String, trigger: TapActionTrigger, action: CustomGestureAction) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.action = action
    }
}

/// The persisted collection of tap/slap action bindings.
struct TapActionLibrary: Codable, Equatable, Sendable {
    var bindings: [TapActionBinding] = []
}
