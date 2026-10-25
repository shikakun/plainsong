import Foundation

/// 位置と長さは`NSString`と同じUTF-16の単位で数える
nonisolated struct FindNavigation {
    let ranges: [NSRange]
    let selection: NSRange
    let stopsAtEdges: Bool

    /// 選択範囲とぴったり重なる一致を、いま選んでいる箇所とみなす
    var current: Int? {
        ranges.firstIndex(of: selection)
    }

    func target(backwards: Bool) -> (index: Int, wrapped: Bool)? {
        guard !ranges.isEmpty else { return nil }
        let found: Int?
        if backwards {
            found = ranges.lastIndex { $0.location < selection.location }
        } else {
            let start = current == nil ? selection.location : selection.location + 1
            found = ranges.firstIndex { $0.location >= start }
        }
        if let found {
            return (found, false)
        }
        guard !stopsAtEdges else { return nil }
        return (backwards ? ranges.count - 1 : 0, true)
    }

    func isAtEdge(_ index: Int, backwards: Bool) -> Bool {
        stopsAtEdges && index == (backwards ? 0 : ranges.count - 1)
    }
}

/// 1件ずつ置換していく流れ。始めた箇所まで一周するか、末尾で止まったところで終わる
nonisolated struct ReplaceFlow {
    enum Step: Equatable {
        case select(Int)
        case reachedEnd
        case completed
    }

    private(set) var start: Int
    /// 末尾から先頭に戻り、始めた箇所より手前を探している途中か
    private(set) var wrapped = false
    /// 置換した箇所。流れが続くあいだは一致から外し、下線を引いて示す
    private(set) var replaced: [NSRange] = []
    private(set) var replacedCount = 0

    /// 置換したあとの文字列に検索語が含まれていても、置換した箇所に重なる一致は選び直さない
    func excludes(_ range: NSRange) -> Bool {
        replaced.contains { replaced in
            NSIntersectionRange(replaced, range).length > 0
                || (range.length == 0 && NSLocationInRange(range.location, replaced))
        }
    }

    mutating func record(_ ranges: [NSRange]) {
        replaced += ranges
        replacedCount += ranges.count
    }

    /// 流れが終わったあとも続けて置換するときは、置換した箇所を覚えたまま、その位置からもう一周する
    mutating func restart(at location: Int) {
        start = location
        wrapped = false
    }

    /// rangesには、置換した箇所を除いた一致を、位置の順に並べて渡す
    mutating func step(after location: Int, in ranges: [NSRange], stopsAtEnd: Bool) -> Step {
        if let index = ranges.firstIndex(where: { $0.location >= location && (!wrapped || $0.location < start) }) {
            return .select(index)
        }
        guard !wrapped else { return .completed }
        if stopsAtEnd {
            return .reachedEnd
        }
        wrapped = true
        return ranges.firstIndex { $0.location < start }.map(Step.select) ?? .completed
    }

    /// 置換せずに移動して端を越えたとき、次へ進んだのなら先頭に戻ったものとし、前へ戻ったのなら最初の周に戻ったものとする
    mutating func didWrap(backwards: Bool) {
        wrapped = !backwards
    }

    /// 置換した箇所がさらに書き換えられたら、もう置換した文字を指していないので、記録から外す
    mutating func adjust(forEditIn editedRange: NSRange, changeInLength delta: Int) {
        let start = NSRange(location: start, length: 0)
        self.start = start.adjusted(forEditIn: editedRange, changeInLength: delta)?.location ?? NSMaxRange(editedRange)
        replaced = replaced.compactMap { $0.adjusted(forEditIn: editedRange, changeInLength: delta) }
    }
}

nonisolated enum FindOutcome {
    case reachedStart
    case reachedEnd(replaced: Int)
    case completed(replaced: Int)
    case replacedAll(Int)

    var message: String {
        switch self {
        case .reachedStart:
            String(localized: "find.status.reachedStart")
        case let .reachedEnd(count) where count > 0:
            String(localized: "find.status.reachedEnd.replaced \(count)")
        case .reachedEnd:
            String(localized: "find.status.reachedEnd")
        case let .completed(count) where count > 0:
            String(localized: "find.status.replaced \(count)")
        case .completed:
            String(localized: "find.status.searchedAll")
        case let .replacedAll(count):
            String(localized: "find.status.replaced \(count)")
        }
    }

    var isWarning: Bool {
        switch self {
        case .reachedStart:
            true
        case let .reachedEnd(count):
            count == 0
        case .completed, .replacedAll:
            false
        }
    }
}
