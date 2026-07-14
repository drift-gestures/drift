import Combine
import Foundation

/// App-owned runtime services for local Excalidraw editing.
@MainActor
final class ExcalidrawBackgroundWorker: ObservableObject, HUDBackgroundWorker {
    /// Local document and preferences store.
    let documents: ExcalidrawDocumentStore
    /// Thread-safe mirror of the currently rendered Excalidraw HUD mode.
    let modeState = ExcalidrawHUDModeState()

    /// Local base URL for the bundled Excalidraw host.
    @Published private(set) var serverURL: URL?
    /// Last server startup error, if any.
    @Published private(set) var serverError: String?

    private var server: ExcalidrawStaticServer?

    /// Creates the Excalidraw runtime worker.
    init(documents: ExcalidrawDocumentStore = ExcalidrawDocumentStore()) {
        self.documents = documents
    }

    /// Starts local document storage and the bundled web server.
    func applicationDidFinishLaunching() {
        documents.start()
        startServerIfNeeded()
    }

    /// Stops the local web server before app termination.
    func applicationWillTerminate() {
        server?.stop()
        server = nil
        serverURL = nil
    }

    /// Ensures the bundled web server is running.
    func startServerIfNeeded() {
        guard serverURL == nil else { return }
        guard let rootURL = Self.webHostRootURL() else {
            serverError = "Bundled Excalidraw host resources were not found."
            return
        }

        let server = ExcalidrawStaticServer(rootDirectory: rootURL)
        do {
            serverURL = try server.start()
            serverError = nil
            self.server = server
        } catch {
            serverError = "Failed to start Excalidraw server: \(error)"
            server.stop()
        }
    }

    /// Restarts the local web server after a recoverable failure.
    func restartServer() {
        server?.stop()
        server = nil
        serverURL = nil
        startServerIfNeeded()
    }

    /// Selects the quick-swipe document, creating one when needed.
    func quickSwipeDocument() throws -> ExcalidrawDocumentRecord {
        try documents.documentForQuickSwipe()
    }

    /// Creates a fresh drawing from the launcher.
    func createNewDrawing() throws -> ExcalidrawDocumentRecord {
        try documents.createNewDrawing()
    }

    private static func webHostRootURL() -> URL? {
        guard let appResourceURL = Bundle.main.resourceURL else { return nil }
        let appHostURL = appResourceURL.appendingPathComponent("ExcalidrawHost", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appHostURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return appHostURL
    }
}
