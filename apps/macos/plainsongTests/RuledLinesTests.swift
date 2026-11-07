import AppKit
@testable import Plainsong
import Testing

@Suite
struct RuledLinesTests {
    private static let text = "あいう\n\n\n" + String(repeating: "あ", count: 200) + "\nAbg\n\n" + "明朝 English\n"

    private func makeEditor(
        _ text: String = text,
        orientation: EditorSettings.Orientation = .horizontal,
        configure: (inout EditorSettings) -> Void = { _ in }
    ) async -> EditorWindowController {
        var settings = EditorSettings()
        settings.orientation = orientation
        settings.guide = .ruledLines
        configure(&settings)
        let editor = EditorWindowController(text: text, settings: settings)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        return editor
    }

    private func rulesView(of editor: EditorWindowController) -> RuledLinesView? {
        editor.window?.contentView?.subviews.lazy.compactMap { $0 as? RuledLinesView }.first
    }

    /// カーソルの帯は字面の中心に合わせてあるので、行の位置の基準にできる
    private func lineMiddles(of editor: EditorWindowController) throws -> [CGFloat] {
        let layoutManager = try #require(editor.textView.textLayoutManager)
        let documentRange = try #require(layoutManager.textContentManager?.documentRange)
        var middles: [CGFloat] = []
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { _ in true }
        layoutManager.enumerateTextSegments(in: documentRange, type: .standard) { _, frame, _, _ in
            middles.append(frame.midY + editor.textView.textContainerOrigin.y)
            return true
        }
        return middles
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], EditorSettings.LineSpacing.allCases)
    func drawsRulesHalfwayBetweenLines(
        orientation: EditorSettings.Orientation,
        lineSpacing: EditorSettings.LineSpacing
    ) async throws {
        let editor = await makeEditor(orientation: orientation) {
            $0.lineSpacing = lineSpacing
            $0.addsParagraphSpacing = true
        }
        let view = try #require(rulesView(of: editor))
        let middles = try lineMiddles(of: editor)
        try #require(middles.count > 3)
        let last = try #require(middles.last)
        let rules = view.rulePositions(in: 0 ... last)
        #expect(rules.count == middles.count - 1)
        for (rule, pair) in zip(rules, zip(middles, middles.dropFirst())) {
            #expect(abs(rule - (pair.0 + pair.1) / 2) <= 1)
        }
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func continuesRulesPastTheLastLine(orientation: EditorSettings.Orientation) async throws {
        let editor = await makeEditor("あ\nい", orientation: orientation)
        let view = try #require(rulesView(of: editor))
        let middles = try lineMiddles(of: editor)
        let pitch = view.linePitch
        let last = try #require(middles.last)
        let rules = view.rulePositions(in: 0 ... last + pitch * 3)
        #expect(rules.count == 4)
        #expect(zip(rules, rules.dropFirst()).allSatisfy { abs($1 - $0 - pitch) <= 1 })
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func drawsRulesInAnEmptyDocument(orientation: EditorSettings.Orientation) async throws {
        let editor = await makeEditor("", orientation: orientation)
        let view = try #require(rulesView(of: editor))
        #expect(view.rulePositions(in: 0 ... view.linePitch * 2).count == 2)
    }

    /// スクロールした先でも、見えている範囲の端にかかる罫線を落とさない
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func findsRulesInAScrolledRange(orientation: EditorSettings.Orientation) async throws {
        let text = (0 ..< 300).map { "\($0)" }.joined(separator: "\n")
        let editor = await makeEditor(text, orientation: orientation)
        let view = try #require(rulesView(of: editor))
        let middles = try lineMiddles(of: editor)
        let last = try #require(middles.last)
        let all = view.rulePositions(in: 0 ... last)
        let range = all[100] - 1 ... all[110] + 1
        let found = view.rulePositions(in: range)
        #expect(found.count == 11)
        for (rule, expected) in zip(found, all[100 ... 110]) {
            #expect(abs(rule - expected) <= 0.01)
        }
    }

    @Test
    func showsRulesOnlyOnRuledLines() async {
        let editor = await makeEditor()
        #expect(rulesView(of: editor) != nil)

        var settings = EditorSettings()
        settings.guide = .manuscriptPaper
        editor.apply(settings)
        #expect(rulesView(of: editor) == nil)

        settings.guide = .blank
        editor.apply(settings)
        #expect(rulesView(of: editor) == nil)

        settings.guide = .ruledLines
        editor.apply(settings)
        #expect(rulesView(of: editor) != nil)
    }

    /// チェックを残したままガイドを切り替えるので、本文を組み直さないと余白が残る
    @Test
    func removesParagraphSpacingWhileGuideIsNotBlank() throws {
        var settings = EditorSettings()
        settings.addsParagraphSpacing = true
        let editor = EditorWindowController(text: "あ\nい", settings: settings)
        let storage = try #require(editor.textStorage)
        func spacing() -> CGFloat? {
            (storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing
        }
        #expect(try #require(spacing()) > 0)

        for guide in [EditorSettings.Guide.ruledLines, .manuscriptPaper] {
            settings.guide = guide
            editor.apply(settings)
            #expect(spacing() == 0)
            #expect(settings.paragraphStyle(lineHeight: 20).paragraphSpacing == 0)

            settings.guide = .blank
            editor.apply(settings)
            #expect(try #require(spacing()) > 0)
        }
    }

    @Test
    func keepsKerningMenuDisabledOnlyOnManuscriptPaper() {
        var settings = EditorSettings()
        for guide in EditorSettings.Guide.allCases {
            settings.guide = guide
            #expect(settings.allowsToggling(\.usesKerning) == (guide != .manuscriptPaper))
            #expect(settings.allowsToggling(\.usesReadableWidth))
        }
    }
}
