import AppKit
@testable import Plainsong
import Testing

@Suite
struct MarkdownHighlighterTests {
    @Test
    func readsEveryDocumentAsMarkdownExceptMDX() {
        #expect(MarkdownSyntax.Flavor(url: nil) == .markdown)
        #expect(MarkdownSyntax.Flavor(url: URL(filePath: "/メモ.txt")) == .markdown)
        #expect(MarkdownSyntax.Flavor(url: URL(filePath: "/README.md")) == .markdown)
        #expect(MarkdownSyntax.Flavor(url: URL(filePath: "/page.mdx")) == .mdx)
    }

    @Test
    func adjustsRangesForEdits() {
        let edited = NSRange(location: 10, length: 3)
        #expect(MarkdownHighlighter.range(NSRange(location: 0, length: 5), adjustedFor: edited, delta: 2)
            == NSRange(location: 0, length: 5))
        #expect(MarkdownHighlighter.range(NSRange(location: 20, length: 5), adjustedFor: edited, delta: 2)
            == NSRange(location: 22, length: 5))
        #expect(MarkdownHighlighter.range(NSRange(location: 5, length: 10), adjustedFor: edited, delta: 2)
            == NSRange(location: 5, length: 12))
        #expect(MarkdownHighlighter.range(NSRange(location: 11, length: 10), adjustedFor: edited, delta: -1)
            == NSRange(location: 10, length: 10))
    }

    @Test
    func rereadsLinesAfterEditingFences() async throws {
        let textView = NSTextView(usingTextLayoutManager: true)
        let storage = try #require(textView.textStorage)
        let highlighter = MarkdownHighlighter(textView: textView)
        textView.string = "# 見出し\n本文\n"
        highlighter.update(flavor: .markdown, appearance: .init(settings: EditorSettings(), theme: nil))
        #expect(style(at: 0, in: storage).contains(.monospaced))

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "```\n")
        await waitUntil { style(at: 4, in: storage).contains(.code) }
        #expect(!style(at: 4, in: storage).contains(.monospaced))
        #expect(style(at: storage.length - 2, in: storage).contains(.code))

        storage.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
        await waitUntil { style(at: 0, in: storage).contains(.monospaced) }
        #expect(style(at: storage.length - 2, in: storage).isEmpty)
    }

    @Test
    func clearsStylesWhenTurnedOff() {
        let textView = NSTextView(usingTextLayoutManager: true)
        let highlighter = MarkdownHighlighter(textView: textView)
        let appearance = MarkdownHighlighter.Appearance(settings: EditorSettings(), theme: nil)
        textView.string = "**太字**"
        highlighter.update(flavor: .markdown, appearance: appearance)
        highlighter.update(flavor: nil, appearance: appearance)
        let storage = textView.textStorage
        #expect(storage?.attribute(.markdownStyle, at: 2, effectiveRange: nil) == nil)
        #expect(storage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont == appearance.font)
    }

    @Test
    func typesWithoutInheritingStyles() {
        let textView = NSTextView(usingTextLayoutManager: true)
        let highlighter = MarkdownHighlighter(textView: textView)
        let appearance = MarkdownHighlighter.Appearance(settings: EditorSettings(), theme: nil)
        highlighter.update(flavor: .markdown, appearance: appearance)
        let attributes = highlighter.plainAttributes([
            .markdownStyle: MarkdownSyntax.Style.bold.rawValue,
            .font: appearance.boldFont,
            .kern: 0,
        ])
        #expect(attributes[.markdownStyle] == nil)
        #expect(attributes[.font] as? NSFont == appearance.font)
        #expect(attributes[.kern] as? Int == 0)
    }

    @Test
    func laysOutUnindentedLinesWithoutIndent() throws {
        let contentStorage = NSTextContentStorage()
        let storage = try #require(contentStorage.textStorage)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 16
        storage.setAttributedString(NSAttributedString(
            string: "# 見出し\n本文\n",
            attributes: [.paragraphStyle: paragraphStyle]
        ))
        storage.addAttribute(
            .markdownStyle,
            value: MarkdownSyntax.Style.unindented.rawValue,
            range: NSRange(location: 0, length: 5)
        )
        let layout = { (location: Int, length: Int) in
            let paragraph = ParagraphIndentRules.shared.textContentStorage(
                contentStorage,
                textParagraphWith: NSRange(location: location, length: length)
            )
            let style = paragraph?.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            return style as? NSParagraphStyle
        }
        #expect(layout(0, 6)?.firstLineHeadIndent == 0)
        #expect(layout(6, 3) == nil)
    }

    private func style(at location: Int, in storage: NSTextStorage) -> MarkdownSyntax.Style {
        let value = storage.attribute(.markdownStyle, at: location, effectiveRange: nil) as? Int
        return MarkdownSyntax.Style(rawValue: value ?? 0)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 10 where !condition() {
            await Task.yield()
        }
        #expect(condition())
    }
}
