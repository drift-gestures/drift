import Foundation

/// One raw motion sample copied out of the chassis IMU HID stream, pairing the latest accelerometer
/// reading with the most recent gyroscope reading.
///
/// The accelerometer and gyroscope are separate HID devices that stream independently, so the gyro
/// fields carry the newest gyro report seen at the moment this accelerometer report arrived. At
/// ~800Hz each that pairing is within ~1ms, which is ample for onset-direction analysis.
struct AccelerometerSample: Sendable {
    /// Lateral acceleration in g, positive toward the right edge of the chassis.
    let x: Double
    /// Front-to-back acceleration in g, positive toward the front edge.
    let y: Double
    /// Vertical acceleration in g, positive upward through the deck.
    let z: Double
    /// Angular velocity about the X axis (roll), raw sensor units.
    let gyroX: Double
    /// Angular velocity about the Y axis (pitch), raw sensor units.
    let gyroY: Double
    /// Angular velocity about the Z axis (yaw), raw sensor units.
    let gyroZ: Double
    /// The time the sample was captured.
    let timestamp: Date
}
