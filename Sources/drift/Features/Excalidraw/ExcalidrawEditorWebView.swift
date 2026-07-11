import AppKit
import SwiftUI
import WebKit

/// WKWebView wrapper that bridges the bundled Excalidraw host to the native document store.
struct ExcalidrawEditorWebView: NSViewRepresentable {
    /// Local server base URL.
    let serverURL: URL
    /// Drawing currently edited.
    let document: ExcalidrawDocumentRecord
    /// Raw Excalidraw JSON loaded from disk.
    let documentJSON: String
    /// Store used for autosaves.
    let documentStore: ExcalidrawDocumentStore
    /// Whether the embedded editor should actively claim keyboard focus.
    let shouldFocusEditor: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(documentStore: documentStore)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "drift")
        let webView = FocusableExcalidrawWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.shouldFocusEditor = shouldFocusEditor
        context.coordinator.load(serverURL: serverURL, document: document, documentJSON: documentJSON)
        if shouldFocusEditor {
            webView.claimEditorFocus()
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.documentStore = documentStore
        context.coordinator.webView = webView
        context.coordinator.shouldFocusEditor = shouldFocusEditor
        context.coordinator.load(serverURL: serverURL, document: document, documentJSON: documentJSON)
        if shouldFocusEditor {
            (webView as? FocusableExcalidrawWebView)?.claimEditorFocus()
        }
    }

    /// Message handler and navigation delegate for the Excalidraw web host.
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var documentStore: ExcalidrawDocumentStore
        weak var webView: WKWebView?
        var shouldFocusEditor = true

        private var loadedServerURL: URL?
        private var pendingDocument: (record: ExcalidrawDocumentRecord, json: String)?
        private var sentDocumentID: String?
        private var webHostReady = false

        init(documentStore: ExcalidrawDocumentStore) {
            self.documentStore = documentStore
        }

        func load(serverURL: URL, document: ExcalidrawDocumentRecord, documentJSON: String) {
            pendingDocument = (document, documentJSON)
            if loadedServerURL != serverURL {
                loadedServerURL = serverURL
                webHostReady = false
                sentDocumentID = nil
                webView?.load(URLRequest(url: serverURL))
                return
            }
            sendPendingDocumentIfReady()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            sendPendingDocumentIfReady()
            claimEditorFocusIfNeeded()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "drift",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else {
                return
            }

            switch type {
            case "ready":
                webHostReady = true
                sendPendingDocumentIfReady()
                claimEditorFocusIfNeeded()
            case "change":
                receiveChange(body)
            default:
                break
            }
        }

        private func sendPendingDocumentIfReady() {
            guard webHostReady,
                  let webView,
                  let pendingDocument
            else {
                return
            }
            guard sentDocumentID != pendingDocument.record.id else { return }

            let documentObject: Any
            if let data = pendingDocument.json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                documentObject = object
            } else {
                documentObject = [:]
            }

            let payload: [String: Any] = [
                "documentID": pendingDocument.record.id,
                "title": pendingDocument.record.title,
                "preferredTheme": pendingDocument.record.preferredTheme.rawValue,
                "document": documentObject
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8)
            else {
                return
            }

            sentDocumentID = pendingDocument.record.id
            webView.evaluateJavaScript(
                "window.driftExcalidrawLoad && window.driftExcalidrawLoad(\(json)); window.driftExcalidrawFocus && window.driftExcalidrawFocus();"
            )
            claimEditorFocusIfNeeded()
        }

        private func claimEditorFocusIfNeeded() {
            guard shouldFocusEditor else { return }
            (webView as? FocusableExcalidrawWebView)?.claimEditorFocus()
        }

        private func receiveChange(_ body: [String: Any]) {
            guard let documentID = body["documentID"] as? String,
                  let document = body["document"] as? String
            else {
                return
            }

            let payload = ExcalidrawDocumentPayload(
                document: document,
                thumbnailDataURL: body["thumbnailDataURL"] as? String,
                themePreference: (body["themePreference"] as? String)
                    .flatMap(ExcalidrawThemePreference.init(rawValue:)),
                thumbnailTheme: (body["thumbnailTheme"] as? String)
                    .flatMap(ExcalidrawResolvedTheme.init(rawValue:))
            )
            Task { @MainActor [documentStore] in
                _ = try? documentStore.save(documentID: documentID, payload: payload)
            }
        }
    }
}

private final class FocusableExcalidrawWebView: WKWebView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        claimEditorFocus()
    }

    override func mouseDown(with event: NSEvent) {
        claimEditorFocus()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        claimEditorFocus()
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        claimEditorFocus()
        super.otherMouseDown(with: event)
    }

    func claimEditorFocus() {
        guard let window,
              window.canBecomeKey
        else {
            return
        }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
        window.makeFirstResponder(self)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self,
                  let window,
                  self.window === window
            else {
                return
            }
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            if !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
            }
            window.makeFirstResponder(self)
        }
    }
}
