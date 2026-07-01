import AppKit

/// Shared AppKit application instance for the menu-bar utility.
let app = NSApplication.shared
/// Application delegate that configures drift's menu, input bridge, HUDs, and live log.
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
