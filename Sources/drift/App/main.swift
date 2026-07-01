import AppKit

// AppKit owns the process lifetime; AppDelegate creates the menu-bar utility and settings window.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
