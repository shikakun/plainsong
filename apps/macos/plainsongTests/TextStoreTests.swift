import AppKit
import Foundation
@testable import Plainsong
import Testing

struct TextStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    private var journalURL: URL {
        directory.appending(path: TextStore.journalName)
    }

    private func relaunch() -> String {
        TextStore(directory: directory).restore()
    }

    private func relaunch(editing edit: (TextStore, NSTextStorage) throws -> Void) rethrows {
        let store = TextStore(directory: directory)
        let storage = NSTextStorage(string: store.restore())
        store.track(storage)
        try edit(store, storage)
    }

    @Test
    func restoresWithoutReplayingSavedEditsTwice() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var staleJournal = Data()
        try relaunch { store, storage in
            storage.replaceCharacters(in: NSRange(), with: "あいうえお👍")
            storage.replaceCharacters(in: NSRange(location: 1, length: 2), with: "a")
            #expect(relaunch() == "あaえお👍")

            staleJournal = try Data(contentsOf: journalURL)
            store.save()
            storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
            #expect(relaunch() == "aえお👍")
        }
        // スナップショットを入れ替えたあと、ジャーナルを空にする前に落ちた状態
        try staleJournal.write(to: journalURL)
        #expect(relaunch() == "あaえお👍")
    }

    @Test
    func discardsTornRecordAndContinues() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        relaunch { _, storage in
            storage.replaceCharacters(in: NSRange(), with: "あい")
            storage.replaceCharacters(in: NSRange(location: 2, length: 0), with: "う")
        }
        try Data(contentsOf: journalURL).dropLast(1).write(to: journalURL)

        relaunch { _, storage in
            #expect(storage.string == "あい")
            storage.replaceCharacters(in: NSRange(location: 2, length: 0), with: "え")
        }
        #expect(relaunch() == "あいえ")
    }
}
