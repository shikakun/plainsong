import AppKit

final class DocumentController: NSDocumentController {
    private var textDocuments: [TextDocument] {
        documents.compactMap { $0 as? TextDocument }
    }

    var editors: [EditorWindowController] {
        documents.flatMap(\.windowControllers).compactMap { $0 as? EditorWindowController }
    }

    var hasVisibleEditors: Bool {
        editors.contains { $0.window?.isVisible == true }
    }

    /// 下書きはファイルを持たないので、ウィンドウの状態に残した下書きのIDから開き直す
    override static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
    ) {
        guard let id = state.decodeObject(of: NSString.self, forKey: TextDocument.draftIDKey) as String?,
              let controller = shared as? DocumentController
        else {
            super.restoreWindow(withIdentifier: identifier, state: state, completionHandler: completionHandler)
            return
        }
        guard DraftLibrary.app.ids().contains(id) else {
            completionHandler(nil, CocoaError(.fileNoSuchFile))
            return
        }
        let document = controller.openDraft(id, display: false)
        completionHandler(document.windowControllers.first?.window, nil)
    }

    func showDrafts() {
        let ids = DraftLibrary.app.ids()
        guard !ids.isEmpty else {
            newDocument(nil)
            return
        }
        for id in ids {
            openDraft(id, display: true)
        }
    }

    /// ファイルに書き込まない自動保存は、間隔を決めないと働かない。間隔はファイルに書き込むときの標準に合わせる
    func apply(_ fileAutosave: EditorSettings.FileAutosave) {
        autosavingDelay = fileAutosave == .backup ? 15 : 0
    }

    func saveChanges() {
        for document in textDocuments {
            document.saveChanges()
        }
    }

    @discardableResult
    private func openDraft(_ id: String, display: Bool) -> TextDocument {
        if let document = textDocuments.first(where: { $0.draftID == id }) {
            if display {
                document.showWindows()
            }
            return document
        }
        let document = TextDocument(draftID: id)
        addDocument(document)
        document.makeWindowControllers()
        if display {
            document.showWindows()
        }
        return document
    }
}
