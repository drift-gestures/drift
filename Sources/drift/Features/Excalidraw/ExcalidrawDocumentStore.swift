import Combine
import Foundation

/// Local file store for Excalidraw drawings, thumbnails, recents, and preferences.
@MainActor
final class ExcalidrawDocumentStore: ObservableObject {
    /// Current recent drawing list, newest first.
    @Published private(set) var documents: [ExcalidrawDocumentRecord] = []
    /// Current persisted preferences.
    @Published private(set) var preferences: ExcalidrawPreferences

    /// Filename extension for Excalidraw documents.
    static let fileExtension = "excalidraw"

    private struct MetadataFile: Codable {
        var entries: [String: MetadataEntry] = [:]
    }

    private struct MetadataEntry: Codable {
        var lastOpenedAt: Date?
        var isDraft: Bool
        var thumbnailFileName: String?
        var thumbnailLightFileName: String?
        var thumbnailDarkFileName: String?
        var preferredTheme: ExcalidrawThemePreference?
    }

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let drawingsFolderKey: String
    private let quickSwipeKey: String
    private let metadataURL: URL
    private let thumbnailsFolder: URL

    /// Creates a local Excalidraw document store.
    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        drawingsFolderKey: String = "drift.excalidraw.drawingsFolder",
        quickSwipeKey: String = "drift.excalidraw.quickSwipeAction",
        metadataFolder: URL? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.drawingsFolderKey = drawingsFolderKey
        self.quickSwipeKey = quickSwipeKey

        let supportFolder = metadataFolder ?? Self.defaultApplicationSupportFolder(fileManager: fileManager)
        metadataURL = supportFolder.appendingPathComponent("metadata.json")
        thumbnailsFolder = supportFolder.appendingPathComponent("Thumbnails", isDirectory: true)

