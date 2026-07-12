import Foundation

/// Names the low-level input backend currently available to drift.
enum InputBackendName: String {
    case enhanced = "Private multitouch bridge"
    case inactive = "Inactive"
}

/// An action performed after a custom gesture is recognized.
enum CustomGestureAction: Codable, Equatable, Sendable {
    case keyboardShortcut(keyCode: UInt16, modifiers: Set<KeyboardModifier>)
    case openApplication(bundleIdentifier: String)
    case runScript(executableURL: URL, arguments: [String])
}

/// A built-in gesture shape configured by the user.
enum BasicGestureKind: Codable, Equatable, Sendable {
    case edgeSwipe(edge: TrackpadEdge, direction: GestureDirection)
    case pinch(direction: PinchDirection)
    case rotate(direction: RotationDirection)
}

enum TrackpadEdge: String, Codable, Sendable { case top, bottom, left, right }
enum EdgeSegment: String, Codable, CaseIterable, Sendable { case leading, middle, trailing }
enum GestureDirection: String, Codable, Sendable { case up, down, left, right }
enum PinchDirection: String, Codable, Sendable { case inward, outward }
enum RotationDirection: String, Codable, Sendable { case clockwise, counterclockwise }

struct BasicGesture: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var kind: BasicGestureKind
    var edgeSegment: EdgeSegment
    var activationThreshold: Double
    var edgeProximity: Double
    var action: CustomGestureAction

    init(
        id: UUID,
        name: String,
        kind: BasicGestureKind,
        edgeSegment: EdgeSegment = .middle,
        activationThreshold: Double,
        edgeProximity: Double,
        action: CustomGestureAction
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.edgeSegment = edgeSegment
        self.activationThreshold = activationThreshold
        self.edgeProximity = edgeProximity
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, edgeSegment, activationThreshold, edgeProximity, action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(BasicGestureKind.self, forKey: .kind)
        edgeSegment = try container.decodeIfPresent(EdgeSegment.self, forKey: .edgeSegment) ?? .middle
        activationThreshold = try container.decode(Double.self, forKey: .activationThreshold)
        edgeProximity = try container.decode(Double.self, forKey: .edgeProximity)
        action = try container.decode(CustomGestureAction.self, forKey: .action)
    }
}

/// One normalized point in an advanced-gesture recording.
struct AdvancedGestureSample: Codable, Equatable, Sendable {
    var centerX: Double
    var centerY: Double
    var fingerCount: Int
    var spread: Double
    var velocityX: Double
    var velocityY: Double
    var pressure: Double
}

struct AdvancedGestureRecording: Codable, Equatable, Sendable {
    /// Fixed-size normalized samples. Recordings are normally resampled to 96 points.
    var samples: [AdvancedGestureSample]
}

struct AdvancedGesture: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var recordings: [AdvancedGestureRecording]
    var isPositionallyAware: Bool
    /// Maximum normalized DTW distance accepted as a match.
    var acceptanceThreshold: Double
    var action: CustomGestureAction
}

/// The persisted custom-gesture collection and the one global advanced-gesture key.
struct CustomGestureLibrary: Codable, Equatable, Sendable {
    var basicGestures: [BasicGesture] = []
    var advancedGestures: [AdvancedGesture] = []
    var advancedActivationModifiers: Set<KeyboardModifier> = [.control]

    private enum CodingKeys: String, CodingKey {
        case basicGestures, advancedGestures, advancedActivationModifiers, advancedActivationModifier
    }

    init(
        basicGestures: [BasicGesture] = [],
        advancedGestures: [AdvancedGesture] = [],
        advancedActivationModifiers: Set<KeyboardModifier> = [.control]
    ) {
        self.basicGestures = basicGestures
        self.advancedGestures = advancedGestures
        self.advancedActivationModifiers = advancedActivationModifiers.isEmpty ? [.control] : advancedActivationModifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basicGestures = try container.decodeIfPresent([BasicGesture].self, forKey: .basicGestures) ?? []
        advancedGestures = try container.decodeIfPresent([AdvancedGesture].self, forKey: .advancedGestures) ?? []
        if let modifiers = try container.decodeIfPresent(Set<KeyboardModifier>.self, forKey: .advancedActivationModifiers),
           !modifiers.isEmpty {
            advancedActivationModifiers = modifiers
        } else if let modifier = try container.decodeIfPresent(KeyboardModifier.self, forKey: .advancedActivationModifier) {
            advancedActivationModifiers = [modifier]
        } else {
            advancedActivationModifiers = [.control]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(basicGestures, forKey: .basicGestures)
        try container.encode(advancedGestures, forKey: .advancedGestures)
        try container.encode(advancedActivationModifiers, forKey: .advancedActivationModifiers)
    }
}
