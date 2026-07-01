import Foundation
#if SWIFT_PACKAGE
import driftMultitouch
#endif

/// Copies the C-produced `TXMTTrackpadSnapshot` into Swift-owned values.
final class CTrackpadBridge {
    /// Human-readable startup status shown in the live log.
    private(set) var statusMessage = "Not started"
    /// Closure invoked whenever the C bridge provides a converted Swift snapshot.
    private var snapshotHandler: ((TrackpadSnapshot) -> Void)?

    /// The active bridge instance used by the C callback trampoline.
    nonisolated(unsafe) private static weak var current: CTrackpadBridge?

    /// Registers this bridge instance as the callback target.
    init() {
        Self.current = self
    }

    /// Loads the private multitouch bridge and starts receiving snapshots.
    /// - Parameter snapshotHandler: Closure called with Swift-owned snapshots.
    /// - Returns: `true` when the private bridge loaded and started successfully.
    func start(snapshotHandler: @escaping (TrackpadSnapshot) -> Void) -> Bool {
        let status = TXMTLoad()
        guard status.available else {
            statusMessage = String(cString: status.message)
            return false
        }

        self.snapshotHandler = snapshotHandler
        let didStart = TXMTStart { snapshot in
            CTrackpadBridge.dispatch(snapshot)
        }
        statusMessage = didStart
            ? "C trackpad snapshots active"
            : "C trackpad snapshots failed to start"
        return didStart
    }

    /// Stops the private bridge and releases the current snapshot handler.
    func stop() {
        TXMTStop()
        snapshotHandler = nil
    }

    /// Converts a C snapshot pointer into Swift model values and dispatches it to the handler.
    /// - Parameter pointer: The pointer supplied by the C bridge callback.
    private static func dispatch(_ pointer: UnsafePointer<TXMTTrackpadSnapshot>?) {
        guard let backend = current, let pointer else { return }
        let source = pointer.pointee
        let contactCount = Int(source.contactCount)
        let contacts: [FingerContact]

        if let contactPointer = source.contacts, contactCount > 0 {
            contacts = UnsafeBufferPointer(start: contactPointer, count: contactCount).map { contact in
                FingerContact(
                    identifier: Int(contact.identifier),
                    state: Int(contact.state),
                    fingerID: Int(contact.fingerId),
                    handID: Int(contact.handId),
                    normalizedPosition: ContactVector(x: contact.normalizedX, y: contact.normalizedY),
                    normalizedVelocity: ContactVector(x: contact.normalizedVelocityX, y: contact.normalizedVelocityY),
                    absolutePosition: ContactVector(x: contact.absoluteX, y: contact.absoluteY),
                    absoluteVelocity: ContactVector(x: contact.absoluteVelocityX, y: contact.absoluteVelocityY),
                    size: contact.size,
                    angle: contact.angle,
                    majorAxis: contact.majorAxis,
                    minorAxis: contact.minorAxis,
                    density: contact.density
                )
            }
        } else {
            contacts = []
        }

        let phase: TrackpadPhase
        switch source.phase {
        case TXMTTouchPhaseBegan: phase = .began
        case TXMTTouchPhaseEnded: phase = .ended
        default: phase = .changed
        }

        backend.snapshotHandler?(TrackpadSnapshot(
            contacts: contacts,
            timestamp: source.timestamp,
            frame: Int(source.frame),
            phase: phase,
            center: CGPoint(x: source.centerX, y: source.centerY),
            scale: source.scale,
            rotation: source.rotationRadians
        ))
    }
}
