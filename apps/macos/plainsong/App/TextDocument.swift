import AppKit
import Synchronization
import UniformTypeIdentifiers

/// 下書きは何もしなくても保存されるので、NSDocumentには変更を知らせない。
/// そのため、NSDocumentの未保存の確認や自動保存は、下書きでは働かない。
final class TextDocument: NSDocument {
    static let draftIDKey = "draftID"
    private static let maxFileNameLength = 30
    private nonisolated static let errorDomain = "Plainsong.TextDocument"

    private(set) var draftID: String?
    private var draftStore: TextStore?
    private var pendingText = ""
    /// 終了するときはウィンドウが先に閉じるので、閉じたあとも本文を読めるよう、書類でも持っておく
    private var textStorage: NSTextStorage?
    private var fileEncoding = FileEncoding.utf8
    private var lineEnding = LineEnding.lf
    private var hasMixedLineEndings = false
    /// `data(ofType:)`には渡されないので、保存しているあいだ覚えておく
    private var savingOperation: NSDocument.SaveOperationType?
    /// 最後に読み書きした中身と、保存している途中の中身のハッシュ。中身は同じまま更新日時だけが変わったことを見分けるのに使う
    private nonisolated let fileHashes = Mutex<(saved: Int?, pending: Int?)>((nil, nil))
    private var disablesSuddenTermination = false

    private var editor: EditorWindowController? {
        windowControllers.first as? EditorWindowController
    }

    private var text: String {
        textStorage?.string ?? pendingText
    }

    convenience init(draftID: String) {
        self.init()
        fileType = UTType.plainText.identifier
        openDraft(draftID)
    }

    override nonisolated static var autosavesInPlace: Bool {
        EditorSettings.FileAutosave.current == .inPlace
    }

    override func makeWindowControllers() {
        // ⌘Nや複製で、名称未設定のまま作られた書類は、下書きにする
        if fileURL == nil, draftStore == nil {
            openDraft(DraftLibrary.app.create(with: pendingText))
        }
        let editor = EditorWindowController(text: pendingText, settings: .load())
        editor.fileEncoding = fileEncoding
        editor.lineEnding = lineEnding
        if hasMixedLineEndings {
            editor.noticeMixedLineEndings()
            hasMixedLineEndings = false
        }
        pendingText = ""
        addWindowController(editor)
        textStorage = editor.textStorage
        // 復元した内容を記録し直さないよう、本文に入れてから見張り始める
        if let textStorage {
            draftStore?.track(textStorage)
        }
    }

    private func openDraft(_ id: String) {
        let store = DraftLibrary.app.store(for: id)
        pendingText = store.restore()
        draftID = id
        draftStore = store
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        guard draftStore == nil else { return }
        super.updateChangeCount(change)
        updateSuddenTermination()
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        updateSuddenTermination()
    }

    /// 自動保存がオンの書類は閉じるボタンに未保存の点を出さないので、ウィンドウの表示ではなく書類の状態で決める
    private func updateSuddenTermination(closing: Bool = false) {
        let disables = !closing && (isDocumentEdited || hasUnautosavedChanges)
        guard disables != disablesSuddenTermination else { return }
        disablesSuddenTermination = disables
        if disables {
            ProcessInfo.processInfo.disableSuddenTermination()
        } else {
            ProcessInfo.processInfo.enableSuddenTermination()
        }
    }

    override var isDocumentEdited: Bool {
        draftStore == nil && super.isDocumentEdited
    }

    override var hasUnautosavedChanges: Bool {
        draftStore == nil && super.hasUnautosavedChanges
    }

    /// 空の下書きは、ほかに下書きがあれば消す。最後の1つは、次に開くときのために残す
    override func close() {
        if let draftStore {
            if textStorage?.length == 0, DraftLibrary.app.ids().count > 1 {
                draftStore.delete()
            } else {
                draftStore.save()
            }
        }
        updateSuddenTermination(closing: true)
        super.close()
    }

    /// 手前から外れたときに保存できない文字のダイアログを出さないよう、ほかの自動保存と同じく、取りやめてもよい保存にする
    func saveChanges() {
        if let draftStore {
            draftStore.save()
        } else if EditorSettings.FileAutosave.current != .off, hasUnautosavedChanges {
            autosave(withImplicitCancellability: true) { _ in }
        }
    }

