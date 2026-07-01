/// Names the low-level input backend currently available to drift.
enum InputBackendName: String {
    /// The private multitouch bridge is active and can stream enhanced trackpad frames.
    case enhanced = "Private multitouch bridge"
    /// No input backend is currently active.
    case inactive = "Inactive"
}
