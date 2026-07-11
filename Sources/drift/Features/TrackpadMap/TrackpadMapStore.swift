import Combine
import CoreGraphics
import Foundation

/// Main-actor state used exclusively by the standalone virtual trackpad window.
@MainActor
final class TrackpadMapStore: ObservableObject {
    struct Trail: Identifiable {
        let id: Int
        var contact: FingerContact
        var points: [CGPoint]
    }

    @Published private(set) var trails: [Int: Trail] = [:]

    private let maximumTrailPointCount = 80

    /// Incorporates the latest hardware frame and removes contacts that have lifted.
    func update(with snapshot: TrackpadSnapshot) {
        let activeIdentifiers = Set(snapshot.contacts.map(\.identifier))
        trails = trails.filter { activeIdentifiers.contains($0.key) }

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
            if trail.points.last != point {
                trail.points.append(point)
                if trail.points.count > maximumTrailPointCount {
                    trail.points.removeFirst(trail.points.count - maximumTrailPointCount)
                }
            }
            trails[contact.identifier] = trail
        }

        if snapshot.phase == .ended, snapshot.contacts.isEmpty {
            trails.removeAll()
        }
    }
}
