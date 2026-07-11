import AppKit
import SwiftUI

/// Root SwiftUI view for the single Excalidraw HUD.
struct ExcalidrawHUDView: View {
    @ObservedObject var worker: ExcalidrawBackgroundWorker
    @ObservedObject var documents: ExcalidrawDocumentStore

    let hudController: HUDController
    let screenFrame: CGRect
    let initialState: ExcalidrawHUDState

    @EnvironmentObject private var hudStore: HUDStore
    @EnvironmentObject private var hudMessages: HUDMessageBus

    @State private var mode: ExcalidrawHUDMode = .launcher
    @State private var selectedLauncherIndex = 1
    @State private var searchQuery = ""
    @State private var selectedSearchDocumentID: String?
    @State private var pendingError: String?
    @State private var didApplyInitialState = false
    @State private var isSavePromptPresented = false
    @State private var savePromptTitle = ""
    @State private var savePromptFocusRequest = 0

    var body: some View {
        GlassEffectContainer {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear(perform: onAppear)
                .onDisappear(perform: onDisappear)
                .onChange(of: mode) { _, _ in
                    applyModeLayout()
                    worker.modeState.setMode(mode)
                }
                .onReceive(hudMessages.messages, perform: receiveHUDMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .launcher:
            ExcalidrawLauncherContent(
                launcherItems: launcherItems,
                selectedLauncherIndex: $selectedLauncherIndex,
                execute: execute
            )
        case .search:
            ExcalidrawSearchContent(
                documents: documents,
                searchQuery: $searchQuery,
                selectedDocumentID: $selectedSearchDocumentID,
                open: open,
                moveToTrash: moveToTrash
            )
        case .editor(let documentID):
            ZStack(alignment: .top) {
                ExcalidrawEditorContent(
                    worker: worker,
                    documents: documents,
                    documentID: documentID,
                    screenFrame: screenFrame,
                    pendingError: pendingError,
                    shouldFocusEditor: !isSavePromptPresented
                )

                if isSavePromptPresented {
                    ExcalidrawSavePromptContent(
                        title: $savePromptTitle,
                        focusRequest: savePromptFocusRequest,
                        save: saveCurrentDocumentTitle,
                        cancel: hideSavePrompt
                    )
                    .padding(.top, ExcalidrawHUDStyle.padding)
                }
            }
        }
    }

    private var launcherItems: [LauncherItem] {
        var items = [
            LauncherItem(action: .search, title: "Search", systemImage: "sparkle.magnifyingglass", record: nil),
            LauncherItem(action: .new, title: "New", systemImage: "pencil.and.scribble", record: nil),
        ]
        items.append(contentsOf: documents.documents.prefix(3).map {
            LauncherItem(action: .open($0.id), title: $0.title, systemImage: nil, record: $0)
        })
        return items
    }

    private func onAppear() {
        refreshDocumentsFromDisk()
        applyModeLayout()
        worker.modeState.setMode(mode)
        guard !didApplyInitialState else { return }
        didApplyInitialState = true
        switch initialState.activation {
        case .launcher:
            setMode(.launcher)
        case .quickOpen:
            openQuickSwipeDocument()
        }
    }

    private func onDisappear() {
        hudStore.setSizeOverride(nil, for: ExcalidrawHUDDefinition.hudID)
        hudStore.setWindowBehaviorOverride(nil, for: ExcalidrawHUDDefinition.hudID)
        worker.modeState.setMode(.launcher)
    }

    private func applyModeLayout() {
        hudStore.setSizeOverride(size(for: mode), for: ExcalidrawHUDDefinition.hudID)
        switch mode {
        case .editor:
            hudStore.setWindowBehaviorOverride(windowBehavior(for: mode), for: ExcalidrawHUDDefinition.hudID)
        default:
            break
        }
    }

    private func size(for mode: ExcalidrawHUDMode) -> CGSize {
        switch mode {
        case .launcher:
            ExcalidrawHUDStyle.launcherSize
        case .search:
            ExcalidrawHUDStyle.searchSize
        case .editor:
            ExcalidrawHUDStyle.editorSize(screenFrame: screenFrame)
        }
    }

    private func windowBehavior(for mode: ExcalidrawHUDMode) -> HUDWindowBehavior {
        switch mode {
        case .launcher:
            .passive
        case .search, .editor:
            .keyInput
        }
    }

    private func receiveHUDMessage(_ targetedMessage: TargetedHUDMessage) {
        guard targetedMessage.hudID == ExcalidrawHUDDefinition.hudID,
              let message = targetedMessage.message.excalidrawHUDMessage
        else {
            return
        }

        switch message {
        case .defaultAction:
            executeActiveLauncherItem()
        case .input(let input):
            receive(input)
        case .savePrompt:
            showSavePrompt()
        case .searchScroll(let offset):
            scrollSearchSelection(offset: offset)
        }
    }

    private func receive(_ input: ExcalidrawHUDInput) {
        guard case .launcher = mode else { return }
        switch input.kind {
        case .moveLeft:
            selectedLauncherIndex = max(0, selectedLauncherIndex - 1)
        case .moveRight:
            selectedLauncherIndex = min(max(0, launcherItems.count - 1), selectedLauncherIndex + 1)
        case .execute:
            executeActiveLauncherItem()
        }
    }

    private func executeActiveLauncherItem() {
        guard launcherItems.indices.contains(selectedLauncherIndex) else { return }
        execute(launcherItems[selectedLauncherIndex])
    }

    private var searchResults: [ExcalidrawDocumentRecord] {
        documents.documents(matching: searchQuery)
    }

    private func syncSearchSelection() {
        let results = searchResults
        guard !results.isEmpty else {
            selectedSearchDocumentID = nil
            return
        }

        if let selectedSearchDocumentID,
           results.contains(where: { $0.id == selectedSearchDocumentID }) {
            return
        }

        selectedSearchDocumentID = results[0].id
    }

    private func scrollSearchSelection(offset: Int) {
        guard case .search = mode else { return }
        let previousDocumentID = selectedSearchDocumentID
        selectSearchResult(offset: offset)
        if selectedSearchDocumentID != previousDocumentID {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func selectSearchResult(offset: Int) {
        let results = searchResults
        guard !results.isEmpty else {
            selectedSearchDocumentID = nil
            return
        }

        let currentIndex = selectedSearchDocumentID
            .flatMap { selectedID in results.firstIndex { $0.id == selectedID } }
            ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        selectedSearchDocumentID = results[nextIndex].id
    }

    private func execute(_ item: LauncherItem) {
        switch item.action {
        case .search:
            setMode(.search)
        case .new:
            createNewDrawing()
        case .open(let documentID):
            guard let record = documents.document(id: documentID) else { return }
            open(record)
        }
    }

    private func openQuickSwipeDocument() {
        do {
            open(try worker.quickSwipeDocument())
        } catch {
            pendingError = "Could not open Excalidraw draft: \(error)"
            setMode(.launcher)
        }
    }

    private func createNewDrawing() {
        do {
            open(try worker.createNewDrawing())
        } catch {
            pendingError = "Could not create Excalidraw drawing: \(error)"
        }
    }

    private func open(_ record: ExcalidrawDocumentRecord) {
        do {
            let opened = try documents.markOpened(record)
            worker.startServerIfNeeded()
            setMode(.editor(documentID: opened.id))
        } catch {
            pendingError = "Could not open drawing: \(error)"
        }
    }

    private func moveToTrash(_ record: ExcalidrawDocumentRecord) {
        do {
            try documents.moveToTrash(record)
            if selectedSearchDocumentID == record.id {
                selectedSearchDocumentID = nil
            }
            syncSearchSelection()
        } catch {
            pendingError = "Could not move drawing to Trash: \(error)"
        }
    }

    private func refreshDocumentsFromDisk() {
        do {
            try documents.refreshDocuments()
            syncSearchSelection()
        } catch {
            pendingError = "Could not refresh Excalidraw drawings: \(error)"
        }
    }

    private func setMode(_ nextMode: ExcalidrawHUDMode) {
        mode = nextMode
        applyModeLayout()
        worker.modeState.setMode(nextMode)
        if case .editor = nextMode {
            return
        }
        hideSavePrompt()
        if case .launcher = nextMode {
            selectedLauncherIndex = min(selectedLauncherIndex, max(0, launcherItems.count - 1))
        }
        if case .search = nextMode {
            syncSearchSelection()
        }
    }

    private func showSavePrompt() {
        guard case .editor(let documentID) = mode,
              let record = documents.document(id: documentID)
        else {
            return
        }
        if !isSavePromptPresented {
            savePromptTitle = record.title
        }
        savePromptFocusRequest += 1
        isSavePromptPresented = true
    }

    private func hideSavePrompt() {
        isSavePromptPresented = false
    }

    private func saveCurrentDocumentTitle() {
        guard case .editor(let documentID) = mode else { return }
        do {
            if let renamed = try documents.rename(documentID: documentID, title: savePromptTitle) {
                hideSavePrompt()
                setMode(.editor(documentID: renamed.id))
            }
        } catch {
            pendingError = "Could not rename drawing: \(error)"
        }
    }
}
