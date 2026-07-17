import Foundation

/// Names the low-level input backend currently available to drift.
enum InputBackendName: String {
    case enhanced = "Private multitouch bridge"
    case inactive = "Inactive"
}

/// An action performed after a custom gesture is recognized.
enum CustomGestureAction: Codable, Equatable, Sendable {
    /// The legacy, persisted single-shortcut representation. Keep this case so existing saved
    /// gesture libraries continue to decode without a migration.
    case keyboardShortcut(keyCode: UInt16, modifiers: Set<KeyboardModifier>)
    /// An ordered collection of shortcut presses with a shared delay between adjacent steps.
    case keyboardShortcutSequence(steps: [KeyboardShortcut], interStepInterval: TimeInterval)
    case openApplication(bundleIdentifier: String)
    case openURL(url: String)
    case runScript(executableURL: URL, arguments: [String])
}

/// One recorded key press in a keyboard-shortcut sequence.
struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: Set<KeyboardModifier>

    init(keyCode: UInt16, modifiers: Set<KeyboardModifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

extension CustomGestureAction {
    /// The configured URL when this action contains a valid, scheme-bearing destination.
    var urlToOpen: URL? {
        guard case .openURL(let value) = self else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue), url.scheme != nil else { return nil }
        return url
    }
}

/// A built-in gesture shape configured by the user.
enum BasicGestureKind: Codable, Equatable, Sendable {
    case edgeSwipe(edge: TrackpadEdge, direction: GestureDirection)
    case pinch(direction: PinchDirection)
    case rotate(direction: RotationDirection)

    var activationThresholdRange: ClosedRange<Double> {
        switch self {
        case .edgeSwipe, .pinch:
            0.03...0.50
        case .rotate:
            0.03...(.pi)
        }
    }
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
    var scopedApplicationBundleIdentifiers: Set<String>

    init(
        id: UUID,
        name: String,
        kind: BasicGestureKind,
        edgeSegment: EdgeSegment = .middle,
        activationThreshold: Double,
        edgeProximity: Double,
        action: CustomGestureAction,
        scopedApplicationBundleIdentifiers: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.edgeSegment = edgeSegment
        self.activationThreshold = activationThreshold
        self.edgeProximity = edgeProximity
        self.action = action
        self.scopedApplicationBundleIdentifiers = scopedApplicationBundleIdentifiers
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, edgeSegment, activationThreshold, edgeProximity, action
        case scopedApplicationBundleIdentifiers
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
        scopedApplicationBundleIdentifiers = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .scopedApplicationBundleIdentifiers
        ) ?? []
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
    var scopedApplicationBundleIdentifiers: Set<String>

    init(
        id: UUID,
        name: String,
        recordings: [AdvancedGestureRecording],
        isPositionallyAware: Bool,
        acceptanceThreshold: Double,
        action: CustomGestureAction,
        scopedApplicationBundleIdentifiers: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.recordings = recordings
        self.isPositionallyAware = isPositionallyAware
        self.acceptanceThreshold = acceptanceThreshold
        self.action = action
        self.scopedApplicationBundleIdentifiers = scopedApplicationBundleIdentifiers
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, recordings, isPositionallyAware, acceptanceThreshold, action
        case scopedApplicationBundleIdentifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        recordings = try container.decode([AdvancedGestureRecording].self, forKey: .recordings)
        isPositionallyAware = try container.decode(Bool.self, forKey: .isPositionallyAware)
        acceptanceThreshold = try container.decode(Double.self, forKey: .acceptanceThreshold)
        action = try container.decode(CustomGestureAction.self, forKey: .action)
        scopedApplicationBundleIdentifiers = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .scopedApplicationBundleIdentifiers
        ) ?? []
    }
}

protocol ApplicationScopedGesture {
    var scopedApplicationBundleIdentifiers: Set<String> { get }
}

extension ApplicationScopedGesture {
    var isGlobal: Bool { scopedApplicationBundleIdentifiers.isEmpty }

    func applies(to focusedApplicationBundleIdentifier: String?) -> Bool {
        guard !isGlobal else { return true }
        guard let focusedApplicationBundleIdentifier else { return false }
        return scopedApplicationBundleIdentifiers.contains(focusedApplicationBundleIdentifier)
    }

    func isScoped(to focusedApplicationBundleIdentifier: String?) -> Bool {
        !isGlobal && applies(to: focusedApplicationBundleIdentifier)
    }
}

extension BasicGesture: ApplicationScopedGesture {}
extension AdvancedGesture: ApplicationScopedGesture {}

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
