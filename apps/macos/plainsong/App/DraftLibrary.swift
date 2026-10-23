import Foundation

struct DraftLibrary {
    /// サンドボックスの外で動くテストやビルドでも、ほかのアプリのファイルと混ざらないよう、bundle IDの下に置く
    static let app = DraftLibrary(
        directory: .applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "plainsong")
    )

    let directory: URL

    private var draftsDirectory: URL {
        directory.appending(path: "Drafts")
    }

    var backupsDirectory: URL {
        directory.appending(path: "Backups")
    }

    func newBackupURL(for fileURL: URL) -> URL {
        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let name = fileURL.deletingPathExtension().lastPathComponent
        let pathExtension = fileURL.pathExtension
        for number in 1... {
            let base = number == 1 ? name : "\(name) \(number)"
            let url = backupsDirectory.appending(path: pathExtension.isEmpty ? base : "\(base).\(pathExtension)")
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        preconditionFailure("unreachable")
    }

    func store(for id: String) -> TextStore {
        TextStore(directory: draftsDirectory.appending(path: id))
    }

    /// 古い順に返す
    func ids() -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: draftsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []
        return urls
            .compactMap { url -> (String, Date)? in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
                guard values?.isDirectory == true else { return nil }
                return (url.lastPathComponent, values?.creationDate ?? .distantPast)
            }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .map(\.0)
    }

    func create(with text: String = "") -> String {
        let id = UUID().uuidString
        guard !text.isEmpty else { return id }
        let directory = draftsDirectory.appending(path: id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: directory.appending(path: TextStore.snapshotName))
        return id
    }
}
