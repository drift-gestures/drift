import XCTest
@testable import drift

final class ExcalidrawStaticServerTests: XCTestCase {
    @MainActor
    func testBackgroundWorkerStartsBundledServerResources() async throws {
        let fixture = try WorkerFixture()
        let worker = ExcalidrawBackgroundWorker(documents: fixture.makeStore())
        worker.applicationDidFinishLaunching()
        defer { worker.applicationWillTerminate() }

        let serverURL = try XCTUnwrap(worker.serverURL)
        let (data, response) = try await URLSession.shared.data(from: serverURL)
        let html = String(data: data, encoding: .utf8) ?? ""

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(html.contains("drift Excalidraw"))
    }

    func testServesBundledStyleStaticFileFromLoopback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-excalidraw-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "hello".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let server = ExcalidrawStaticServer(rootDirectory: root)
        let baseURL = try server.start()
        defer { server.stop() }

        let (data, response) = try await URLSession.shared.data(from: baseURL)

        XCTAssertEqual(String(data: data, encoding: .utf8), "hello")
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(baseURL.host, "127.0.0.1")
    }

    func testRejectsPathTraversal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-excalidraw-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "hello".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let server = ExcalidrawStaticServer(rootDirectory: root)
        let baseURL = try server.start()
        defer { server.stop() }

        let url = URL(string: "../secret", relativeTo: baseURL)!
        let (_, response) = try await URLSession.shared.data(from: url)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }
}

private struct WorkerFixture {
    let root: URL
    let drawings: URL
    let support: URL
    let defaults: UserDefaults

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-excalidraw-worker-\(UUID().uuidString)", isDirectory: true)
        drawings = root.appendingPathComponent("Drawings", isDirectory: true)
        support = root.appendingPathComponent("Support", isDirectory: true)
        defaults = UserDefaults(suiteName: "drift.excalidraw.worker.tests.\(UUID().uuidString)")!
        defaults.set(drawings.path, forKey: "drawings")
    }

    @MainActor
    func makeStore() -> ExcalidrawDocumentStore {
        ExcalidrawDocumentStore(
            defaults: defaults,
            drawingsFolderKey: "drawings",
            quickSwipeKey: "quickSwipe",
            metadataFolder: support
        )
    }
}
