import Foundation
import IOKit
import IOKit.hid

// This file is the only place that touches the undocumented chassis-accelerometer HID device.
//
// Approach adapted from the reverse-engineering in AbdullahFID/MacSlapApp and
// olvvier/apple-silicon-accelerometer. Two non-obvious points that this implementation depends on:
//
//   1. We match the device with IOServiceGetMatchingServices + IOHIDDeviceCreate rather than
//      IOHIDManager. IOHIDManager device access requires Developer ID signing to succeed, which the
//      locally "Sign to Run Locally" drift build does not have; the direct IOService path does not.
//   2. The IMU does not stream until it is powered on. Power/reporting state lives on the
//      AppleSPUHIDDriver service, not the IOHIDDevice wrapper, so `wakeSensorDrivers()` must set
//      SensorPropertyPowerState/ReportingState on every driver service or the input-report callback
//      never fires (open still succeeds, which is what made the first implementation look silent).
//
// The device reports one opaque vendor-defined array element per frame: a 22-byte report with X/Y/Z
// as little-endian Int32 Q16.16 fixed point at byte offsets 6/10/14 (confirmed via
// `ioreg -rc AppleSPUHIDDevice -l`, product "accel", usage page 0xFF00, usage 3).

/// Reads the internal MEMS accelerometer and gyroscope exposed as vendor-defined IOKit HID devices
/// on Apple Silicon Macs and streams paired raw samples to Swift.
final class AccelerometerBridge: @unchecked Sendable {
    /// Vendor usage page under which the Sensor Processing Unit publishes its HID devices.
    private static let targetUsagePage = 0xFF00
    /// Vendor usage identifying the accelerometer device within that usage page.
    private static let accelUsage = 3
    /// Vendor usage identifying the gyroscope device within that usage page.
    private static let gyroUsage = 9
    /// Q16.16 fixed-point divisor that converts raw sensor units to approximate g.
    private static let accelScale = 65536.0
    /// Report buffer capacity; reports are 22 bytes but we over-allocate defensively.
    private static let reportBufferSize = 256

    /// Human-readable startup status shown in the live log.
    private(set) var statusMessage = "Not started"

    private var accelDevice: IOHIDDevice?
    private var gyroDevice: IOHIDDevice?
    private var accelBuffer: UnsafeMutablePointer<UInt8>?
    private var gyroBuffer: UnsafeMutablePointer<UInt8>?
    private var hidThread: Thread?
    private var threadShouldRun = false
    private var sampleHandler: ((AccelerometerSample) -> Void)?
    // Most recent gyro reading, paired with each accelerometer report as it arrives.
    private var latestGyro: (x: Double, y: Double, z: Double) = (0, 0, 0)

