import SwiftUI

struct ExcalidrawEditorContent: View {
    @ObservedObject var worker: ExcalidrawBackgroundWorker
    @ObservedObject var documents: ExcalidrawDocumentStore

    let documentID: String
    let screenFrame: CGRect
    let pendingError: String?
    let shouldFocusEditor: Bool

    var body: some View {
        let size = ExcalidrawHUDStyle.editorSize(screenFrame: screenFrame)
        if let record = documents.document(id: documentID),
           let serverURL = worker.serverURL {
            ExcalidrawEditorWebView(
                serverURL: serverURL,
                document: record,
                documentJSON: documents.documentJSON(for: record),
                documentStore: documents,
                shouldFocusEditor: shouldFocusEditor
            )
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            VStack(spacing: 12) {
                Text(worker.serverError ?? pendingError ?? "Preparing Excalidraw...")
                    .font(DriftTypography.hudAction)
                Button("Retry") {
                    worker.restartServer()
                }
                .tint(Color.excalidrawAccent)
            }
            .padding([.vertical, .horizontal], ExcalidrawHUDStyle.padding)
            .frame(width: size.width, height: size.height)
            .background(.ultraThickMaterial)
            .cornerRadius(ExcalidrawHUDStyle.cornerRadius)
            .overlay(
                    RoundedRectangle(cornerRadius: ExcalidrawHUDStyle.cornerRadius)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .foregroundStyle(.primary)
        }
    }
}
