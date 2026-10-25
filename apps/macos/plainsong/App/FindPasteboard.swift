import AppKit

struct FindPasteboard {
    private var changeCount: Int?

    static var hasString: Bool {
        NSPasteboard(name: .find).string(forType: .string)?.isEmpty == false
    }

    mutating func readChanges() -> String? {
        let pasteboard = NSPasteboard(name: .find)
        guard pasteboard.changeCount != changeCount else { return nil }
        changeCount = pasteboard.changeCount
        guard let string = pasteboard.string(forType: .string), !string.isEmpty else { return nil }
        return string
    }

    mutating func write(_ string: String) {
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        changeCount = pasteboard.changeCount
    }
}