    /// Finds, wakes, opens, and begins streaming from the chassis accelerometer and gyroscope.
    /// - Parameter sampleHandler: Closure called with each converted Swift-owned sample.
    /// - Returns: `true` when the accelerometer was found, opened, and scheduled successfully. The
    ///   gyroscope is best-effort: its absence degrades location accuracy but does not fail startup.
    func start(sampleHandler: @escaping (AccelerometerSample) -> Void) -> Bool {
        // Wake the SPU sensor drivers up front so the IMU is already streaming by the time the
        // input-report callbacks are attached below.
        wakeSensorDrivers()

        guard let matching = IOServiceMatching("AppleSPUHIDDevice") else {
            statusMessage = "Could not create AppleSPUHIDDevice matching dictionary."
            return false
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            statusMessage = "No AppleSPUHIDDevice services found on this Mac."
            return false
        }
        defer { IOObjectRelease(iterator) }

        // A single iterator pass collects both the accel (usage 3) and gyro (usage 9) services.
        var accelService: io_service_t = 0
        var gyroService: io_service_t = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            switch primaryUsage(of: service) {
            case Self.accelUsage where accelService == 0: accelService = service; IOObjectRetain(service)
            case Self.gyroUsage where gyroService == 0: gyroService = service; IOObjectRetain(service)
            default: break
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        defer {
            if accelService != 0 { IOObjectRelease(accelService) }
            if gyroService != 0 { IOObjectRelease(gyroService) }
        }

        guard accelService != 0, let accel = IOHIDDeviceCreate(kCFAllocatorDefault, accelService),
              IOHIDDeviceOpen(accel, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            statusMessage = "No accelerometer device found or it could not be opened."
            return false
        }
        accelDevice = accel
        self.sampleHandler = sampleHandler

        // The gyroscope is optional: pair it in when present for far better left/right separation.
        if gyroService != 0, let gyro = IOHIDDeviceCreate(kCFAllocatorDefault, gyroService),
           IOHIDDeviceOpen(gyro, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
            gyroDevice = gyro
        }

        // Power/reporting state lives on the driver service, not the opened devices, so wake again
        // now that they are open or the callbacks can still stay silent.
        wakeSensorDrivers()

        let context = Unmanaged.passUnretained(self).toOpaque()
        accelBuffer = registerReportCallback(on: accel, callback: Self.accelReportCallback, context: context)
        if let gyro = gyroDevice {
            gyroBuffer = registerReportCallback(on: gyro, callback: Self.gyroReportCallback, context: context)
        }

        // Service the callbacks on a dedicated background run loop. The main run loop stalls during
        // menu tracking and other UI work, which would pause sensor delivery and drop fast impacts.
        threadShouldRun = true
        let devices = [accel, gyroDevice].compactMap { $0 }
        let thread = Thread { [weak self] in
            guard let runLoop = CFRunLoopGetCurrent() else { return }
            devices.forEach { IOHIDDeviceScheduleWithRunLoop($0, runLoop, CFRunLoopMode.defaultMode.rawValue) }
            while self?.threadShouldRun == true {
                CFRunLoopRunInMode(.defaultMode, 0.25, true)
            }
            devices.forEach {
                IOHIDDeviceUnscheduleFromRunLoop($0, runLoop, CFRunLoopMode.defaultMode.rawValue)
                IOHIDDeviceClose($0, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }
        thread.name = "drift.accelerometer"
        thread.stackSize = 512 * 1024
        hidThread = thread
        thread.start()

        statusMessage = gyroDevice == nil
            ? "Chassis accelerometer active (~805Hz); gyroscope unavailable."
            : "Chassis accelerometer + gyroscope active (~805Hz)."
        return true
    }

    /// Signals the background thread to unschedule and close, and releases retained state.
    func stop() {
        threadShouldRun = false
        hidThread = nil
        accelDevice = nil
        gyroDevice = nil
        sampleHandler = nil
        accelBuffer?.deallocate(); accelBuffer = nil
        gyroBuffer?.deallocate(); gyroBuffer = nil
    }

    /// Allocates a report buffer and registers a callback on a device, returning the buffer to own.
    private func registerReportCallback(
        on device: IOHIDDevice,
        callback: @escaping IOHIDReportCallback,
        context: UnsafeMutableRawPointer
    ) -> UnsafeMutablePointer<UInt8> {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportBufferSize)
        buffer.initialize(repeating: 0, count: Self.reportBufferSize)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.reportBufferSize, callback, context)
        return buffer
    }

    /// Reads the `PrimaryUsage` property of an SPU HID service.
    private func primaryUsage(of service: io_service_t) -> Int {
        var properties: Unmanaged<CFMutableDictionary>?
        IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard let dictionary = properties?.takeRetainedValue() as? [String: Any],
              dictionary["PrimaryUsagePage"] as? Int == Self.targetUsagePage else { return -1 }
        return dictionary["PrimaryUsage"] as? Int ?? -1
    }

    /// Powers on the IMU by setting reporting/power-state properties on every `AppleSPUHIDDriver`
    /// service. On Apple Silicon the driver, not the IOHIDDevice wrapper, owns the sensor's power
    /// state, so this is the step that actually makes the sensor stream reports.
    private func wakeSensorDrivers() {
        guard let matching = IOServiceMatching("AppleSPUHIDDriver") else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            for (key, value) in [
                ("SensorPropertyReportingState", Int32(1)),
                ("SensorPropertyPowerState", Int32(1)),
                ("ReportInterval", Int32(1000))
            ] {
                var mutableValue = value
                if let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &mutableValue) {
                    IORegistryEntrySetCFProperty(service, key as CFString, number)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    /// C-compatible trampoline invoked by IOKit for every raw accelerometer report.
    private static let accelReportCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context else { return }
        Unmanaged<AccelerometerBridge>.fromOpaque(context).takeUnretainedValue()
            .handleAccel(report: report, length: length)
    }

    /// C-compatible trampoline invoked by IOKit for every raw gyroscope report.
    private static let gyroReportCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context else { return }
        Unmanaged<AccelerometerBridge>.fromOpaque(context).takeUnretainedValue()
            .handleGyro(report: report, length: length)
    }

    /// Stores the latest gyroscope reading (raw units) to be paired with the next accel report.
    private func handleGyro(report: UnsafePointer<UInt8>, length: CFIndex) {
        guard length >= 18 else { return }
        let data = UnsafeBufferPointer(start: report, count: Int(length))
        latestGyro = (
            Double(Self.readInt32LE(data, at: 6)),
            Double(Self.readInt32LE(data, at: 10)),
            Double(Self.readInt32LE(data, at: 14))
        )
    }

    /// Parses one raw accelerometer report, pairs it with the latest gyro reading, and forwards it.
    /// - Parameters:
    ///   - report: Pointer to the raw report bytes owned by IOKit for the callback's duration.
    ///   - length: Number of valid bytes in the report.
    private func handleAccel(report: UnsafePointer<UInt8>, length: CFIndex) {
        guard length >= 18 else { return }
        let data = UnsafeBufferPointer(start: report, count: Int(length))
        let x = Double(Self.readInt32LE(data, at: 6)) / Self.accelScale
        let y = Double(Self.readInt32LE(data, at: 10)) / Self.accelScale
        let z = Double(Self.readInt32LE(data, at: 14)) / Self.accelScale

        // Reject frames outside a plausible magnitude band; the sensor occasionally emits
        // status/keep-alive reports that decode to nonsense in the accelerometer axes.
        let magnitude = (x * x + y * y + z * z).squareRoot()
        guard magnitude > 0.2, magnitude < 25.0 else { return }

        let gyro = latestGyro
        sampleHandler?(AccelerometerSample(
            x: x, y: y, z: z,
            gyroX: gyro.x, gyroY: gyro.y, gyroZ: gyro.z,
            timestamp: Date()
        ))
    }

    /// Reads a little-endian 32-bit signed integer out of a raw byte buffer.
    /// - Parameters:
    ///   - data: The byte buffer to read from.
    ///   - offset: The byte offset of the least-significant byte.
    /// - Returns: The decoded value, or `0` when the offset is out of range.
    private static func readInt32LE(_ data: UnsafeBufferPointer<UInt8>, at offset: Int) -> Int32 {
        guard offset + 3 < data.count else { return 0 }
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(data[offset + index]) << (8 * index)
        }
        return Int32(bitPattern: value)
    }
}