        let drawingsFolder = defaults.string(forKey: drawingsFolderKey)
            .map(URL.init(fileURLWithPath:))
            ?? Self.defaultDrawingsFolder(fileManager: fileManager)
        let quickSwipeAction = defaults.string(forKey: quickSwipeKey)
            .flatMap(ExcalidrawQuickSwipeAction.init(rawValue:))
            ?? .openLastDraft
        preferences = ExcalidrawPreferences(
            drawingsFolder: drawingsFolder,
            quickSwipeAction: quickSwipeAction
        )
    }

    /// Starts local storage and loads the initial recents list.
    func start() {
        do {
            try ensureStorage()
            try refreshDocuments()
        } catch {
            documents = []
        }
    }

    /// Updates and persists user preferences.
    func savePreferences(
        drawingsFolder: URL,
        quickSwipeAction: ExcalidrawQuickSwipeAction
    ) throws {
        preferences = ExcalidrawPreferences(
            drawingsFolder: drawingsFolder,
            quickSwipeAction: quickSwipeAction
        )
        defaults.set(drawingsFolder.path, forKey: drawingsFolderKey)
        defaults.set(quickSwipeAction.rawValue, forKey: quickSwipeKey)
        try ensureStorage()
        try refreshDocuments()
    }

    /// Refreshes known documents from disk.
    func refreshDocuments() throws {
        try ensureStorage()
        let metadata = loadMetadata()
        let fileURLs = try fileManager.contentsOfDirectory(
            at: preferences.drawingsFolder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        documents = fileURLs
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { record(for: $0, metadata: metadata) }
            .sorted(by: Self.sortDocuments)
    }

    /// Returns a document matching an identifier.
    func document(id: String) -> ExcalidrawDocumentRecord? {
        documents.first { $0.id == id }
    }

    /// Creates a new local scratch drawing and records it as a draft.
    @discardableResult
    func createNewDrawing() throws -> ExcalidrawDocumentRecord {
        try ensureStorage()
        let fileURL = uniqueDrawingURL(title: "Untitled")
        try Self.emptyDocumentJSON.write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        var metadata = loadMetadata()
        metadata.entries[documentID(for: fileURL)] = MetadataEntry(
            lastOpenedAt: Date(),
            isDraft: true,
            thumbnailFileName: nil,
            thumbnailLightFileName: nil,
            thumbnailDarkFileName: nil,
            preferredTheme: .system
        )
        try saveMetadata(metadata)
        try refreshDocuments()
        return documents.first { $0.fileURL == fileURL } ?? ExcalidrawDocumentRecord(
            id: documentID(for: fileURL),
            title: fileURL.deletingPathExtension().lastPathComponent,
            fileURL: fileURL,
            thumbnailURL: nil,
            lightThumbnailURL: nil,
            darkThumbnailURL: nil,
            modifiedAt: Date(),
            lastOpenedAt: Date(),
            isDraft: true,
            preferredTheme: .system
        )
    }

    /// Chooses the drawing opened by the fast top-edge swipe.
    func documentForQuickSwipe() throws -> ExcalidrawDocumentRecord {
        try refreshDocuments()
        switch preferences.quickSwipeAction {
        case .createNew:
            return try createNewDrawing()
        case .openLastDraft:
            if let draft = documents.first(where: \.isDraft) {
                return try markOpened(draft)
            }
            if let recent = documents.first {
                return try markOpened(recent)
            }
            return try createNewDrawing()
        case .openLastFile:
            if let recent = documents.first {
                return try markOpened(recent)
            }
            return try createNewDrawing()
        }
    }

    /// Records an explicit open from launcher/search recents.
    @discardableResult
    func markOpened(_ record: ExcalidrawDocumentRecord) throws -> ExcalidrawDocumentRecord {
        var metadata = loadMetadata()
        var entry = metadata.entries[record.id] ?? MetadataEntry(
            lastOpenedAt: nil,
            isDraft: record.isDraft,
            thumbnailFileName: record.thumbnailURL?.lastPathComponent,
            thumbnailLightFileName: record.lightThumbnailURL?.lastPathComponent,
            thumbnailDarkFileName: record.darkThumbnailURL?.lastPathComponent,
            preferredTheme: record.preferredTheme
        )
        entry.lastOpenedAt = Date()
        entry.preferredTheme = entry.preferredTheme ?? record.preferredTheme
        metadata.entries[record.id] = entry
        try saveMetadata(metadata)
        try refreshDocuments()
        return documents.first { $0.id == record.id } ?? record
    }

    /// Saves editor JSON and optional thumbnail for an existing document.
    @discardableResult
    func save(documentID: String, payload: ExcalidrawDocumentPayload) throws -> ExcalidrawDocumentRecord? {
        try ensureStorage()
        guard let current = document(id: documentID) else { return nil }

        try payload.document.write(
            to: current.fileURL,
            atomically: true,
            encoding: .utf8
        )

        var metadata = loadMetadata()
        var entry = metadata.entries[documentID] ?? MetadataEntry(
            lastOpenedAt: current.lastOpenedAt,
            isDraft: current.isDraft,
            thumbnailFileName: current.thumbnailURL?.lastPathComponent,
            thumbnailLightFileName: current.lightThumbnailURL?.lastPathComponent,
            thumbnailDarkFileName: current.darkThumbnailURL?.lastPathComponent,
            preferredTheme: current.preferredTheme
        )
        if let themePreference = payload.themePreference {
            entry.preferredTheme = themePreference
        } else {
            entry.preferredTheme = entry.preferredTheme ?? current.preferredTheme
        }
        if let thumbnailData = Self.decodeDataURL(payload.thumbnailDataURL) {
            let thumbnailName: String
            switch payload.thumbnailTheme {
            case .light:
                thumbnailName = entry.thumbnailLightFileName ?? "\(UUID().uuidString).png"
                entry.thumbnailLightFileName = thumbnailName
            case .dark:
                thumbnailName = entry.thumbnailDarkFileName ?? "\(UUID().uuidString).png"
                entry.thumbnailDarkFileName = thumbnailName
            case nil:
                thumbnailName = entry.thumbnailFileName ?? "\(UUID().uuidString).png"
            }
            let thumbnailURL = thumbnailsFolder.appendingPathComponent(thumbnailName)
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
            entry.thumbnailFileName = thumbnailName
        }
        metadata.entries[documentID] = entry
        try saveMetadata(metadata)
        try refreshDocuments()
        return document(id: documentID)
    }

    /// Loads raw JSON for a local Excalidraw document.
    func documentJSON(for record: ExcalidrawDocumentRecord) -> String {
        (try? String(contentsOf: record.fileURL, encoding: .utf8)) ?? Self.emptyDocumentJSON
    }

    /// Renames a drawing file while preserving metadata and thumbnails.
    @discardableResult
    func rename(documentID: String, title: String) throws -> ExcalidrawDocumentRecord? {
        try ensureStorage()
        guard let current = document(id: documentID) else { return nil }

        let sanitizedTitle = sanitizedDrawingTitle(title, fallback: current.title)
        let destinationURL = uniqueRenameURL(title: sanitizedTitle, excluding: current.fileURL)
        guard destinationURL != current.fileURL else { return current }

        try fileManager.moveItem(at: current.fileURL, to: destinationURL)

        var metadata = loadMetadata()
        let oldID = documentID
        let newID = self.documentID(for: destinationURL)
        if let entry = metadata.entries.removeValue(forKey: oldID) {
            metadata.entries[newID] = entry
        }
        try saveMetadata(metadata)
        try refreshDocuments()
        return document(id: newID)
    }

    /// Filters local drawings by title.
    func documents(matching query: String) -> [ExcalidrawDocumentRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return documents }
        return documents.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func ensureStorage() throws {
        try fileManager.createDirectory(
            at: preferences.drawingsFolder,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: metadataURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: thumbnailsFolder,
            withIntermediateDirectories: true
        )
    }

    private func record(for fileURL: URL, metadata: MetadataFile) -> ExcalidrawDocumentRecord? {
        guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != false else {
            return nil
        }

        let id = documentID(for: fileURL)
        let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date.distantPast
        let entry = metadata.entries[id]
        let thumbnailURL = entry?.thumbnailFileName.map {
            thumbnailsFolder.appendingPathComponent($0)
        }
        let lightThumbnailURL = entry?.thumbnailLightFileName.map {
            thumbnailsFolder.appendingPathComponent($0)
        }
        let darkThumbnailURL = entry?.thumbnailDarkFileName.map {
            thumbnailsFolder.appendingPathComponent($0)
        }
        return ExcalidrawDocumentRecord(
            id: id,
            title: fileURL.deletingPathExtension().lastPathComponent,
            fileURL: fileURL,
            thumbnailURL: thumbnailURL,
            lightThumbnailURL: lightThumbnailURL,
            darkThumbnailURL: darkThumbnailURL,
            modifiedAt: modifiedAt,
            lastOpenedAt: entry?.lastOpenedAt,
            isDraft: entry?.isDraft ?? false,
            preferredTheme: entry?.preferredTheme ?? .system
        )
    }

    private func uniqueDrawingURL(title: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = formatter.string(from: Date())
        var candidate = preferences.drawingsFolder
            .appendingPathComponent("\(title) \(stamp)")
            .appendingPathExtension(Self.fileExtension)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = preferences.drawingsFolder
                .appendingPathComponent("\(title) \(stamp) \(index)")
                .appendingPathExtension(Self.fileExtension)
            index += 1
        }
        return candidate
    }

    private func uniqueRenameURL(title: String, excluding currentURL: URL) -> URL {
        var candidate = preferences.drawingsFolder
            .appendingPathComponent(title)
            .appendingPathExtension(Self.fileExtension)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path),
              candidate.standardizedFileURL != currentURL.standardizedFileURL {
            candidate = preferences.drawingsFolder
                .appendingPathComponent("\(title) \(index)")
                .appendingPathExtension(Self.fileExtension)
            index += 1
        }
        return candidate
    }

    private func sanitizedDrawingTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        return base.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    private func loadMetadata() -> MetadataFile {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode(MetadataFile.self, from: data)
        else {
            return MetadataFile()
        }
        return decoded
    }

    private func saveMetadata(_ metadata: MetadataFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func documentID(for fileURL: URL) -> String {
        fileURL.standardizedFileURL.path
    }

    private static func sortDocuments(
        _ lhs: ExcalidrawDocumentRecord,
        _ rhs: ExcalidrawDocumentRecord
    ) -> Bool {
        let leftDate = lhs.lastOpenedAt ?? lhs.modifiedAt
        let rightDate = rhs.lastOpenedAt ?? rhs.modifiedAt
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func decodeDataURL(_ value: String?) -> Data? {
        guard let value,
              let commaIndex = value.firstIndex(of: ",")
        else {
            return nil
        }
        let encoded = String(value[value.index(after: commaIndex)...])
        return Data(base64Encoded: encoded)
    }

    private static func defaultDrawingsFolder(fileManager: FileManager) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        return documents
            .appendingPathComponent("drift", isDirectory: true)
            .appendingPathComponent("Excalidraw", isDirectory: true)
    }

    private static func defaultApplicationSupportFolder(fileManager: FileManager) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("drift", isDirectory: true)
            .appendingPathComponent("Excalidraw", isDirectory: true)
    }

    private static let emptyDocumentJSON = """
    {
      "type": "excalidraw",
      "version": 2,
      "source": "drift",
      "elements": [],
      "appState": {
        "viewBackgroundColor": "#ffffff"
      },
      "files": {}
    }
    """
}
