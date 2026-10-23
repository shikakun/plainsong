import AppKit

/// 書いた内容を、アプリが落ちても失わないように保存する
///
/// 編集のたびに差分をジャーナルへ追記し、アプリが手前から外れたときに、全文をスナップショットへまとめる。
/// 追記はカーネルに渡した時点で、アプリが落ちても残る。Macごと落ちたときに備えて、入力が止まったらディスクまで書き出す。
/// 終了したときもジャーナルに残るので、次に起動したときに再生する。
///
/// ジャーナルは、元にしたスナップショットのハッシュ（UInt64）のあとにレコードが続く。
/// レコードは、チェックサム、置き換えた位置、消した長さ、入れた長さ（それぞれUInt32）と、入れた文字列からなる。
/// 位置と長さは`NSString`と同じUTF-16の単位で数え、文字列もUTF-16のまま持つ。
final class TextStore: NSObject, NSTextStorageDelegate {
    static let snapshotName = "text.txt"
    static let journalName = "journal"
    private static let headerSize = 8
    private static let recordHeaderSize = 16
    private static let idleDelay = Duration.seconds(2)

    private let directory: URL
    private var journal: FileHandle?
    private weak var storage: NSTextStorage?
    private var hasRecords = false
    /// ジャーナルへの追記に失敗したら、次の機会に全文を書き直す
    private var needsSave = false
    private var lastEdit = ContinuousClock.now
    private var flushTask: Task<Void, Never>?

    init(directory: URL) {
        self.directory = directory
    }

    private var snapshotURL: URL {
        directory.appending(path: Self.snapshotName)
    }

    private var journalURL: URL {
        directory.appending(path: Self.journalName)
    }

    /// スナップショットにジャーナルを再生した内容を返し、続きを追記できるようにする
    func restore() -> String {
        let snapshot = (try? Data(contentsOf: snapshotURL)) ?? Data()
        let journalData = (try? Data(contentsOf: journalURL)) ?? Data()
        let base = Self.hash(snapshot)
        // 壊れたバイトがあっても全体を捨てず、読めるところは残す
        // swiftlint:disable:next optional_data_string_conversion
        let text = NSMutableString(string: String(decoding: snapshot, as: UTF8.self))
        let journalBase = journalData.count >= Self.headerSize
            ? journalData.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            : nil
        var validEnd = 0
        // ハッシュが違うのは、まとめ終えてからジャーナルを空にするまでに落ちたとき。差分はすでにスナップショットに入っている
        if journalBase == base {
            validEnd = Self.replay(journalData, onto: text)
            hasRecords = validEnd > Self.headerSize
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if validEnd == 0 {
                try Self.header(base).write(to: journalURL)
                validEnd = Self.headerSize
            }
            let journal = try FileHandle(forWritingTo: journalURL)
            // 書いている途中で落ちて切れたレコードを捨て、続きをそこから書く
            try journal.truncate(atOffset: UInt64(validEnd))
            self.journal = journal
        } catch {
            needsSave = true
        }
        return text as String
    }

    func track(_ storage: NSTextStorage) {
        self.storage = storage
        storage.delegate = self
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        append(Self.record(replacing: editedRange.length - delta, with: editedRange, of: textStorage.mutableString))
        scheduleFlush()
    }

