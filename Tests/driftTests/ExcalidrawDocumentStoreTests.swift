import XCTest
@testable import drift

@MainActor
final class ExcalidrawDocumentStoreTests: XCTestCase {
    func testCreateNewDrawingWritesPlainExcalidrawJSONAndMarksDraft() throws {
        let fixture = try StoreFixture()
        let store = fixture.makeStore()
        store.start()

        let record = try store.createNewDrawing()
        let json = try String(contentsOf: record.fileURL, encoding: .utf8)

        XCTAssertEqual(record.fileURL.pathExtension, "excalidraw")
        XCTAssertTrue(record.isDraft)
        XCTAssertEqual(record.preferredTheme, .system)
        XCTAssertTrue(json.contains("\"type\": \"excalidraw\""))
        XCTAssertTrue(json.contains("\"elements\": []"))
    }

    func testQuickSwipeOpensLatestDraftByDefault() throws {
        let fixture = try StoreFixture()
        let store = fixture.makeStore()
        store.start()

        let draft = try store.createNewDrawing()
        let quick = try store.documentForQuickSwipe()

        XCTAssertEqual(quick.id, draft.id)
    }

    func testSavePersistsDocumentAndThumbnailMetadata() throws {
        let fixture = try StoreFixture()
        let store = fixture.makeStore()
        store.start()
        let record = try store.createNewDrawing()
        let pngDataURL = "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())"

        let saved = try store.save(
            documentID: record.id,
            payload: ExcalidrawDocumentPayload(
                document: #"{"type":"excalidraw","version":2,"source":"test","elements":[{"id":"a"}],"appState":{},"files":{}}"#,
                thumbnailDataURL: pngDataURL,
                themePreference: .dark,
                thumbnailTheme: .dark
            )
        )

        XCTAssertEqual(saved?.preferredTheme, .dark)
        XCTAssertNotNil(saved?.thumbnailURL)
        XCTAssertNotNil(saved?.darkThumbnailURL)
        XCTAssertEqual(try String(contentsOf: record.fileURL, encoding: .utf8).contains(#""id":"a""#), true)
        XCTAssertEqual(FileManager.default.fileExists(atPath: saved?.thumbnailURL?.path ?? ""), true)
        XCTAssertEqual(
            FileManager.default.fileExists(atPath: saved?.thumbnailURL(resolvedTheme: .dark)?.path ?? ""),
            true
        )
    }
}

private struct StoreFixture {
    let root: URL
    let drawings: URL
    let support: URL
    let defaults: UserDefaults

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-excalidraw-store-\(UUID().uuidString)", isDirectory: true)
        drawings = root.appendingPathComponent("Drawings", isDirectory: true)
        support = root.appendingPathComponent("Support", isDirectory: true)
        defaults = UserDefaults(suiteName: "drift.excalidraw.tests.\(UUID().uuidString)")!
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
