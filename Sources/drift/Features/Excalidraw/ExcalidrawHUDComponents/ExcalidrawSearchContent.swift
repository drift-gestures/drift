import AppKit
import SwiftUI

struct ExcalidrawSearchContent: View {
    @ObservedObject var documents: ExcalidrawDocumentStore
    @Binding var searchQuery: String
    @Binding var selectedDocumentID: String?
    let open: (ExcalidrawDocumentRecord) -> Void

    @State private var searchFocusRequest = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ExcalidrawSearchTextField(
                    text: $searchQuery,
                    placeholder: "Search drawings",
                    focusRequest: searchFocusRequest,
                    submit: openSelectedDocument,
                    moveSelection: selectResult
                )
                    .font(DriftTypography.hudAction.weight(.medium))
                    .padding(.horizontal, 25)
                    .padding(.top, 19)
                    .padding(.bottom, 7)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .opacity(0.5)
                    .cornerRadius(.infinity)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)

            }
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredDocuments.isEmpty {
                            Text("No drawings found")
                                .font(DriftTypography.hudFieldValue.weight(.regular))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        } else {
                            ForEach(filteredDocuments) { record in
                                Button {
                                    open(record)
                                } label: {
                                    SearchResultRow(
                                        record: record,
                                        isSelected: record.id == selectedDocumentID
                                    )
                                }
                                .id(record.id)
                                .buttonStyle(.plain)
                                .onHover { isHovered in
                                    if isHovered {
                                        selectedDocumentID = record.id
                                    }
                                }
                            }
                        }
                    }
                }
                .onChange(of: selectedDocumentID) { _, documentID in
                    guard let documentID else { return }
                    scrollProxy.scrollTo(documentID)
                }
            }
            .padding([.horizontal], 15)
            .padding(.vertical, 12)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                selectedDocumentPath

                Spacer()

                if selectedDocument != nil {
                    HStack(spacing: 5) {
                        Text("Open")
                        KeybindingUI(keys: ["return"])
                    }
                    .font(DriftTypography.hudInlineControlIcon.weight(.regular))
                    .foregroundStyle(.secondary)
                    
                    RoundedRectangle(cornerRadius: .infinity)
                        .background(.white)
                        .opacity(0.1)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 13)
                    
                    HStack(spacing: 5) {
                        Text("Move to trash")
                        KeybindingUI(keys: ["command", "delete.left"])
                    }
                    .font(DriftTypography.hudInlineControlIcon.weight(.regular))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, ExcalidrawHUDStyle.padding)
            .padding(.bottom, 2)
            .frame(height: 42)
            .background(.ultraThinMaterial)
        }
        .frame(width: ExcalidrawHUDStyle.searchSize.width * 0.8, height: ExcalidrawHUDStyle.searchSize.height, alignment: .top)
        .cornerRadius(ExcalidrawHUDStyle.cornerRadius/2)
        .glassEffect(.regular, in: .rect(cornerRadius: ExcalidrawHUDStyle.cornerRadius/2))
        .onAppear {
            syncSelection()
            searchFocusRequest += 1
        }
        .onChange(of: searchQuery) { _, _ in
            syncSelection()
        }
    }

    private var filteredDocuments: [ExcalidrawDocumentRecord] {
        documents.documents(matching: searchQuery)
    }

    @ViewBuilder
    private var selectedDocumentPath: some View {
        if let selectedDocument {
            Text(selectedDocument.fileURL.deletingLastPathComponent().lastPathComponent)
                .font(DriftTypography.hudInlineControlIcon.weight(.regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var selectedDocument: ExcalidrawDocumentRecord? {
        guard let selectedDocumentID else { return filteredDocuments.first }
        return filteredDocuments.first { $0.id == selectedDocumentID } ?? filteredDocuments.first
    }

    private func openSelectedDocument() {
        guard let selectedDocument else { return }
        open(selectedDocument)
    }

    private func selectResult(offset: Int) {
        let records = filteredDocuments
        guard !records.isEmpty else {
            selectedDocumentID = nil
            return
        }

        let currentIndex = selectedDocumentID
            .flatMap { selectedID in records.firstIndex { $0.id == selectedID } }
            ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), records.count - 1)
        selectedDocumentID = records[nextIndex].id
    }

    private func syncSelection() {
        let records = filteredDocuments
        guard !records.isEmpty else {
            selectedDocumentID = nil
            return
        }

        if let selectedDocumentID,
           records.contains(where: { $0.id == selectedDocumentID }) {
            return
        }

        selectedDocumentID = records[0].id
    }
}

struct KeybindingUI: View {
    
    let keys: [String];
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Image(systemName: key)
                    .font(.system(size: 11))
                    .padding(7)
                    .frame(width: 14+11, height: 14+11)
                    .background(.white.opacity(0.1))
                    .cornerRadius(7)
            }
        }
    }
}

struct SearchResultRow: View {
    let record: ExcalidrawDocumentRecord
    let isSelected: Bool;

    var body: some View {
        HStack(spacing: 9) {
            ThumbnailView(record: record, type: .small)
            Text(record.title)
                .font(DriftTypography.hudFieldValue)
                .lineLimit(1)

            Spacer()
        }
        .padding(8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(.primary)
    }

    private var rowBackground: Color {
        isSelected ? Color.white.opacity(0.1) : Color.clear
    }
}

struct ExcalidrawSearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequest: Int
    let submit: () -> Void
    let moveSelection: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            focusRequest: focusRequest,
            submit: submit,
            moveSelection: moveSelection
        )
    }

    func makeNSView(context: Context) -> SearchTextField {
        let textField = SearchTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        textField.textColor = .labelColor
        context.coordinator.requestFocus(for: textField)
        return textField
    }

    func updateNSView(_ textField: SearchTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.submit = submit
        context.coordinator.moveSelection = moveSelection
        if textField.stringValue != text {
            textField.stringValue = text
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            context.coordinator.requestFocus(for: textField)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var focusRequest: Int
        var submit: () -> Void
        var moveSelection: (Int) -> Void

        init(
            text: Binding<String>,
            focusRequest: Int,
            submit: @escaping () -> Void,
            moveSelection: @escaping (Int) -> Void
        ) {
            self.text = text
            self.focusRequest = focusRequest
            self.submit = submit
            self.moveSelection = moveSelection
        }

        func requestFocus(for textField: SearchTextField) {
            DispatchQueue.main.async { [weak textField] in
                guard let textField,
                      let window = textField.window
                else {
                    return
                }
                window.makeFirstResponder(textField)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                moveSelection(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                moveSelection(1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                text.wrappedValue = textView.string
                submit()
                return true
            default:
                return false
            }
        }
    }
}

final class SearchTextField: NSTextField {}