    func save() {
        guard hasRecords || needsSave, let storage else { return }
        let data = Data(storage.string.utf8)
        let temporaryURL = directory.appending(path: Self.snapshotName + ".tmp")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: temporaryURL)
            let temporary = try FileHandle(forWritingTo: temporaryURL)
            try Self.synchronize(temporary)
            try temporary.close()
            guard rename(temporaryURL.path, snapshotURL.path) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            // スナップショットを入れ替えてから空にする。逆の順で落ちると、ジャーナルにしかない差分を失う
            let journal = try journal ?? FileHandle(forWritingTo: journalURL)
            try journal.truncate(atOffset: 0)
            try journal.write(contentsOf: Self.header(Self.hash(data)))
            try Self.synchronize(journal)
            self.journal = journal
            hasRecords = false
            needsSave = false
        } catch {
            needsSave = true
        }
    }

    func delete() {
        flushTask?.cancel()
        flushTask = nil
        try? journal?.close()
        journal = nil
        if storage?.delegate === self {
            storage?.delegate = nil
        }
        storage = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func append(_ record: Data) {
        guard let journal, !needsSave else { return }
        do {
            try journal.write(contentsOf: record)
            hasRecords = true
        } catch {
            needsSave = true
        }
    }

    /// 打鍵のたびにタスクを作らないよう、ひとつのタスクが最後の編集から一定時間たつまで待ち続ける
    private func scheduleFlush() {
        lastEdit = .now
        guard flushTask == nil else { return }
        flushTask = Task {
            var deadline = lastEdit + Self.idleDelay
            while deadline > .now {
                try? await Task.sleep(until: deadline)
                guard !Task.isCancelled else { return }
                deadline = lastEdit + Self.idleDelay
            }
            flushTask = nil
            if needsSave {
                save()
            } else if let journal {
                try? Self.synchronize(journal)
            }
        }
    }

    private static func synchronize(_ handle: FileHandle) throws {
        // fsyncだけではドライブのキャッシュに残り、電源が落ちると失われることがある
        if fcntl(handle.fileDescriptor, F_FULLFSYNC) == -1 {
            try handle.synchronize()
        }
    }

    private static func header(_ base: UInt64) -> Data {
        withUnsafeBytes(of: base) { Data($0) }
    }

    private static func record(replacing removed: Int, with range: NSRange, of string: NSString) -> Data {
        var record = Data(count: recordHeaderSize + range.length * 2)
        record.withUnsafeMutableBytes { bytes in
            for (index, value) in [range.location, removed, range.length].enumerated() {
                bytes.storeBytes(of: UInt32(value), toByteOffset: 4 + index * 4, as: UInt32.self)
            }
            if let characters = bytes.baseAddress?.advanced(by: recordHeaderSize) {
                string.getCharacters(characters.assumingMemoryBound(to: unichar.self), range: range)
            }
            bytes.storeBytes(of: checksum(UnsafeRawBufferPointer(rebasing: bytes[4...])), as: UInt32.self)
        }
        return record
    }

    /// 壊れたレコードがあれば、そこで止める。返すのは、正しく読めたところまでのバイト数
    private static func replay(_ journal: Data, onto text: NSMutableString) -> Int {
        journal.withUnsafeBytes { bytes in
            var offset = headerSize
            while bytes.count - offset >= recordHeaderSize {
                let fields = (0 ..< 4).map {
                    Int(bytes.loadUnaligned(fromByteOffset: offset + $0 * 4, as: UInt32.self))
                }
                let (location, removed, inserted) = (fields[1], fields[2], fields[3])
                let end = offset + recordHeaderSize + inserted * 2
                guard end <= bytes.count,
                      fields[0] == checksum(UnsafeRawBufferPointer(rebasing: bytes[offset + 4 ..< end])),
                      location + removed <= text.length
                else { break }
                var characters = [unichar](repeating: 0, count: inserted)
                characters.withUnsafeMutableBytes {
                    $0.copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[offset + recordHeaderSize ..< end]))
                }
                text.replaceCharacters(
                    in: NSRange(location: location, length: removed),
                    with: NSString(characters: characters, length: inserted) as String
                )
                offset = end
            }
            return offset
        }
    }

    private static func checksum(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        UInt32(truncatingIfNeeded: hash(bytes))
    }

    private static func hash(_ data: Data) -> UInt64 {
        data.withUnsafeBytes { hash($0) }
    }

    /// FNV-1a。プロセスごとに種が変わる`Hasher`は、ファイルに残す値には使えない
    private static func hash(_ bytes: UnsafeRawBufferPointer) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return hash
    }
}
