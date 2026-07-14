import CoreGraphics
import Foundation

// Detection approach adapted from AbdullahFID/MacSlapApp's SlapDetector. The empirically clean
// separator between a deliberate tap/slap and ordinary chassis vibration (typing, desk knocks) is
// that a real impact produces HIGH linear acceleration AND HIGH jerk in the same instant, while
// typing produces one or the other but never both together. Gravity is removed with a slow EMA so
// only the impulsive component is tested, an adaptive noise floor tracks the resting baseline, a
// short peak-hold captures the true peak force, and a refractory period stops one impact's ringing
// from retriggering.

/// Reduces a stream of raw `AccelerometerSample`s into semantic `ImpactSnapshot` tap/slap events.
final class ImpactDetector {
    /// Peak linear-acceleration (gravity removed) needed to qualify as an impact, in g.
    private let ampThreshold: Double
    /// Jerk index (Σ|Δlinear accel|·rate across axes) needed alongside amplitude, in g/s.
    private let jerkThreshold: Double
    /// Amplitude so high it is accepted even without the jerk test, in g.
    private let hardAmpThreshold: Double
    /// Amplitude at or above which an impact is classified as a slap rather than a tap, in g.
    private let slapThreshold: Double
    /// Adaptive-floor multiplier: linear magnitude must also exceed `noiseFloor + sigmaMult·noiseDev`.
    private let sigmaMult: Double
    /// Assumed IMU delivery rate used to scale the jerk index and time-based windows.
    private let sampleRate: Double
    /// Gravity EMA retention factor (~0.5s time constant at 805Hz).
    private let gravityAlpha: Double
    /// Ignore window after a detection so chassis ringing cannot retrigger.
    private let refractory: TimeInterval
    /// Peak-hold window used to capture the true peak force of an impact.
    private let impactWindow: TimeInterval
    /// Onset window used to capture strike direction before chassis resonance smears it.
    private let onsetWindow: TimeInterval
    /// Maximum gap between impacts that still counts as the same repeat sequence.
    private let repeatWindow: TimeInterval

    // Gravity estimate (per axis) and previous linear sample used for the jerk index.
    private var gravityX = 0.0, gravityY = 0.0, gravityZ = 0.0
    private var gravityInitialized = false
    private var previousLinearX = 0.0, previousLinearY = 0.0, previousLinearZ = 0.0
    private var havePreviousLinear = false

    // Adaptive baseline noise floor.
    private var noiseFloor = 0.0
    private var noiseDev = 0.0
    private var noiseInitialized = false

    // Impact state machine.
    private enum State { case idle, inImpact }
    private var state: State = .idle
    private var peakAmplitude = 0.0
    // Direction is taken from the summed onset impulse, not the peak: the peak is dominated by
    // chassis resonance/ringing whose direction no longer reflects where the strike landed, while
    // the first few samples of the impulse still point along the true strike direction. Onset gyro
    // is summed alongside because an off-center strike rotates the chassis, and that angular-velocity
    // sign separates left/right far more cleanly than linear acceleration at the sensor's point.
    private var onsetX = 0.0, onsetY = 0.0
    private var onsetGyroX = 0.0, onsetGyroY = 0.0, onsetGyroZ = 0.0
    private var onsetSamples = 0
    private var impactSamples = 0
    private var refractoryCount = 0
    private var warmupCount = 0

    // Repeat-sequence grouping (drift-specific, layered on top of the base detector).
    private var lastImpactDate: Date?
    private var pendingRepeatCount = 0

    /// Creates an impact detector with tunable thresholds.
    init(
        ampThreshold: Double = 0.15,
        jerkThreshold: Double = 30.0,
        hardAmpThreshold: Double = 1.0,
        slapThreshold: Double = 0.4,
        sigmaMult: Double = 7.0,
        sampleRate: Double = 805.0,
        gravityAlpha: Double = 0.9975,
        refractory: TimeInterval = 0.14,
        impactWindow: TimeInterval = 0.05,
        onsetWindow: TimeInterval = 0.006,
        repeatWindow: TimeInterval = 0.5
    ) {
        self.ampThreshold = ampThreshold
        self.jerkThreshold = jerkThreshold
        self.hardAmpThreshold = hardAmpThreshold
        self.slapThreshold = slapThreshold
        self.sigmaMult = sigmaMult
        self.sampleRate = sampleRate
        self.gravityAlpha = gravityAlpha
        self.refractory = refractory
        self.impactWindow = impactWindow
        self.onsetWindow = onsetWindow
        self.repeatWindow = repeatWindow
    }

