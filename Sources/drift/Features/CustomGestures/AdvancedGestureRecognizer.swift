import CoreGraphics
import Foundation

enum AdvancedGestureRecognizer {
    static let sampleCount = 96

    static func recording(from snapshots: [TrackpadSnapshot], positionallyAware: Bool) -> AdvancedGestureRecording? {
        let populated = snapshots.filter { !$0.contacts.isEmpty }
        guard populated.count >= 2 else { return nil }
        var samples = populated.map(sample(from:))
        if !positionallyAware, let origin = samples.first {
            for index in samples.indices {
                samples[index].centerX -= origin.centerX
                samples[index].centerY -= origin.centerY
            }
        }
        return AdvancedGestureRecording(samples: resample(samples, count: sampleCount))
    }

    static func bestMatch(
        recording: AdvancedGestureRecording,
        gestures: [AdvancedGesture]
    ) -> (gesture: AdvancedGesture, distance: Double)? {
        matches(recording: recording, gestures: gestures).min { $0.distance < $1.distance }
    }

    static func bestAcceptedMatch(
        recording: AdvancedGestureRecording,
        gestures: [AdvancedGesture]
    ) -> (gesture: AdvancedGesture, distance: Double)? {
        matches(recording: recording, gestures: gestures)
            .filter { $0.distance <= $0.gesture.acceptanceThreshold }
            .min { $0.distance < $1.distance }
    }

    private static func matches(
        recording: AdvancedGestureRecording,
        gestures: [AdvancedGesture]
    ) -> [(gesture: AdvancedGesture, distance: Double)] {
        gestures.compactMap { gesture -> (AdvancedGesture, Double)? in
            guard !gesture.recordings.isEmpty else { return nil }
            let candidate = gesture.isPositionallyAware ? recording : positionIndependent(recording)
            let distance = gesture.recordings.map { dtw(candidate.samples, $0.samples) }.min() ?? .infinity
            return (gesture, distance)
        }
    }

    private static func sample(from snapshot: TrackpadSnapshot) -> AdvancedGestureSample {
        let count = max(snapshot.contacts.count, 1)
        let spread = snapshot.contacts.reduce(0.0) { partial, contact in
            let dx = contact.normalizedPosition.x - snapshot.center.x
            let dy = contact.normalizedPosition.y - snapshot.center.y
            return partial + sqrt(dx * dx + dy * dy)
        } / Double(count)
        let velocity = snapshot.contacts.reduce((x: 0.0, y: 0.0)) { partial, contact in
            (partial.x + contact.normalizedVelocity.x, partial.y + contact.normalizedVelocity.y)
        }
        let pressure = snapshot.contacts.reduce(0.0) { $0 + $1.density } / Double(count)
        return AdvancedGestureSample(
            centerX: snapshot.center.x,
            centerY: snapshot.center.y,
            fingerCount: snapshot.contacts.count,
            spread: spread,
            velocityX: velocity.x / Double(count),
            velocityY: velocity.y / Double(count),
            pressure: pressure
        )
    }

    private static func positionIndependent(_ recording: AdvancedGestureRecording) -> AdvancedGestureRecording {
        guard let origin = recording.samples.first else { return recording }
        return AdvancedGestureRecording(samples: recording.samples.map {
            var sample = $0
            sample.centerX -= origin.centerX
            sample.centerY -= origin.centerY
            return sample
        })
    }

    private static func resample(_ samples: [AdvancedGestureSample], count: Int) -> [AdvancedGestureSample] {
        guard samples.count > 1, count > 1 else { return samples }
        return (0..<count).map { outputIndex in
            let position = Double(outputIndex) * Double(samples.count - 1) / Double(count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, samples.count - 1)
            return interpolate(samples[lower], samples[upper], amount: position - Double(lower))
        }
    }

    private static func interpolate(_ lhs: AdvancedGestureSample, _ rhs: AdvancedGestureSample, amount: Double) -> AdvancedGestureSample {
        func value(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        return AdvancedGestureSample(
            centerX: value(lhs.centerX, rhs.centerX), centerY: value(lhs.centerY, rhs.centerY),
            fingerCount: amount < 0.5 ? lhs.fingerCount : rhs.fingerCount,
            spread: value(lhs.spread, rhs.spread),
            velocityX: value(lhs.velocityX, rhs.velocityX), velocityY: value(lhs.velocityY, rhs.velocityY),
            pressure: value(lhs.pressure, rhs.pressure)
        )
    }

    /// DTW with a Sakoe-Chiba band, keeping comparison near linear for fixed-size recordings.
    private static func dtw(_ lhs: [AdvancedGestureSample], _ rhs: [AdvancedGestureSample]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return .infinity }
        let band = max(abs(lhs.count - rhs.count), max(lhs.count, rhs.count) / 8)
        var previous = Array(repeating: Double.infinity, count: rhs.count + 1)
        previous[0] = 0
        for i in 1...lhs.count {
            var current = Array(repeating: Double.infinity, count: rhs.count + 1)
            let lower = max(1, i - band)
            let upper = min(rhs.count, i + band)
            if lower <= upper {
                for j in lower...upper {
                    current[j] = sampleDistance(lhs[i - 1], rhs[j - 1]) + min(previous[j], current[j - 1], previous[j - 1])
                }
            }
            previous = current
        }
        return previous[rhs.count] / Double(max(lhs.count, rhs.count))
    }

    private static func sampleDistance(_ lhs: AdvancedGestureSample, _ rhs: AdvancedGestureSample) -> Double {
        let position = hypot(lhs.centerX - rhs.centerX, lhs.centerY - rhs.centerY)
        let velocity = hypot(lhs.velocityX - rhs.velocityX, lhs.velocityY - rhs.velocityY)
        let fingers = Double(abs(lhs.fingerCount - rhs.fingerCount))
        // DTW already accounts for timing variation. Velocity remains a supporting signal, but a
        // low weight prevents natural speed differences from overpowering path and finger shape.
        return position + 0.08 * velocity + 0.5 * fingers + 0.3 * abs(lhs.spread - rhs.spread) + 0.1 * abs(lhs.pressure - rhs.pressure)
    }
}
