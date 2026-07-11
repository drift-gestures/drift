import Foundation

/// Stable modes rendered by the single Excalidraw HUD.
enum ExcalidrawHUDMode: Equatable, Sendable {
    /// Compact top launcher with actions and recents.
    case launcher
    /// Search surface for filtering local drawings.
    case search
    /// Full drawing editor for one local document.
    case editor(documentID: String)
}

/// Per-drawing theme preference.
enum ExcalidrawThemePreference: String, Codable, Equatable, Sendable {
    /// Follow the current macOS appearance.
    case system
    /// Always open and preview this drawing in light mode.
    case light
    /// Always open and preview this drawing in dark mode.
    case dark

    /// Resolves a stored preference into a concrete render theme.
    func resolved(systemTheme: ExcalidrawResolvedTheme) -> ExcalidrawResolvedTheme {
        switch self {
        case .system:
            systemTheme
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

/// Concrete Excalidraw render theme.
enum ExcalidrawResolvedTheme: String, Codable, Equatable, Sendable {
    /// Light editor appearance.
    case light
    /// Dark editor appearance.
    case dark
}

/// Initial state carried when the Excalidraw HUD opens.
struct ExcalidrawHUDState: Equatable, Sendable {
    /// How the HUD should choose its first visible mode.
    enum Activation: Equatable, Sendable {
        /// Show the launcher and wait for user selection.
        case launcher
        /// Open the preferred quick-swipe document immediately.
        case quickOpen
    }

    /// Requested first behavior for the HUD session.
    let activation: Activation

    /// Creates Excalidraw HUD state.
    /// - Parameter activation: Initial activation behavior.
    init(activation: Activation = .launcher) {
        self.activation = activation
    }
}

/// Messages accepted by the visible Excalidraw HUD.
enum ExcalidrawHUDMessage: Sendable {
    /// Gesture-derived input while the launcher is active.
    case input(ExcalidrawHUDInput)
    /// Keyboard/default request to execute the active launcher action.
    case defaultAction
    /// Keyboard request to show the editor save/rename prompt.
    case savePrompt
    /// Scroll-wheel request to move the active search result selection.
    case searchScroll(offset: Int)
}

extension HUDMessage {
    /// Creates an Excalidraw HUD message.
    /// - Parameter message: Excalidraw-specific message payload.
    /// - Returns: Type-erased HUD message.
    static func excalidraw(_ message: ExcalidrawHUDMessage) -> HUDMessage {
        HUDMessage(message)
    }

    /// Excalidraw HUD message payload, when this message belongs to the Excalidraw HUD.
    var excalidrawHUDMessage: ExcalidrawHUDMessage? {
        payload(as: ExcalidrawHUDMessage.self)
    }
}

/// Gesture input routed to the Excalidraw launcher.
struct ExcalidrawHUDInput: Equatable, Sendable {
    /// Gesture-derived movement type.
    enum Kind: Equatable, Sendable {
        /// User moved left across launcher items.
        case moveLeft
        /// User moved right across launcher items.
        case moveRight
        /// User moved farther down to execute the active item.
        case execute
    }

    /// Classified input kind.
    let kind: Kind
    /// Absolute gesture delta used to classify the input.
    let magnitude: Double
    /// Source trackpad frame.
    let frame: Int
}

/// Reason a listener-owned Excalidraw HUD session closed.
enum ExcalidrawHUDCloseReason: Equatable, Sendable {
    /// User clicked outside the HUD window.
    case clickOutside
    /// User pressed Escape while the launcher or search HUD was active.
    case escape
    /// User pressed Command-W while the HUD was active.
    case commandW
}

/// Thread-safe mirror of the visible Excalidraw mode for listener keyboard routing.
final class ExcalidrawHUDModeState: @unchecked Sendable {
    private let lock = NSLock()
    private var mode: ExcalidrawHUDMode = .launcher

    /// Replaces the current visible mode.
    func setMode(_ mode: ExcalidrawHUDMode) {
        lock.lock()
        self.mode = mode
        lock.unlock()
    }

    /// Current visible mode.
    var currentMode: ExcalidrawHUDMode {
        lock.lock()
        let mode = self.mode
        lock.unlock()
        return mode
    }
}

/// One local Excalidraw drawing known to drift.
struct ExcalidrawDocumentRecord: Identifiable, Equatable, Codable, Sendable {
    /// Stable identity, currently the standardized file path.
    let id: String
    /// Human-readable display title.
    var title: String
    /// Local `.excalidraw` file URL.
    var fileURL: URL
    /// Latest thumbnail image generated from the web editor.
    var thumbnailURL: URL?
    /// Light-mode thumbnail image generated from the web editor.
    var lightThumbnailURL: URL?
    /// Dark-mode thumbnail image generated from the web editor.
    var darkThumbnailURL: URL?
    /// File modification date.
    var modifiedAt: Date
    /// Last time the document was opened through drift.
    var lastOpenedAt: Date?
    /// Whether the file was created as a scratch draft.
    var isDraft: Bool
    /// Preferred editor and thumbnail theme for this drawing.
    var preferredTheme: ExcalidrawThemePreference

    /// Chooses the thumbnail URL that best matches the resolved drawing theme.
    func thumbnailURL(resolvedTheme: ExcalidrawResolvedTheme) -> URL? {
        switch resolvedTheme {
        case .light:
            lightThumbnailURL ?? thumbnailURL ?? darkThumbnailURL
        case .dark:
            darkThumbnailURL ?? thumbnailURL ?? lightThumbnailURL
        }
    }
}

/// Saved quick-swipe behavior.
enum ExcalidrawQuickSwipeAction: String, Codable, Equatable, Sendable {
    /// Resume the latest draft or recent drawing.
    case openLastDraft
    /// Always create a fresh drawing.
    case createNew
    /// Open the most recently saved/opened file.
    case openLastFile
}

/// User preferences for the Excalidraw feature.
struct ExcalidrawPreferences: Equatable, Sendable {
    /// Directory where `.excalidraw` files are stored.
    var drawingsFolder: URL
    /// Default action for a fast top-edge swipe.
    var quickSwipeAction: ExcalidrawQuickSwipeAction
}

/// Payload sent from the web editor when scene data changes.
struct ExcalidrawDocumentPayload: Codable, Equatable, Sendable {
    /// Raw Excalidraw JSON object.
    var document: String
    /// Optional PNG data URL for the current scene thumbnail.
    var thumbnailDataURL: String?
    /// User's preferred theme for this drawing.
    var themePreference: ExcalidrawThemePreference? = nil
    /// Concrete theme used when rendering the thumbnail PNG.
    var thumbnailTheme: ExcalidrawResolvedTheme? = nil
}
