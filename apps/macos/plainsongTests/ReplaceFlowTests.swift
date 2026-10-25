import Foundation
@testable import Plainsong
import Testing

@Suite
struct ReplaceFlowTests {
    private func ranges(at locations: [Int]) -> [NSRange] {
        locations.map { NSRange(location: $0, length: 1) }
    }

    @Test
    func continuesFromStartAfterEnd() {
        var flow = ReplaceFlow(start: 10)
        #expect(flow.step(after: 11, in: ranges(at: [0, 20]), stopsAtEnd: false) == .select(1))
        // 末尾を越えたら先頭に戻り、始めた箇所より手前を探す
        #expect(flow.step(after: 21, in: ranges(at: [0, 20]), stopsAtEnd: false) == .select(0))
        #expect(flow.wrapped)
        // 始めた箇所まで一周したら終える
        #expect(flow.step(after: 1, in: ranges(at: [20]), stopsAtEnd: false) == .completed)
    }

    @Test
    func stopsAtEndWhenAsked() {
        var flow = ReplaceFlow(start: 10)
        #expect(flow.step(after: 21, in: ranges(at: [0]), stopsAtEnd: true) == .reachedEnd)
        #expect(!flow.wrapped)
    }

    @Test
    func excludesReplacedRanges() {
        var flow = ReplaceFlow(start: 0)
        // 「雨」を「霧雨」にしたあと、「霧雨」の中の「雨」は選び直さない
        flow.record([NSRange(location: 0, length: 2)])
        #expect(flow.excludes(NSRange(location: 1, length: 1)))
        #expect(!flow.excludes(NSRange(location: 2, length: 1)))
        #expect(flow.replacedCount == 1)
    }

    @Test
    func followsEdits() {
        var flow = ReplaceFlow(start: 10)
        flow.record([NSRange(location: 10, length: 2)])
        // 手前に3文字入れると、始めた箇所も置換した箇所も後ろにずれる
        flow.adjust(forEditIn: NSRange(location: 0, length: 3), changeInLength: 3)
        #expect(flow.start == 13)
        #expect(flow.replaced == [NSRange(location: 13, length: 2)])
        // 置換した箇所を書き換えると、記録から外れる
        flow.adjust(forEditIn: NSRange(location: 14, length: 1), changeInLength: 0)
        #expect(flow.replaced.isEmpty)
    }

    @Test
    func restartsKeepingReplacedRanges() {
        var flow = ReplaceFlow(start: 10)
        flow.record([NSRange(location: 10, length: 1)])
        #expect(flow.step(after: 11, in: [], stopsAtEnd: false) == .completed)
        flow.restart(at: 0)
        #expect(flow.start == 0)
        #expect(!flow.wrapped)
        #expect(flow.excludes(NSRange(location: 10, length: 1)))
    }

    @Test
    func movesToNeighbors() {
        let ranges = ranges(at: [0, 5, 9])
        func target(from location: Int, length: Int = 1, backwards: Bool = false, stops: Bool = false) -> Int? {
            let selection = NSRange(location: location, length: length)
            return FindNavigation(ranges: ranges, selection: selection, stopsAtEdges: stops)
                .target(backwards: backwards)?.index
        }
        #expect(target(from: 5) == 2)
        #expect(target(from: 3, length: 0) == 1)
        #expect(target(from: 9) == 0)
        #expect(target(from: 0, backwards: true) == 2)
    }

    @Test
    func stopsAtEdgesWhenAsked() {
        let ranges = ranges(at: [0, 5, 9])
        let last = FindNavigation(ranges: ranges, selection: NSRange(location: 9, length: 1), stopsAtEdges: true)
        #expect(last.target(backwards: false) == nil)
        #expect(last.target(backwards: true)?.index == 1)
        let first = FindNavigation(ranges: ranges, selection: NSRange(location: 0, length: 1), stopsAtEdges: true)
        #expect(first.target(backwards: true) == nil)
        #expect(first.isAtEdge(0, backwards: true))
        #expect(first.isAtEdge(2, backwards: false))
        #expect(!first.isAtEdge(1, backwards: false))
        #expect(FindNavigation(ranges: [], selection: NSRange(), stopsAtEdges: false).target(backwards: false) == nil)
    }

    @Test
    func warnsOnlyWhenStoppedWithoutReplacing() {
        #expect(FindOutcome.reachedStart.isWarning)
        #expect(FindOutcome.reachedEnd(replaced: 0).isWarning)
        // 末尾で止まっても、置換していれば流れをやり終えたものとする
        #expect(!FindOutcome.reachedEnd(replaced: 2).isWarning)
        #expect(!FindOutcome.completed(replaced: 0).isWarning)
        #expect(!FindOutcome.replacedAll(2).isWarning)
    }
}
