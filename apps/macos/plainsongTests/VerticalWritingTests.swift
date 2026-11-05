import AppKit
@testable import Plainsong
import Testing

@Suite
struct VerticalWritingTests {
    private func makeEditor(
        _ text: String,
        configure: (inout EditorSettings) -> Void = { _ in }
    ) async -> EditorWindowController {
        var settings = EditorSettings()
        settings.orientation = .vertical
        configure(&settings)
        let editor = EditorWindowController(text: text, settings: settings)
        await settle()
        return editor
    }

    private func settle() async {
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }

    private func attribute(_ key: NSAttributedString.Key, at location: Int, of editor: EditorWindowController) -> Any? {
        editor.textStorage?.attribute(key, at: location, effectiveRange: nil)
    }

    @Test
    func decidesRunsByToken() {
        let string = "11月3日、GNPとMP3とA4とa、iPhoneと2026年と3.14と10%と11/3と!" as NSString
        let runs = UprightGlyphs.runs(in: string, range: NSRange(location: 0, length: string.length)).map { run in
            string.substring(with: run.range) + (run.kind == .tateChuYoko ? "（縦中横）" : "")
        }
        #expect(runs == ["11（縦中横）", "3", "GNP", "MP3", "A4", "a"])
    }

    @Test
    func replacesFontsWithSquareAdvances() {
        for font in [
            EditorSettings.FontFamily.sansSerif.font(ofSize: 18),
            EditorSettings.FontFamily.serif.font(ofSize: 18),
            EditorSettings.FontFamily.sansSerif.boldFont(ofSize: 18),
        ] {
            func width(_ text: String, _ kind: UprightGlyphs.Kind) -> CGFloat {
                text.size(withAttributes: [.font: UprightGlyphs.font(for: kind, replacing: font), .kern: 0]).width
            }
            #expect(abs(width("W", .upright) - 18) < 0.01)
            #expect(abs(width("a", .upright) - 18) < 0.01)
            #expect(abs(width("12", .tateChuYoko) - 18) < 0.01)
        }
    }

    @Test
    func findsStopsWidenedInVertical() {
        let string = "あ、い。「う」、え。」お，A．" as NSString
        let indices = JapaneseTypesetter.widenedStops(in: string, range: NSRange(location: 0, length: string.length))
        #expect(indices.map { string.substring(with: NSRange(location: $0, length: 2)) } == ["、い", "。「", "、え", "，A"])
    }

    @Test
    func restoresOriginalFontsWhenTurnedHorizontal() async {
        var settings = EditorSettings()
        settings.orientation = .vertical
        let editor = EditorWindowController(text: "GNPと12", settings: settings)
        await settle()
        #expect(attribute(.verticalGlyphForm, at: 0, of: editor) != nil)
        #expect(attribute(.uprightGlyphs, at: 4, of: editor) != nil)
        settings.orientation = .horizontal
        editor.apply(settings)
        for location in [0, 4] {
            let font = settings.fontFamily.font(ofSize: settings.fontSize)
            #expect(attribute(.font, at: location, of: editor) as? NSFont == font)
            #expect(attribute(.uprightGlyphs, at: location, of: editor) == nil)
            #expect(attribute(.verticalGlyphForm, at: location, of: editor) == nil)
        }
    }

    /// 太字の見出しの英数のあとで入力しても、本文の書式に太字が残らない
    @Test
    func typesPlainTextAfterUprightHeading() async throws {
        let editor = await makeEditor("# GNPの話") { $0.highlightsMarkdown = true }
        let storage = try #require(editor.textStorage)
        #expect(attribute(.uprightOriginalFont, at: 2, of: editor) is NSFont)
        let attributes = editor.textView(
            editor.textView,
            shouldChangeTypingAttributes: [:],
            toAttributes: storage.attributes(at: 2, effectiveRange: nil)
        )
        let settings = EditorSettings()
        #expect(attributes[.font] as? NSFont == settings.fontFamily.font(ofSize: settings.fontSize))
        #expect(attributes[.verticalGlyphForm] == nil)
    }