    /// ファイルに書き込まない自動保存は、NSDocumentが選ぶ場所ではなく、設定ウィンドウから開けるバックアップのフォルダに書く
    override func autosave(
        withImplicitCancellability autosavingIsImplicitlyCancellable: Bool,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        if Self.autosavesInPlace {
            adoptModificationDateIfContentsUnchanged()
        } else if autosavedContentsFileURL == nil, let fileURL {
            autosavedContentsFileURL = DraftLibrary.app.newBackupURL(for: fileURL)
        }
        super.autosave(
            withImplicitCancellability: autosavingIsImplicitlyCancellable,
            completionHandler: completionHandler
        )
    }

    /// ネットワークのボリュームなどでは、更新日時が変わっても`presentedItemDidChange()`が呼ばれないことがあるので、保存する前にも確かめる
    override func save(
        withDelegate delegate: Any?,
        didSave didSaveSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        adoptModificationDateIfContentsUnchanged()
        super.save(withDelegate: delegate, didSave: didSaveSelector, contextInfo: contextInfo)
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        // 続けて入力した文字が、保存する前の取り消しの単位にまとめられると、NSDocumentが変更に気づかない
        editor?.breakUndoCoalescing()
        savingOperation = saveOperation
        super.save(to: url, ofType: typeName, for: saveOperation) { [self] error in
            savingOperation = nil
            // 入力が止まったときの自動保存では、保存できない文字のダイアログを出さずに見送り、⌘Sや閉じるときに尋ねる
            var error = error
            let isUnencodable = (error as NSError?)?.domain == Self.errorDomain
            if isUnencodable, saveOperation == .autosaveInPlaceOperation, autosavingIsImplicitlyCancellable {
                error = CocoaError(.userCancelled)
            }
            // バックアップへの自動保存と書き出しは、書類のファイルを書き換えない
            let updatesFile = [.saveOperation, .saveAsOperation, .autosaveInPlaceOperation].contains(saveOperation)
            fileHashes.withLock { hashes in
                if error == nil, updatesFile {
                    hashes.saved = hashes.pending
                }
                hashes.pending = nil
            }
            // 書き出しのように、保存しても書類がファイルに結び付かない操作では、下書きのままにする
            if error == nil, fileURL != nil, let draftStore {
                draftStore.delete()
                self.draftStore = nil
                draftID = nil
                for controller in windowControllers {
                    controller.window?.invalidateRestorableState()
                }
            }
            completionHandler(error)
        }
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if fileURL == nil, let name = Self.fileName(for: text) {
            savePanel.nameFieldStringValue = name
        }
        return true
    }

    /// バックアップは書いた内容を残すためのものなので、保存できない文字があればUTF-8で書く
    override func data(ofType _: String) throws -> Data {
        let text = lineEnding.normalizing(text)
        let fallback = savingOperation == .autosaveElsewhereOperation ? Data(text.utf8) : nil
        guard let data = fileEncoding.encode(text) ?? fallback else {
            throw unencodableError()
        }
        let hash = Self.contentHash(data)
        fileHashes.withLock { $0.pending = hash }
        return data
    }

    /// canConcurrentlyReadDocumentsを有効にしていないので、メインスレッドで呼ばれる
    override nonisolated func read(from url: URL, ofType _: String) throws {
        let data = try Data(contentsOf: url)
        let (string, fileEncoding) = try FileEncoding.decode(
            data,
            attributeEncoding: FileEncoding.attributeEncoding(at: url)
        )
        let (lineEnding, isMixed) = LineEnding.detect(in: string)
        let hash = Self.contentHash(data)
        fileHashes.withLock { $0 = (hash, nil) }
        MainActor.assumeIsolated {
            self.fileEncoding = fileEncoding
            self.lineEnding = lineEnding
            if let editor {
                editor.fileEncoding = fileEncoding
                editor.lineEnding = lineEnding
                editor.replaceText(string)
                undoManager?.removeAllActions()
                if isMixed {
                    editor.noticeMixedLineEndings()
                }
            } else {
                pendingText = string
                hasMixedLineEndings = isMixed
            }
        }
    }

