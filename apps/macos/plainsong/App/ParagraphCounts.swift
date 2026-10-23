import Foundation

/// 書記素クラスタも単語も段落をまたがないので、全文の数は段落ごとの数の和になる
struct ParagraphCounts {
    private var paragraphs: [(length: Int, count: Int)] = []
    private(set) var total = 0

    init(string: NSString, count: (NSRange) -> Int) {
        update(
            string: string,
            editedRange: NSRange(location: 0, length: string.length),
            changeInLength: string.length,
            count: count
        )
    }

    /// `editedRange`と`delta`は、`NSTextStorage`の`editedRange`と`changeInLength`と同じく、編集したあとの位置で受け取る
    /// 改行を消したり、\rの直後に\nを入れたりすると前の段落とつながるので、編集した位置の1文字前の段落から数え直す
    mutating func update(
        string: NSString,
        editedRange: NSRange,
        changeInLength delta: Int,
        count: (NSRange) -> Int
    ) {
        var index = 0
        var location = 0
        func skipParagraphs(endingBy position: Int) {
            while index < paragraphs.count, location + paragraphs[index].length <= position {
                location += paragraphs[index].length
                index += 1
            }
        }
        skipParagraphs(endingBy: editedRange.location - 1)
        let first = index
        let start = location
        skipParagraphs(endingBy: NSMaxRange(editedRange) - delta)
        let removed = first ..< min(index + 1, paragraphs.count)
        let end = start + paragraphs[removed].reduce(0) { $0 + $1.length } + delta

        var inserted: [(length: Int, count: Int)] = []
        var paragraphStart = start
        while paragraphStart < end {
            let paragraph = string.paragraphRange(for: NSRange(location: paragraphStart, length: 0))
            inserted.append((paragraph.length, count(paragraph)))
            paragraphStart = NSMaxRange(paragraph)
        }
        total += inserted.reduce(0) { $0 + $1.count } - paragraphs[removed].reduce(0) { $0 + $1.count }
        paragraphs.replaceSubrange(removed, with: inserted)
    }

    func count(in range: NSRange, count: (NSRange) -> Int) -> Int {
        var result = 0
        var location = 0
        for paragraph in paragraphs {
            let paragraphRange = NSRange(location: location, length: paragraph.length)
            location += paragraph.length
            guard location > range.location else { continue }
            guard paragraphRange.location < NSMaxRange(range) else { break }
            guard let intersection = paragraphRange.intersection(range) else { continue }
            result += intersection == paragraphRange ? paragraph.count : count(intersection)
        }
        return result
    }
}
