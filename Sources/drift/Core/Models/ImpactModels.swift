import CoreGraphics
import Foundation

/// How hard a detected chassis impact was, bucketed from its peak acceleration magnitude.
enum ImpactIntensity: String, Sendable {
    /// A light contact, such as a fingertip tap on the deck or palm rest.
    case tap
    /// A hard contact, such as an open-hand slap.
    case slap
}

/// A coarse, approximate guess at which side of the chassis absorbed an impact.
///
/// A single 3-axis accelerometer cannot truly localize a 2D impact point on the chassis; this is a
/// heuristic derived from the dominant axis and sign of the peak sample, not a calibrated position.
enum ImpactRegion: String, Sendable {
    /// Peak lateral acceleration was negative (impact nearer the left edge).
    case left
    /// Peak lateral acceleration was positive (impact nearer the right edge).
    case right
    /// Peak front-back acceleration was positive (impact nearer the palm rest/front edge).
    case frontPalmRest
    /// Peak front-back acceleration was negative (impact nearer the hinge/back edge).
    case deck
    /// No axis was clearly dominant enough to guess a region.
    case unknown
}

/// Shared mapping from acceleration components to a normalized chassis-map coordinate.
enum ChassisCoordinate {
    /// Edge scale for live tilt, where the raw sample includes a full ~1g of gravity when tilted.
    static let liveEdgeScale = 1.5
    /// Edge scale for the small onset-impulse direction vectors captured during an impact.
    static let impactEdgeScale = 0.4

    /// Projects lateral/front-back acceleration into a normalized `0...1` map coordinate.
    ///
    /// Uses a `tanh` soft clamp so the point always stays on the map and larger forces push it
    /// toward the edges. `x` maps left→right (`0`→`1`); `y` maps so positive front-back values sit
    /// toward the top of the map. This is an approximate heuristic, not a calibrated position.
    /// - Parameters:
    ///   - x: Lateral acceleration in g (positive toward the right edge).
    ///   - y: Front-back acceleration in g (positive toward the front edge).
    ///   - edgeScale: Acceleration in g that maps roughly to the edge of the map.
    /// - Returns: A normalized coordinate with `0.5, 0.5` at center.
    static func normalized(x: Double, y: Double, edgeScale: Double) -> CGPoint {
        CGPoint(
            x: 0.5 + 0.5 * tanh(x / edgeScale),
            y: 0.5 + 0.5 * tanh(y / edgeScale)
        )
    }
}

/// One calibrated chassis zone: a labeled region with the mean onset feature vector measured when
/// tapping it, plus the normalized map position used to display hits classified into it.
struct ChassisZone: Codable, Equatable, Sendable {
    /// Human-readable zone name shown during and after calibration.
    let label: String
    /// Normalized display position (`0...1`, `y` up) at which hits in this zone are drawn.
    let center: CGPoint
    /// Mean onset feature vector (unit accel direction + unit gyro direction) measured while tapping
    /// this zone during calibration. See `ImpactSnapshot.feature`.
    let centroid: [Double]
}

/// A nearest-centroid classifier that assigns a measured onset-direction vector to the calibrated
/// zone whose training taps produced the most similar vector.
///
/// A single accelerometer cannot recover a precise 2D position, but classifying into a few coarse
/// zones is far more robust than regressing a continuous coordinate: it only needs the measured
/// vector to be closest to the right zone's centroid, which tolerates per-tap noise.
struct ChassisCalibration: Codable, Equatable, Sendable {
    /// The calibrated zones, one per guided target.
    let zones: [ChassisZone]

    /// Classifies an onset feature vector to the nearest zone centroid.
    /// - Parameter feature: The onset feature vector from an `ImpactSnapshot`.
    /// - Returns: The closest zone, or `nil` when no zones are calibrated.
    func classify(_ feature: [Double]) -> ChassisZone? {
        zones.min { squaredDistance($0.centroid, feature) < squaredDistance($1.centroid, feature) }
    }

    /// Builds a zone classifier by averaging the feature vectors collected for each guided target.
    /// - Parameter groups: Per-zone label, display center, and the measured feature vectors.
    /// - Returns: The zone model, or `nil` when fewer than two usable zones were collected.
    static func build(groups: [(label: String, center: CGPoint, measurements: [[Double]])]) -> ChassisCalibration? {
        let zones = groups.compactMap { group -> ChassisZone? in
            guard let dimension = group.measurements.first?.count, !group.measurements.isEmpty else { return nil }
            var centroid = [Double](repeating: 0, count: dimension)
            for measurement in group.measurements where measurement.count == dimension {
                for index in 0..<dimension { centroid[index] += measurement[index] }
            }
            let count = Double(group.measurements.count)
            centroid = centroid.map { $0 / count }
            return ChassisZone(label: group.label, center: group.center, centroid: centroid)
        }
        guard zones.count >= 2 else { return nil }
        return ChassisCalibration(zones: zones)
    }

    /// Squared Euclidean distance between two equal-length feature vectors.
    private func squaredDistance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return .greatestFiniteMagnitude }
        return zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
    }
}

/// A semantic, reduced impact event produced by `ImpactDetector` from raw accelerometer samples.
struct ImpactSnapshot: Sendable {
    /// The classified impact force.
    let intensity: ImpactIntensity
    /// The approximate chassis region, or `.unknown` when no axis dominated the impact.
    let region: ImpactRegion
    /// Approximate normalized position of the impact on the chassis map, each axis in `0...1`
    /// with `0.5` at center. Derived from the onset impulse direction, so it is a coarse heuristic
    /// (see `ImpactRegion`) unless a `ChassisCalibration` is applied downstream.
    let coordinate: CGPoint
    /// The onset feature used for zone classification: the unit accel direction concatenated with
    /// the unit gyro direction (`[accelX, accelY, gyroX, gyroY, gyroZ]`, each sub-vector normalized).
    /// Normalizing each part separately makes the feature scale-free so the classifier weighs the
    /// accelerometer and gyroscope evenly, and gyro sign cleanly separates off-center left/right hits.
    let feature: [Double]
    /// How many impacts occurred within the detector's repeat window, including this one.
    let repeatCount: Int
    /// The peak acceleration magnitude in g that triggered detection.
    let peakMagnitude: Double
    /// The time the impact was detected.
    let timestamp: Date
}
