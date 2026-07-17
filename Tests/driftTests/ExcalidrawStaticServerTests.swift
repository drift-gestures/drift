import Darwin
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

    func testClientDisconnectBeforeWriteDoesNotCrashServer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-excalidraw-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = String(repeating: "x", count: 256 * 1024)
        try payload.write(to: root.appendingPathComponent("large.html"), atomically: true, encoding: .utf8)
        let server = ExcalidrawStaticServer(rootDirectory: root)
        let baseURL = try server.start()
        defer { server.stop() }

        let fd = Self.connectRaw(to: baseURL)
        XCTAssertGreaterThanOrEqual(fd, 0)
        close(fd)

        try await Task.sleep(nanoseconds: 100_000_000)

        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("large.html"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), payload)
    }

    func testClientDisconnectMidResponseDoesNotCrashServer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-excalidraw-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = String(repeating: "y", count: 1_024 * 1024)
        try payload.write(to: root.appendingPathComponent("bundle.js"), atomically: true, encoding: .utf8)
        let server = ExcalidrawStaticServer(rootDirectory: root)
        let baseURL = try server.start()
        defer { server.stop() }

        let fd = Self.connectRaw(to: baseURL)
        XCTAssertGreaterThanOrEqual(fd, 0)

        let request = "GET /bundle.js HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let sent = request.withCString { ptr in
            Darwin.send(fd, ptr, strlen(ptr), 0)
        }
        XCTAssertGreaterThan(sent, 0)

        var buf = [UInt8](repeating: 0, count: 4096)
        let received = recv(fd, &buf, buf.count, 0)
        XCTAssertGreaterThan(received, 0)

        close(fd)

        try await Task.sleep(nanoseconds: 200_000_000)

        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("bundle.js"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), payload)
    }

    func testServerRemainsFunctionalAfterMultipleClientDisconnects() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-excalidraw-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = String(repeating: "z", count: 512 * 1024)
        try payload.write(to: root.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
        let server = ExcalidrawStaticServer(rootDirectory: root)
        let baseURL = try server.start()
        defer { server.stop() }

        for _ in 0..<5 {
            let fd = Self.connectRaw(to: baseURL)
            guard fd >= 0 else { continue }

            let request = "GET /data.json HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            _ = request.withCString { ptr in
                Darwin.send(fd, ptr, strlen(ptr), 0)
            }

            var buf = [UInt8](repeating: 0, count: 1024)
            _ = recv(fd, &buf, buf.count, 0)

            close(fd)
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("data.json"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), payload)
    }

    private static func connectRaw(to url: URL) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(url.port ?? 80).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return -1
        }
        return fd
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