    @Test
    func keepsFirstColumnVisibleWhenWindowNarrows() async throws {
        let editor = await makeEditor(String(repeating: "縦書きの本文です。\n", count: 300))
        let window = try #require(editor.window)
        window.setContentSize(NSSize(width: 800, height: 480))
        let layoutManager = try #require(editor.textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        editor.textView.scrollRangeToVisible(NSRange(location: 0, length: 0))

        window.setContentSize(NSSize(width: 500, height: 480))

        let column = editor.textView.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil)
        #expect(window.convertToScreen(window.contentLayoutRect).contains(column))
    }

    @Test
    func leavesComposingTextUntypesetUntilCommitted() async {
        let editor = await makeEditor("GNP")
        let textView = editor.textView
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("と", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle()

        textView.setMarkedText(
            "k",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        await settle()
        #expect(attribute(.uprightGlyphs, at: 4, of: editor) == nil)
        #expect(attribute(.uprightGlyphs, at: 0, of: editor) != nil)

        textView.insertText("k", replacementRange: textView.markedRange())
        await settle()
        #expect(attribute(.uprightGlyphs, at: 4, of: editor) != nil)
    }

    /// 打鍵のたびに段落を組み直すと、長い文書で入力が遅れる
    @Test
    func doesNotEditAttributesWhenAlreadyTypeset() async throws {
        for orientation in EditorSettings.Orientation.allCases {
            let editor = await makeEditor("11月3日、GNPと書いた。\n本文") { $0.orientation = orientation }
            let storage = try #require(editor.textStorage)
            let observer = EditObserver(storage: storage)
            editor.typesetter.typeset(NSRange(location: 0, length: storage.length))
            #expect(!observer.hasSeenEdit, "\(orientation)")
        }
    }

    /// 英数の部分だけ途切れると、置換した箇所の印が読み取りにくくなる
    @Test
    func underlinesReplacedTextWithoutGaps() async throws {
        let editor = await makeEditor("あGNPと12う")
        let textView = editor.textView
        textView.insertionPointColor = .systemRed
        _ = editor.updateFindMarks(removing: [], results: [], replaced: [NSRange(location: 1, length: 6)])
        let layoutManager = try #require(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let fragment = try #require(layoutManager.textLayoutFragment(for: layoutManager.documentRange.location))

        let image = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 400,
            pixelsHigh: 200,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: image)).cgContext
        context.scaleBy(x: 2, y: 2)
        fragment.draw(at: CGPoint(x: 0, y: 20), in: context)

        #expect(CGFloat(longestRedRun(in: image)) > 5 * EditorSettings().fontSize * 2 * 0.95)
    }

    private func longestRedRun(in image: NSBitmapImageRep) -> Int {
        var longest = 0
        for row in 0 ..< image.pixelsHigh {
            var run = 0
            for column in 0 ..< image.pixelsWide {
                let color = image.colorAt(x: column, y: row)?.usingColorSpace(.sRGB)
                let isRed = color.map { $0.alphaComponent > 0.9 && $0.redComponent > 0.7 && $0.greenComponent < 0.5 }
                run = isRed == true ? run + 1 : 0
                longest = max(longest, run)
            }
        }
        return longest
    }

    @Test
    func centersSelectionOnText() async throws {
        for orientation in [EditorSettings.Orientation.horizontal, .vertical] {
            for fontFamily in [EditorSettings.FontFamily.serif, .sansSerif] {
                let editor = await makeEditor(String(repeating: "目", count: 300) + "\n\n次の段落") {
                    $0.orientation = orientation
                    $0.fontFamily = fontFamily
                    $0.addsParagraphSpacing = false
                }
                try expectBandsCentered(in: editor.textView, isVertical: orientation == .vertical)
            }
        }
    }

    private func expectBandsCentered(in textView: NSTextView, isVertical: Bool) throws {
        let manager = try #require(textView.textLayoutManager)
        let start = manager.documentRange.location
        manager.ensureLayout(for: manager.documentRange)

        var bands: [CGRect] = []
        manager.enumerateTextSegments(in: manager.documentRange, type: .selection) { _, frame, _, _ in
            bands.append(frame)
            return true
        }
        var centers: [CGFloat?] = []
        manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let isEmpty = fragment.textLineFragments[0].characterRange.length <= 1
            for line in fragment.textLineFragments {
                let glyph = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.glyphOrigin.y
                // ヒラギノの全角の字面の中心は、ベースラインから0.38字上にある
                centers.append(isEmpty ? nil : glyph - (isVertical ? 0 : 0.38 * 16))
            }
            return true
        }

        #expect(bands.count == centers.count)
        #expect(bands.count > 3)
        for (band, center) in zip(bands, centers) {
            #expect(band.height == bands[0].height)
            if let center {
                #expect(abs(band.midY - center) <= 0.5)
            }
        }
        // 行間の扱いが違う空の行でも、帯は等間隔に並ぶ
        #expect(Set(zip(bands, bands.dropFirst()).map { $1.minY - $0.minY }).count == 1)
        // テキストビューの外には描けない
        #expect(textView.textContainerOrigin.y + bands[0].minY >= 0)

        // カーソルは1点の範囲で列挙するので、まとめて列挙したときと位置が揃うことを確かめる
        let firstFragment = try #require(manager.textLayoutFragment(for: start))
        let secondLine = firstFragment.textLineFragments[1].characterRange.location
        let location = try #require(manager.textContentManager?.location(start, offsetBy: secondLine))
        var caret: CGRect?
        manager.enumerateTextSegments(in: NSTextRange(location: location), type: .standard) { _, frame, _, _ in
            caret = frame
            return false
        }
        #expect(caret?.minY == bands[1].minY)
    }

    /// 文書の先頭にある結果は動かせないので、パネルのほうが避ける
    @Test
    func uncoversFindResultAtDocumentStart() async {
        let editor = await makeEditor("雨の日\n本文")
        let textView = editor.textView
        let range = NSRange(location: 0, length: 1)
        textView.setSelectedRange(range)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        panel.setFrame(rect.insetBy(dx: -10, dy: -10), display: false)

        editor.showFindResult(range, avoiding: panel)

        #expect(!textView.firstRect(forCharacterRange: range, actualRange: nil).intersects(panel.frame))
    }

    /// パネルは結果の上へ広がっているので、結果を上へ少し動かすだけでは隠れたままになる
    @Test
    func scrollsFindResultAwayFromPanel() async throws {
        let editor = await makeEditor(String(repeating: "本文\n", count: 500)) { $0.orientation = .horizontal }
        let window = try #require(editor.window)
        let textView = editor.textView
        let layoutManager = try #require(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let range = NSRange(location: 3 * 250, length: 1)
        textView.scrollRangeToVisible(range)
        let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let panelFrame = NSRect(x: rect.minX - 10, y: rect.minY - 10, width: rect.width + 20, height: 120)
        panel.setFrame(panelFrame, display: false)

        editor.showFindResult(range, avoiding: panel)

        #expect(panel.frame == panelFrame)
        let moved = textView.firstRect(forCharacterRange: range, actualRange: nil)
        #expect(!moved.intersects(panel.frame))
        #expect(window.convertToScreen(window.contentLayoutRect).contains(moved))
    }
}

private final class EditObserver: NSObject {
    private(set) var hasSeenEdit = false

    init(storage: NSTextStorage) {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didProcessEditing),
            name: NSTextStorage.didProcessEditingNotification,
            object: storage
        )
    }

    @objc private func didProcessEditing() {
        hasSeenEdit = true
    }
}
