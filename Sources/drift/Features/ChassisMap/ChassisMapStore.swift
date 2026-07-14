import Combine
import CoreGraphics
import Foundation

/// Main-actor state used exclusively by the standalone chassis accelerometer map window.
@MainActor
final class ChassisMapStore: ObservableObject {
    /// A detected impact rendered as a fading dot at its approximate chassis coordinate.
    struct ImpactMarker: Identifiable {
        let id = UUID()
        let coordinate: CGPoint
        let intensity: ImpactIntensity
        let peakMagnitude: Double
        let recordedAt: Date
    }

    /// Whether the map is visible and should process samples.
    @Published private(set) var isEnabled = false
    /// The latest raw accelerometer sample, used for the live crosshair and numeric readout.
    @Published private(set) var latestSample: AccelerometerSample?
    /// Smoothed live position of the crosshair, each axis in `0...1` with `0.5` at center.
    @Published private(set) var livePosition = CGPoint(x: 0.5, y: 0.5)
    /// Recently detected impacts still within their visual fade window.
    @Published private(set) var impactMarkers: [ImpactMarker] = []
    /// Calibrated zone centers drawn as faint guides so snapped hits read as zones.
    @Published private(set) var zoneCenters: [CGPoint] = []

    /// Time an impact dot remains visible while it fades away.
    static let impactFadeDuration: TimeInterval = 1.2
    /// Smoothing factor for the live crosshair so raw sensor jitter does not make it vibrate.
    private static let positionSmoothing = 0.25

    /// Starts or stops map processing and clears retained visual state when hidden.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard !enabled else { return }
        latestSample = nil
        livePosition = CGPoint(x: 0.5, y: 0.5)
        impactMarkers.removeAll()
    }

    /// Incorporates one throttled raw accelerometer sample into the live crosshair position.
    /// - Parameter sample: The latest raw accelerometer sample in g.
    func update(with sample: AccelerometerSample) {
        guard isEnabled else { return }
        latestSample = sample
        let target = ChassisCoordinate.normalized(x: sample.x, y: sample.y, edgeScale: ChassisCoordinate.liveEdgeScale)
        livePosition = CGPoint(
            x: livePosition.x + (target.x - livePosition.x) * Self.positionSmoothing,
            y: livePosition.y + (target.y - livePosition.y) * Self.positionSmoothing
        )
        pruneExpiredMarkers()
    }

    /// Records a detected impact as a fading coordinate dot.
    /// - Parameters:
    ///   - impact: The classified tap/slap event to visualize.
    ///   - coordinate: The resolved display coordinate (calibrated when a calibration is applied,
    ///     otherwise the impact's uncalibrated onset projection).
    func record(impact: ImpactSnapshot, at coordinate: CGPoint) {
        guard isEnabled else { return }
        pruneExpiredMarkers()
        impactMarkers.append(ImpactMarker(
            coordinate: coordinate,
            intensity: impact.intensity,
            peakMagnitude: impact.peakMagnitude,
            recordedAt: impact.timestamp
        ))
    }

    /// Updates the calibrated zone guide positions shown on the map.
    /// - Parameter centers: Normalized zone centers, or empty when uncalibrated.
    func setZoneCenters(_ centers: [CGPoint]) {
        guard zoneCenters != centers else { return }
        zoneCenters = centers
    }

    /// Drops impact markers that have finished their visual fade.
    private func pruneExpiredMarkers() {
        let now = Date()
        impactMarkers.removeAll { now.timeIntervalSince($0.recordedAt) >= Self.impactFadeDuration }
    }
}
