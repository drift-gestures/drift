import Combine
import CoreGraphics
import Foundation

/// Main-actor state used exclusively by the standalone virtual trackpad window.
@MainActor
final class TrackpadMapStore: ObservableObject {
    /// A timestamped trail sample that can fade independently of the latest input frame.
    struct TrailPoint {
        let position: CGPoint
        let recordedAt: Date
    }

    struct Trail: Identifiable {
        let id: Int
        var contact: FingerContact
        var points: [TrailPoint]
    }

    /// A chassis impact rendered as a fading flash along the map's matching edge.
    struct ImpactFlash: Identifiable {
        let id = UUID()
        let region: ImpactRegion
        let intensity: ImpactIntensity
        let recordedAt: Date
    }

    @Published private(set) var trails: [Int: Trail] = [:]
    /// Recently detected chassis impacts still within their visual fade window.
    @Published private(set) var impactFlashes: [ImpactFlash] = []
    /// Controls whether the map's scheduled drawing work should run.
    @Published private(set) var isEnabled = false
    /// The active frame used to render aggregate contact indicators.
    @Published private(set) var snapshot: TrackpadSnapshot?
    /// Continuous display rotation with the bridge's ±π wrapping removed.
    @Published private(set) var displayRotation = 0.0
    /// Accumulated aggregate contact movement used to move the map rails.
    @Published private(set) var scrollPosition = CGPoint.zero

    /// Time a released contact remains visible while its trail fades away.
    static let trailFadeDuration: TimeInterval = 0.5
    /// Time a chassis impact flash remains visible while it fades away.
    static let impactFadeDuration: TimeInterval = 0.6

    private var previousReportedRotation: Double?
    private var previousCenter: CGPoint?

    /// Starts or stops map-only processing and clears retained visual state when hidden.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard !enabled else { return }

        trails.removeAll()
        impactFlashes.removeAll()
        snapshot = nil
        displayRotation = 0
        scrollPosition = .zero
        previousReportedRotation = nil
        previousCenter = nil
    }

    /// Records a detected chassis impact and prunes flashes that have finished fading.
    /// - Parameter impact: The classified tap/slap event to visualize.
    func record(impact: ImpactSnapshot) {
        guard isEnabled else { return }
        let now = Date()
        impactFlashes.removeAll { now.timeIntervalSince($0.recordedAt) >= Self.impactFadeDuration }
        impactFlashes.append(ImpactFlash(region: impact.region, intensity: impact.intensity, recordedAt: impact.timestamp))
    }

    /// Incorporates the latest hardware frame and removes contacts that have lifted.
    func update(with snapshot: TrackpadSnapshot) {
        guard isEnabled else { return }
        let now = Date()
        discardExpiredTrailPoints(before: now.addingTimeInterval(-Self.trailFadeDuration))
        updateAggregateVisuals(with: snapshot)
        self.snapshot = snapshot.contacts.isEmpty ? nil : snapshot

        for contact in snapshot.contacts {
            let point = CGPoint(
                x: contact.normalizedPosition.x,
                y: contact.normalizedPosition.y
            )
            var trail = trails[contact.identifier] ?? Trail(
                id: contact.identifier,
                contact: contact,
                points: []
            )
            trail.contact = contact
            if trail.points.last?.position != point {
                trail.points.append(TrailPoint(position: point, recordedAt: now))
            }
            trails[contact.identifier] = trail
        }
    }

    /// Drops samples that have already completed their visual fade.
    private func discardExpiredTrailPoints(before cutoff: Date) {
        trails = trails.compactMapValues { trail in
            var trail = trail
            trail.points.removeAll { $0.recordedAt < cutoff }
            return trail.points.isEmpty ? nil : trail
        }
    }

    /// Maintains continuous rotation and cumulative two-axis movement for aggregate indicators.
    private func updateAggregateVisuals(with snapshot: TrackpadSnapshot) {
        guard !snapshot.contacts.isEmpty else {
            previousReportedRotation = nil
            previousCenter = nil
            displayRotation = 0
            scrollPosition = .zero
            return
        }

        if snapshot.phase == .began || previousReportedRotation == nil || previousCenter == nil {
            displayRotation = -snapshot.rotation
            scrollPosition = .zero
        } else if let previousReportedRotation, let previousCenter {
            var rotationDelta = snapshot.rotation - previousReportedRotation
            if rotationDelta > .pi {
                rotationDelta -= 2 * .pi
            } else if rotationDelta < -.pi {
                rotationDelta += 2 * .pi
            }
            displayRotation -= rotationDelta
            if snapshot.fingerCount == 2 {
                scrollPosition.x += snapshot.center.x - previousCenter.x
                scrollPosition.y += snapshot.center.y - previousCenter.y
            }
        }

        previousReportedRotation = snapshot.rotation
        previousCenter = snapshot.center
    }
}