    /// NSDocumentが保存するたびにファイルの拡張属性を消すので、書き込んだあとに付け直す
    /// canAsynchronouslyWriteを有効にしていないので、メインスレッドで呼ばれる
    override nonisolated func writeSafely(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType
    ) throws {
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        guard saveOperation != .autosaveElsewhereOperation else { return }
        MainActor.assumeIsolated {
            fileEncoding.writeAttribute(to: url)
        }
    }

    private func unencodableError() -> NSError {
        NSError(domain: Self.errorDomain, code: 0, userInfo: [
            NSLocalizedDescriptionKey: String(localized: "error.unencodable.title \(fileEncoding.name)"),
            // NSDocumentが見出しを「保存できませんでした」に差し替えるので、理由も説明文に含める
            NSLocalizedRecoverySuggestionErrorKey: String(
                localized: "error.unencodable.message \(fileEncoding.name) \(fileEncoding.name)"
            ),
            NSLocalizedRecoveryOptionsErrorKey: [
                String(localized: "error.unencodable.saveAsUTF8"),
                String(localized: "error.unencodable.cancel"),
            ],
            NSRecoveryAttempterErrorKey: self,
        ])
    }

    /// 回復できたと伝えると、NSDocumentが保存をやり直す
    override nonisolated func attemptRecovery(
        fromError error: any Error,
        optionIndex recoveryOptionIndex: Int,
        delegate: Any?,
        didRecoverSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard (error as NSError).domain == Self.errorDomain else {
            super.attemptRecovery(
                fromError: error,
                optionIndex: recoveryOptionIndex,
                delegate: delegate,
                didRecoverSelector: didRecoverSelector,
                contextInfo: contextInfo
            )
            return
        }
        let didRecover = recoveryOptionIndex == 0
        if didRecover {
            MainActor.assumeIsolated {
                fileEncoding = .utf8
                editor?.fileEncoding = .utf8
            }
        }
        // `- (void)didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo`のシグネチャで、結果を呼び出し元に返す
        guard let delegate = delegate as AnyObject?,
              let didRecoverSelector,
              delegate.responds(to: didRecoverSelector)
        else { return }
        typealias Callback = @convention(c) (AnyObject, Selector, Bool, UnsafeMutableRawPointer?) -> Void
        let callback = unsafeBitCast(delegate.method(for: didRecoverSelector), to: Callback.self)
        callback(delegate, didRecoverSelector, didRecover, contextInfo)
    }

    /// クラウドのストレージなどは、中身を変えずに更新日時だけを変えることがある。中身が同じなら、更新日時を合わせるだけにする
    /// NSDocumentに任せると、自動保存がファイルに書き込む設定では読み直して取り消しの履歴を消し、そうでなければ保存するときに、ほかのアプリが変更したと警告する
    override nonisolated func presentedItemDidChange() {
        guard !adoptModificationDateIfContentsUnchanged() else { return }
        super.presentedItemDidChange()
    }

    @discardableResult
    private nonisolated func adoptModificationDateIfContentsUnchanged() -> Bool {
        guard var url = presentedItemURL else { return false }
        url.removeCachedResourceValue(forKey: .contentModificationDateKey)
        let knownDate = fileModificationDate
        let hashes = fileHashes.withLock { $0 }
        var modificationDate: Date?
        let coordinator = NSFileCoordinator(filePresenter: self)
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { url in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date != knownDate,
                  let data = try? Data(contentsOf: url),
                  [hashes.saved, hashes.pending].contains(Self.contentHash(data))
            else { return }
            modificationDate = date
        }
        // 確かめているあいだに保存していたら、保存した日時を残す
        guard let modificationDate, fileModificationDate == knownDate else { return false }
        fileModificationDate = modificationDate
        return true
    }

    /// 書き込んだ中身と比べるだけで、ファイルには残さないので、プロセスごとに種が変わる`Hasher`を使える
    private nonisolated static func contentHash(_ data: Data) -> Int {
        var hasher = Hasher()
        data.withUnsafeBytes { hasher.combine(bytes: $0) }
        return hasher.finalize()
    }

    static func fileName(for text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let name = String((line ?? "").prefix(maxFileNameLength))
            .replacing(/[\/:]/, with: "-")
            // 先頭が「.」だと隠しファイルになる
            .trimmingPrefix(/\.+/)
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
