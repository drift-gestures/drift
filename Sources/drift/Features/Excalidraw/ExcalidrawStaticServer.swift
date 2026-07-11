import Darwin
import Foundation

/// Minimal loopback-only static file server for the bundled Excalidraw host.
final class ExcalidrawStaticServer: @unchecked Sendable {
    /// Server startup and request failures.
    enum ServerError: Error {
        case missingRoot(URL)
        case socketCreationFailed
        case socketOptionFailed
        case bindFailed
        case listenFailed
        case portLookupFailed
    }

    /// Directory served by this server.
    let rootDirectory: URL

    private let queue = DispatchQueue(label: "drift.excalidraw.static-server")
    private let stateLock = NSLock()
    private var socketDescriptor: Int32 = -1
    private var activePort: UInt16?

    /// Creates a static file server rooted at a bundled directory.
    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// Starts the server if needed and returns the local base URL.
    @discardableResult
    func start() throws -> URL {
        stateLock.lock()
        if let activePort {
            stateLock.unlock()
            return Self.baseURL(port: activePort)
        }
        stateLock.unlock()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ServerError.missingRoot(rootDirectory)
        }

        let descriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard descriptor >= 0 else { throw ServerError.socketCreationFailed }

        var yes: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            close(descriptor)
            throw ServerError.socketOptionFailed
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let didBind = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard didBind == 0 else {
            close(descriptor)
            throw ServerError.bindFailed
        }

        guard listen(descriptor, SOMAXCONN) == 0 else {
            close(descriptor)
            throw ServerError.listenFailed
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let didReadPort = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &boundLength)
            }
        }
        guard didReadPort == 0 else {
            close(descriptor)
            throw ServerError.portLookupFailed
        }

        let port = UInt16(bigEndian: boundAddress.sin_port)
        stateLock.lock()
        socketDescriptor = descriptor
        activePort = port
        stateLock.unlock()

        queue.async { [weak self] in
            self?.acceptLoop(descriptor: descriptor)
        }

        return Self.baseURL(port: port)
    }

    /// Stops accepting requests and closes the listening socket.
    func stop() {
        stateLock.lock()
        let descriptor = socketDescriptor
        socketDescriptor = -1
        activePort = nil
        stateLock.unlock()

        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
        }
    }

    private func acceptLoop(descriptor: Int32) {
        while true {
            var address = sockaddr()
            var addressLength = socklen_t(MemoryLayout<sockaddr>.size)
            let client = accept(descriptor, &address, &addressLength)
            guard client >= 0 else { break }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(client: client)
            }
        }
    }

    private func handle(client: Int32) {
        defer {
            shutdown(client, SHUT_RDWR)
            close(client)
        }

        guard let request = readRequest(from: client),
              let firstLine = request.split(separator: "\r\n", maxSplits: 1).first
        else {
            sendResponse(status: "400 Bad Request", body: Data(), client: client)
            return
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              parts[0] == "GET"
        else {
            sendResponse(status: "405 Method Not Allowed", body: Data(), client: client)
            return
        }

        let path = String(parts[1])
        guard let fileURL = fileURL(for: path),
              let data = try? Data(contentsOf: fileURL)
        else {
            sendResponse(status: "404 Not Found", body: Data(), client: client)
            return
        }

        sendResponse(
            status: "200 OK",
            contentType: mimeType(for: fileURL),
            body: data,
            client: client
        )
    }

    private func readRequest(from client: Int32) -> String? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while data.count < 16_384 {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            data.append(buffer, count: count)
            if data.range(of: Data("\r\n\r\n".utf8)) != nil {
                break
            }
        }
        return String(data: data, encoding: .utf8)
    }

    private func fileURL(for requestPath: String) -> URL? {
        let pathWithoutQuery = requestPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        let decoded = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
        guard !decoded.contains("..") else { return nil }

        let relativePath = decoded == "/"
            ? "index.html"
            : String(decoded.drop(while: { $0 == "/" }))
        guard !relativePath.isEmpty else { return nil }

        let candidate = rootDirectory.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        guard candidate.path.hasPrefix(rootDirectory.standardizedFileURL.path) else { return nil }
        return candidate
    }

    private func sendResponse(
        status: String,
        contentType: String = "text/plain; charset=utf-8",
        body: Data,
        client: Int32
    ) {
        let headers = "HTTP/1.1 \(status)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n" +
            "\r\n"
        var response = Data(headers.utf8)
        response.append(body)
        response.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var remaining = response.count
            var offset = 0
            while remaining > 0 {
                let sent = Darwin.send(client, baseAddress.advanced(by: offset), remaining, 0)
                guard sent > 0 else { break }
                remaining -= sent
                offset += sent
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }

    private static func baseURL(port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)/")!
    }
}
