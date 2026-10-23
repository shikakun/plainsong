import Foundation

struct CharacterCountOptions: Equatable {
    var includesSpaces = true
    var includesIdeographicSpaces = true
    var includesTabs = false
    var includesNewlines = false

    private static let includesSpacesKey = "characterCount.includesSpaces"
    private static let includesIdeographicSpacesKey = "characterCount.includesIdeographicSpaces"
    private static let includesTabsKey = "characterCount.includesTabs"
    private static let includesNewlinesKey = "characterCount.includesNewlines"

    static func load(from defaults: UserDefaults) -> CharacterCountOptions {
        var options = CharacterCountOptions()
        options.includesSpaces = defaults.object(forKey: includesSpacesKey) as? Bool ?? options.includesSpaces
        options.includesIdeographicSpaces = defaults.object(forKey: includesIdeographicSpacesKey) as? Bool
            ?? options.includesIdeographicSpaces
        options.includesTabs = defaults.object(forKey: includesTabsKey) as? Bool ?? options.includesTabs
        options.includesNewlines = defaults.object(forKey: includesNewlinesKey) as? Bool ?? options.includesNewlines
        return options
    }

    func save(to defaults: UserDefaults) {
        defaults.set(includesSpaces, forKey: Self.includesSpacesKey)
        defaults.set(includesIdeographicSpaces, forKey: Self.includesIdeographicSpacesKey)
        defaults.set(includesTabs, forKey: Self.includesTabsKey)
        defaults.set(includesNewlines, forKey: Self.includesNewlinesKey)
    }

    /// NSTextStorageの文字列を直接たどらず、UTF-8でコピーしてから数える。10万字あると、パフォーマンスがおよそ5分の1になる
    func count(in string: NSString, range: NSRange? = nil) -> Int {
        let range = range ?? NSRange(location: 0, length: string.length)
        let capacity = range.length * 3
        let text = String(unsafeUninitializedCapacity: capacity) { buffer in
            var used = 0
            // 対になっていないサロゲートは、置き換えて1文字として数える
            string.getBytes(
                buffer.baseAddress,
                maxLength: capacity,
                usedLength: &used,
                encoding: String.Encoding.utf8.rawValue,
                options: .allowLossy,
                range: range,
                remaining: nil
            )
            return used
        }
        if includesSpaces, includesIdeographicSpaces, includesTabs, includesNewlines {
            return text.count
        }
        var count = 0
        for character in text where !excludes(character) {
            count += 1
        }
        return count
    }

    private func excludes(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        // 空白に結合文字が続くと、空白ではない1文字になる
        switch first.value {
        case 0x20: return !includesSpaces && scalars.count == 1
        case 0x3000: return !includesIdeographicSpaces && scalars.count == 1
        case 0x09: return !includesTabs && scalars.count == 1
        case 0x0A ... 0x0D, 0x85, 0x2028, 0x2029: return !includesNewlines && character.isNewline
        default: return false
        }
    }
}
