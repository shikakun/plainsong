import AppKit

/// ファイルにないキーと読めない値はnilにし、そのキーだけデフォルトの色を使う
struct Theme {
    var background: NSColor?
    var foreground: NSColor?
    var cursor: NSColor?
    var selectionBackground: NSColor?
    var selectionForeground: NSColor?

    /// Ghosttyの設定ファイルと同じく、同じキーは後の行を使い、空の値はそれまでの指定を取り消す
    init(ghosttyConfig text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let color = Self.color(parts[1].trimmingCharacters(in: .whitespaces))
            switch parts[0].trimmingCharacters(in: .whitespaces) {
            case "background": background = color
            case "foreground": foreground = color
            case "cursor-color": cursor = color
            case "selection-background": selectionBackground = color
            case "selection-foreground": selectionForeground = color
            default: continue
            }
        }
    }

    var hasColors: Bool {
        [background, foreground, cursor, selectionBackground, selectionForeground].contains { $0 != nil }
    }

    var appearance: NSAppearance? {
        guard let color = background?.usingColorSpace(.sRGB) else { return nil }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
        // 明度（L*）が50になる輝度を境目にする
        return NSAppearance(named: luminance > 0.184 ? .aqua : .darkAqua)
    }

    /// Ghosttyが受け付ける16進数の書き方（`#`は省略可、6桁か3桁）だけを読む。X11の色名は読まない
    private static func color(_ value: String) -> NSColor? {
        var digits = Substring(value)
        if digits.count >= 2, digits.hasPrefix("\""), digits.hasSuffix("\"") {
            digits = digits.dropFirst().dropLast()
        }
        if digits.hasPrefix("#") {
            digits = digits.dropFirst()
        }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let components: [CGFloat]
        switch digits.count {
        case 6:
            components = stride(from: 0, to: 6, by: 2).map { offset in
                let start = digits.index(digits.startIndex, offsetBy: offset)
                return CGFloat(Int(digits[start ..< digits.index(start, offsetBy: 2)], radix: 16) ?? 0) / 255
            }
        case 3:
            components = digits.map { CGFloat(($0.hexDigitValue ?? 0) * 17) / 255 }
        default:
            return nil
        }
        return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
    }
}

enum ThemeReference: Equatable {
    case standard
    case bundled(String)
    case imported(String)

    /// ファイル名には`/`を使えないので、区切りに使う
    private static let bundledPrefix = "bundled/"
    private static let importedPrefix = "imported/"

    init(rawValue: String) {
        if rawValue.hasPrefix(Self.bundledPrefix) {
            self = .bundled(String(rawValue.dropFirst(Self.bundledPrefix.count)))
        } else if rawValue.hasPrefix(Self.importedPrefix) {
            self = .imported(String(rawValue.dropFirst(Self.importedPrefix.count)))
        } else {
            self = .standard
        }
    }

    var rawValue: String {
        switch self {
        case .standard: "standard"
        case let .bundled(name): Self.bundledPrefix + name
        case let .imported(name): Self.importedPrefix + name
        }
    }
}

struct ThemeLibrary {
    private static let bundledDirectory = Bundle.main.url(forResource: "Themes", withExtension: nil)
    private static let defaultImportedDirectory = DraftLibrary.app.directory.appending(path: "Themes")

    private let importedDirectory: URL

    init(importedDirectory: URL = defaultImportedDirectory) {
        self.importedDirectory = importedDirectory
    }

    var bundledNames: [String] {
        Self.names(in: Self.bundledDirectory)
    }

    var importedNames: [String] {
        Self.names(in: importedDirectory)
    }

    func theme(for reference: ThemeReference) -> Theme? {
        let url = switch reference {
        case .standard: nil as URL?
        case let .bundled(name): Self.bundledDirectory?.appending(path: name)
        case let .imported(name): importedDirectory.appending(path: name)
        }
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Theme(ghosttyConfig: text)
    }

    /// ファイルシステムは大文字と小文字を区別しないことがある
    func importTheme(from url: URL) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard Theme(ghosttyConfig: text).hasColors else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: importedDirectory, withIntermediateDirectories: true)
        let existing = Set(importedNames.map { $0.lowercased() })
        let baseName = url.lastPathComponent
        var name = baseName
        var number = 2
        while existing.contains(name.lowercased()) {
            name = "\(baseName) \(number)"
            number += 1
        }
        try text.write(to: importedDirectory.appending(path: name), atomically: true, encoding: .utf8)
        return name
    }

    func removeImported(_ name: String) throws {
        try FileManager.default.removeItem(at: importedDirectory.appending(path: name))
    }

    private static func names(in directory: URL?) -> [String] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil,
                  options: .skipsHiddenFiles
              )
        else { return [] }
        return urls.map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
