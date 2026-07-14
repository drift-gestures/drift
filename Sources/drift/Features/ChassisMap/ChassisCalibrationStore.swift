import Combine
import CoreGraphics
import Foundation

/// Owns the chassis map's learned calibration and the guided tap-each-corner calibration flow.
@MainActor
final class ChassisCalibrationStore: ObservableObject {
    /// One physical corner the user is asked to tap, with its known normalized map coordinate.
    struct Target: Identifiable {
        let id = UUID()
        let label: String
        let normalized: CGPoint
    }

    /// In-progress calibration state while the user taps the guided targets.
    struct Session {
        var targetIndex: Int
        var collected: [(measured: [Double], targetIndex: Int)]
        var samplesForCurrentTarget: Int
    }

    /// Spots tapped during calibration, ordered as the user is guided through them. Only left/right
    /// are used: the back-of-chassis signal is too weak to separate, but the lateral axis (tapping
    /// the left vs right front palm rest) is the one that classifies reliably. Normalized
    /// coordinates follow the chassis map's convention: `y` up, `x` right.
    static let targets: [Target] = [
        Target(label: "Left palm rest", normalized: CGPoint(x: 0.2, y: 0.5)),
        Target(label: "Right palm rest", normalized: CGPoint(x: 0.8, y: 0.5))
    ]
    /// Taps collected per target before advancing, averaged to reject per-tap noise.
    static let samplesPerTarget = 5
    /// UserDefaults key under which the fitted calibration is persisted as JSON.
    private static let storageKey = "drift.chassisCalibration"

    /// The active calibration applied to impacts, or `nil` when uncalibrated.
    @Published private(set) var calibration: ChassisCalibration?
    /// The current guided session, or `nil` when not calibrating.
    @Published private(set) var session: Session?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            calibration = try? JSONDecoder().decode(ChassisCalibration.self, from: data)
        }
    }

    /// Whether a calibration has been fitted and is currently applied.
    var isCalibrated: Bool { calibration != nil }

    /// The target the user should tap next, or `nil` when no session is active.
    var currentTarget: Target? {
        guard let session, session.targetIndex < Self.targets.count else { return nil }
        return Self.targets[session.targetIndex]
    }

    /// Begins a fresh guided calibration session at the first target.
    func startCalibration() {
        session = Session(targetIndex: 0, collected: [], samplesForCurrentTarget: 0)
    }

    /// Cancels an in-progress session without changing the stored calibration.
    func cancelCalibration() {
        session = nil
    }

    /// Clears the stored calibration and returns to the uncalibrated onset-direction projection.
    func resetCalibration() {
        calibration = nil
        session = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Feeds one detected impact's onset feature into the active session, advancing as targets fill
    /// and building the classifier once every target has been sampled.
    /// - Parameter feature: The onset feature vector from an `ImpactSnapshot`.
    func collect(feature: [Double]) {
        guard var session, currentTarget != nil else { return }
        session.collected.append((measured: feature, targetIndex: session.targetIndex))
        session.samplesForCurrentTarget += 1

        if session.samplesForCurrentTarget >= Self.samplesPerTarget {
            session.targetIndex += 1
            session.samplesForCurrentTarget = 0
        }
        self.session = session

        if session.targetIndex >= Self.targets.count {
            finish(with: session.collected)
        }
    }

    /// Builds and persists a zone classifier from the collected samples, then ends the session.
    /// - Parameter samples: All measured/target-index pairs collected across every target.
    private func finish(with samples: [(measured: [Double], targetIndex: Int)]) {
        let groups = Self.targets.enumerated().map { index, target in
            (
                label: target.label,
                center: target.normalized,
                measurements: samples.filter { $0.targetIndex == index }.map(\.measured)
            )
        }
        if let built = ChassisCalibration.build(groups: groups) {
            calibration = built
            if let data = try? JSONEncoder().encode(built) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
        session = nil
    }
}