    /// Feeds one raw sample through the detector.
    /// - Parameter sample: The latest accelerometer sample.
    /// - Returns: A completed impact snapshot when a peak-held impact ends on this sample.
    func process(_ sample: AccelerometerSample) -> ImpactSnapshot? {
        // 1) Track gravity and derive the linear (impulsive) acceleration and its magnitude.
        if !gravityInitialized {
            gravityX = sample.x; gravityY = sample.y; gravityZ = sample.z
            gravityInitialized = true
        }
        gravityX = gravityAlpha * gravityX + (1 - gravityAlpha) * sample.x
        gravityY = gravityAlpha * gravityY + (1 - gravityAlpha) * sample.y
        gravityZ = gravityAlpha * gravityZ + (1 - gravityAlpha) * sample.z
        let linearX = sample.x - gravityX
        let linearY = sample.y - gravityY
        let linearZ = sample.z - gravityZ
        let linearMagnitude = (linearX * linearX + linearY * linearY + linearZ * linearZ).squareRoot()

        // 2) Jerk index: summed absolute per-axis change scaled by the sample rate.
        var jerk = 0.0
        if havePreviousLinear {
            jerk = (abs(linearX - previousLinearX) + abs(linearY - previousLinearY) + abs(linearZ - previousLinearZ)) * sampleRate
        }
        previousLinearX = linearX; previousLinearY = linearY; previousLinearZ = linearZ
        havePreviousLinear = true

        // 3) Warm up so the gravity estimate settles before anything is detected.
        warmupCount += 1
        if warmupCount < Int(sampleRate * 0.3) { return nil }

        // 4) Adaptive noise floor, frozen while the signal is elevated so an impact cannot inflate it.
        let elevated = linearMagnitude > (noiseFloor + 4 * noiseDev + 0.02)
        if !noiseInitialized {
            noiseFloor = linearMagnitude; noiseDev = 0.01; noiseInitialized = true
        } else if !elevated {
            let floorAlpha = 0.999
            noiseFloor = floorAlpha * noiseFloor + (1 - floorAlpha) * linearMagnitude
            noiseDev = floorAlpha * noiseDev + (1 - floorAlpha) * abs(linearMagnitude - noiseFloor)
        }
        let dynamicAmp = max(ampThreshold, noiseFloor + sigmaMult * noiseDev)

        // 5) Refractory: swallow samples for a short window after a detection.
        if refractoryCount > 0 { refractoryCount -= 1; return nil }

        // 6) State machine.
        switch state {
        case .idle:
            let impulsive = linearMagnitude >= dynamicAmp && jerk >= jerkThreshold
            let bigHit = linearMagnitude >= hardAmpThreshold
            if impulsive || bigHit {
                state = .inImpact
                peakAmplitude = linearMagnitude
                onsetX = linearX; onsetY = linearY
                onsetGyroX = sample.gyroX; onsetGyroY = sample.gyroY; onsetGyroZ = sample.gyroZ
                onsetSamples = 1
                impactSamples = 0
            }
            return nil

        case .inImpact:
            impactSamples += 1
            if linearMagnitude > peakAmplitude {
                peakAmplitude = linearMagnitude
            }
            // Accumulate direction only during the brief onset window, before resonance sets in.
            let onsetWindowSamples = max(1, Int(onsetWindow * sampleRate))
            if onsetSamples < onsetWindowSamples {
                onsetX += linearX; onsetY += linearY
                onsetGyroX += sample.gyroX; onsetGyroY += sample.gyroY; onsetGyroZ += sample.gyroZ
                onsetSamples += 1
            }
            let windowSamples = max(1, Int(impactWindow * sampleRate))
            let ended = linearMagnitude < dynamicAmp * 0.5 || impactSamples >= windowSamples
            guard ended else { return nil }

            state = .idle
            refractoryCount = Int(refractory * sampleRate)
            return makeSnapshot(at: sample.timestamp)
        }
    }

    /// Builds an impact snapshot from the current peak-hold state and updates repeat grouping.
    /// - Parameter timestamp: The time the impact ended.
    /// - Returns: The completed impact snapshot.
    private func makeSnapshot(at timestamp: Date) -> ImpactSnapshot {
        let isRepeat = lastImpactDate.map { timestamp.timeIntervalSince($0) <= repeatWindow } ?? false
        pendingRepeatCount = isRepeat ? pendingRepeatCount + 1 : 1
        lastImpactDate = timestamp

        // Average the onset impulse so a single noisy sample cannot swing the direction.
        let divisor = Double(max(onsetSamples, 1))
        let directionX = onsetX / divisor
        let directionY = onsetY / divisor

        // Feature = unit accel direction (2D) + unit gyro direction (3D), each normalized separately
        // so accel and gyro contribute on equal footing regardless of their very different scales.
        let accelUnit = normalize2(directionX, directionY)
        let gyroUnit = normalize3(onsetGyroX / divisor, onsetGyroY / divisor, onsetGyroZ / divisor)
        let feature = [accelUnit.0, accelUnit.1, gyroUnit.0, gyroUnit.1, gyroUnit.2]

        return ImpactSnapshot(
            intensity: peakAmplitude >= slapThreshold ? .slap : .tap,
            region: region(forX: directionX, y: directionY),
            coordinate: ChassisCoordinate.normalized(x: directionX, y: directionY, edgeScale: ChassisCoordinate.impactEdgeScale),
            feature: feature,
            repeatCount: pendingRepeatCount,
            peakMagnitude: peakAmplitude,
            timestamp: timestamp
        )
    }

    /// Normalizes a 2D vector to unit length, returning zeros when the vector is degenerate.
    private func normalize2(_ x: Double, _ y: Double) -> (Double, Double) {
        let magnitude = (x * x + y * y).squareRoot()
        guard magnitude > 1e-9 else { return (0, 0) }
        return (x / magnitude, y / magnitude)
    }

    /// Normalizes a 3D vector to unit length, returning zeros when the vector is degenerate.
    private func normalize3(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
        let magnitude = (x * x + y * y + z * z).squareRoot()
        guard magnitude > 1e-9 else { return (0, 0, 0) }
        return (x / magnitude, y / magnitude, z / magnitude)
    }

    /// Classifies a coarse chassis region from the dominant axis and sign of the peak linear accel.
    /// - Parameters:
    ///   - x: Peak lateral linear acceleration.
    ///   - y: Peak front-back linear acceleration.
    /// - Returns: The best-guess region, or `.unknown` when no axis clearly dominates.
    private func region(forX x: Double, y: Double) -> ImpactRegion {
        let absX = abs(x)
        let absY = abs(y)
        let dominantAxisMargin = 1.3

        if absX >= absY * dominantAxisMargin {
            return x < 0 ? .left : .right
        }
        if absY >= absX * dominantAxisMargin {
            return y > 0 ? .frontPalmRest : .deck
        }
        return .unknown
    }
}
