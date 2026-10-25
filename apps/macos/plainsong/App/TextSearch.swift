import Foundation

/// 位置と長さは`NSString`と同じUTF-16の単位で数える
nonisolated struct TextSearch: Equatable {
    var pattern = ""
    var matchesCase = false
    /// NSRegularExpressionには全角と半角を同じとみなす指定がないので、正規表現では常に区別する
    var matchesWidth = true
    var usesRegularExpression = false

    struct InvalidPattern: Error {}

    struct Match {
        let range: NSRange
        fileprivate let result: NSTextCheckingResult?
    }

    func matches(in string: NSString) throws(InvalidPattern) -> [Match] {
        guard !pattern.isEmpty else { return [] }
        let range = NSRange(location: 0, length: string.length)
        if usesRegularExpression {
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if !matchesCase {
                options.insert(.caseInsensitive)
            }
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
                throw InvalidPattern()
            }
            return expression.matches(in: string as String, range: range).map { Match(range: $0.range, result: $0) }
        }
        var options: NSString.CompareOptions = []
        if !matchesCase {
            options.insert(.caseInsensitive)
        }
        if !matchesWidth {
            options.insert(.widthInsensitive)
        }
        var matches: [Match] = []
        var searchRange = range
        while searchRange.length > 0 {
            let found = string.range(of: pattern, options: options, range: searchRange)
            guard found.location != NSNotFound else { break }
            matches.append(Match(range: found, result: nil))
            searchRange = NSRange(location: NSMaxRange(found), length: NSMaxRange(range) - NSMaxRange(found))
        }
        return matches
    }

    static func replacement(for match: Match, in string: NSString, template: String) -> String {
        guard let result = match.result, let expression = result.regularExpression else { return template }
        return expression.replacementString(for: result, in: string as String, offset: 0, template: template)
    }
}

nonisolated extension NSRange {
    /// editedRangeには編集したあとの範囲を渡す。編集した箇所に重なる範囲は、もう同じ文字を指していないのでnilを返す
    func adjusted(forEditIn editedRange: NSRange, changeInLength delta: Int) -> NSRange? {
        let editEnd = NSMaxRange(editedRange) - delta
        if location >= editEnd {
            return NSRange(location: location + delta, length: length)
        }
        if NSMaxRange(self) <= editedRange.location {
            return self
        }
        return nil
    }

    func resized(forEditIn editedRange: NSRange, changeInLength delta: Int) -> NSRange {
        if let adjusted = adjusted(forEditIn: editedRange, changeInLength: delta) {
            return adjusted
        }
        let start = Swift.min(location, editedRange.location)
        let end = Swift.max(NSMaxRange(self) + delta, NSMaxRange(editedRange))
        return NSRange(location: start, length: end - start)
    }
}

nonisolated extension TextSearch {
    private static let matchesCaseKey = "findMatchesCase"
    private static let matchesWidthKey = "findMatchesWidth"
    private static let usesRegularExpressionKey = "findUsesRegularExpression"

    /// 検索語は検索用ペーストボードでほかのアプリと共有するので、ここには保存しない
    static func load(from defaults: UserDefaults) -> TextSearch {
        TextSearch(
            matchesCase: defaults.bool(forKey: matchesCaseKey),
            matchesWidth: defaults.object(forKey: matchesWidthKey) as? Bool ?? true,
            usesRegularExpression: defaults.bool(forKey: usesRegularExpressionKey)
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(matchesCase, forKey: Self.matchesCaseKey)
        defaults.set(matchesWidth, forKey: Self.matchesWidthKey)
        defaults.set(usesRegularExpression, forKey: Self.usesRegularExpressionKey)
    }
}
