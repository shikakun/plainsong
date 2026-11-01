import Foundation
@testable import Plainsong
import Testing

@Suite
struct MarkdownSyntaxTests {
    @Test
    func boldensHeadingsAndDimsMarks() {
        #expect(styled("## 見出し\n") == [
            Styled("##", [.marker, .monospaced, .unindented]),
            Styled(" ", [.bold, .monospaced, .unindented]),
            Styled("見出し", [.bold, .unindented]),
        ])
        #expect(styled("#ハッシュタグ\n").isEmpty)
        #expect(styled("####### 7つ\n").isEmpty)
    }

    @Test
    func readsStrongWithoutSurroundingSpaces() {
        #expect(styled("これは**太字**です") == [
            Styled("**", .marker),
            Styled("太字", .bold),
            Styled("**", .marker),
        ])
        #expect(styled("__太字__") == [
            Styled("__", .marker),
            Styled("太字", .bold),
            Styled("__", .marker),
        ])
        #expect(styled("** 太字ではない**").isEmpty)
    }

    @Test
    func readsCodeSpansBeforeOtherSyntax() {
        #expect(styled("`**a**` と ``a`b``") == [
            Styled("`", [.marker, .code]),
            Styled("**a**", .code),
            Styled("`", [.marker, .code]),
            Styled("``", [.marker, .code]),
            Styled("a`b", .code),
            Styled("``", [.marker, .code]),
        ])
        #expect(styled("閉じていない`バッククォート").isEmpty)
    }

    @Test
    func dimsBlockMarkers() {
        let indent: MarkdownSyntax.Style = [.monospaced, .unindented]
        #expect(styled("> - [x] 済み\n") == [
            Styled(">", [.marker, .unindented]),
            Styled(" ", .unindented),
            Styled("-", indent.union(.marker)),
            Styled(" ", indent),
            Styled("[x]", indent.union(.marker)),
            Styled(" ", indent),
            Styled("済み", .unindented),
        ])
        #expect(styled("12. 項目\n") == [
            Styled("12.", indent.union(.marker)),
            Styled(" ", indent),
            Styled("項目", .unindented),
        ])
        #expect(styled(" \t- 下の階層\n") == [
            Styled(" \t", indent),
            Styled("-", indent.union(.marker)),
            Styled(" ", indent),
            Styled("下の階層", .unindented),
        ])
        #expect(styled("* * *\n") == [Styled("* * *", .marker)])
        #expect(styled("-5度\n").isEmpty)
    }

    @Test
    func readsRowsStartingWithPipeAsTable() {
        let separator: MarkdownSyntax.Style = [.marker, .monospaced, .unindented]
        #expect(styled("| `a|b` | c\\|d |\n") == [
            Styled("|", separator),
            Styled(" ", .unindented),
            Styled("`", [.marker, .code, .unindented]),
            Styled("a|b", [.code, .unindented]),
            Styled("`", [.marker, .code, .unindented]),
            Styled(" ", .unindented),
            Styled("|", separator),
            Styled(" c\\|d ", .unindented),
            Styled("|", separator),
        ])
        #expect(styled("| --- |:-:|\n") == [Styled("| --- |:-:|", separator)])
        #expect(styled("a | b\n").isEmpty)
    }

    @Test
    func dimsLinkSyntaxButNotText() {
        #expect(styled("[Plainsong](https://plainsong.shikakun.com/ \"Title\")") == [
            Styled("[", .marker),
            Styled("](https://plainsong.shikakun.com/ \"Title\")", .marker),
        ])
        #expect(styled("![](icon.png)") == [Styled("![](icon.png)", .marker)])
    }

    @Test
    func dimsTags() {
        #expect(styled("<kbd>⌘</kbd><!-- メモ --> a < b") == [
            Styled("<kbd>", [.marker, .monospaced]),
            Styled("</kbd><!-- メモ -->", [.marker, .monospaced]),
        ])
    }

    @Test
    func unindentsLinesOfOnlyCodeOrHTML() {
        #expect(styled(" `a` \n").allSatisfy { $0.style.contains(.unindented) })
        #expect(styled("`a`と本文\n").allSatisfy { !$0.style.contains(.unindented) })
        #expect(styled("> `a`\n").allSatisfy { !$0.style.contains(.unindented) })
        #expect(styled("<b>a</b> \n").allSatisfy { $0.style.contains(.unindented) })
        #expect(styled("<b>a</b>b\n").allSatisfy { !$0.style.contains(.unindented) })
    }

    @Test
    func findsFencedCodeBlocks() {
        let string = "a\n```swift\nlet a = 1\n~~~\n```\nb\n  ~~~~\n```\n" as NSString
        let blocks = MarkdownSyntax.blocks(in: string)
        #expect(blocks.map { string.substring(with: $0.range) } == [
            "```swift\nlet a = 1\n~~~\n```\n",
            "  ~~~~\n```\n",
        ])
        #expect(blocks.map(\.isClosed) == [true, false])
    }

    @Test
    func readsBacktickFencesOnlyWithoutBackticksInInfo() {
        let string = "```a`b```\n# 見出し\n" as NSString
        #expect(MarkdownSyntax.blocks(in: string).isEmpty)
    }

    @Test
    func stylesCodeBlockLines() {
        let code: MarkdownSyntax.Style = [.code, .unindented]
        let fence = code.union(.marker)
        #expect(styled("```sh\n# 見出しではない\n```\n") == [
            Styled("```sh\n", fence),
            Styled("# 見出しではない\n", code),
            Styled("```\n", fence),
        ])
        #expect(styled("```\nコード") == [
            Styled("```\n", fence),
            Styled("コード", code),
        ])
    }

    @Test
    func readsFrontMatterOnlyAtStart() {
        let string = "---\ntitle: a\n---\n# 見出し\n" as NSString
        #expect(MarkdownSyntax.blocks(in: string) == [
            MarkdownSyntax.Block(range: NSRange(location: 0, length: 17), isClosed: true, isFrontMatter: true),
        ])
        #expect(MarkdownSyntax.blocks(in: "\n---\ntitle: a\n---\n").isEmpty)
        #expect(MarkdownSyntax.blocks(in: "---\n閉じていない\n").isEmpty)
    }

    @Test
    func dimsFrontMatterWithoutStylingContents() {
        #expect(styled("---\n# title: a\n---\n# 見出し\n") == [
            Styled("---\n# title: a\n---\n#", [.marker, .monospaced, .unindented]),
            Styled(" ", [.bold, .monospaced, .unindented]),
            Styled("見出し", [.bold, .unindented]),
        ])
    }

    @Test
    func readsImportsAndExportsOnlyInMDX() {
        let line = "import { Chart } from './chart'\n"
        #expect(styled(line, flavor: .mdx) == [Styled("import { Chart } from './chart'", [.code, .unindented])])
        #expect(styled(line).isEmpty)
        #expect(styled("  import a\n", flavor: .mdx).isEmpty)
    }

    @Test
    func readsOnlyLinesInRange() {
        let string = "# 1\n# 2\n# 3\n" as NSString
        let runs = MarkdownSyntax.runs(
            in: NSRange(location: 5, length: 0),
            of: string,
            blocks: [],
            flavor: .markdown
        )
        #expect(runs.map { string.substring(with: $0.range) } == ["#", " ", "2"])
    }

    private func styled(_ text: String, flavor: MarkdownSyntax.Flavor = .markdown) -> [Styled] {
        let string = text as NSString
        let runs = MarkdownSyntax.runs(
            in: NSRange(location: 0, length: string.length),
            of: string,
            blocks: MarkdownSyntax.blocks(in: string),
            flavor: flavor
        )
        return runs.map { Styled(string.substring(with: $0.range), $0.style) }
    }
}

private struct Styled: Equatable, CustomTestStringConvertible {
    let text: String
    let style: MarkdownSyntax.Style

    init(_ text: String, _ style: MarkdownSyntax.Style) {
        self.text = text
        self.style = style
    }

    var testDescription: String {
        "\(text.debugDescription): \(style.rawValue)"
    }
}
