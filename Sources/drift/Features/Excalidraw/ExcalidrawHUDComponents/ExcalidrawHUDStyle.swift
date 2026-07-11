import CoreGraphics

/// Shared dimensions for the Excalidraw HUD modes.
enum ExcalidrawHUDStyle {
    static let spacing: CGFloat = 5
    static let padding: CGFloat = 20
    static let launcherSize = CGSize(width: 78*8+spacing*7+40, height: 78+8+10+40)
    static let searchSize = CGSize(width: 760, height: 400)
    static let settingsSize = CGSize(width: 560, height: 260)
    static let launcherTopInset: CGFloat = 96
    static let editorTopInset: CGFloat = 72
    static let cornerRadius: CGFloat = 45
    static let itemSize = CGSize(width: 78, height: 78)
    static let thumbnailSize = CGSize(width: 58, height: 42)

    static func editorSize(screenFrame: CGRect) -> CGSize {
        CGSize(
            width: min(screenFrame.width - 96, max(820, screenFrame.width * 0.82)),
            height: min(screenFrame.height - 150, max(600, screenFrame.height * 0.76))
        )
    }
}
