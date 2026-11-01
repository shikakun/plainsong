import AppKit
import UniformTypeIdentifiers

extension NSAttributedString.Key {
    nonisolated static let markdownStyle = NSAttributedString.Key("PlainsongMarkdownStyle")
}

extension MarkdownSyntax.Flavor {
    private static let mdxType = UTType(importedAs: "com.shikakun.plainsong.mdx")

    /// 保存パネルで拡張子を打ち替えても`fileType`は変わらないので、拡張子で決める
    init(url: URL?) {
        let type = url.flatMap { UTType(filenameExtension: $0.pathExtension) }
        self = type?.conforms(to: Self.mdxType) == true ? .mdx : .markdown
    }
}

final class MarkdownHighlighter {
    struct Appearance {
        var font: NSFont
        var boldFont: NSFont
        var codeFont: NSFont
        var textColor: NSColor
        var markerColor: NSColor
        var codeColor: NSColor

        init(settings: EditorSettings, theme: Theme?) {
            font = settings.fontFamily.font(ofSize: settings.fontSize)
            boldFont = settings.fontFamily.boldFont(ofSize: settings.fontSize)
            codeFont = EditorSettings.FontFamily.monospacedFont(ofSize: settings.fontSize)
            textColor = theme?.foreground ?? .textColor
            markerColor = .secondaryLabelColor
            codeColor = theme?.palette[2] ?? .code
        }

        var plainAttributes: [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: textColor]
        }
    }

    static let styledKeys: Set<NSAttributedString.Key> = [.font, .foregroundColor]

    private weak var textView: NSTextView?
    private(set) var flavor: MarkdownSyntax.Flavor?
    private var appearance: Appearance?
    private var blocks: [MarkdownSyntax.Block] = []
    private var pendingRange: NSRange?
    private var pendingTask: Task<Void, Never>?
    private var editingObservation: (any NSObjectProtocol)?

    init(textView: NSTextView) {
        self.textView = textView
        // 本文はメインスレッドでしか変えないので、通知もメインスレッドで届く
        editingObservation = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.storageDidProcessEditing() }
        }
    }

    func update(flavor: MarkdownSyntax.Flavor?, appearance: Appearance) {
        let flavorChanged = flavor != self.flavor
        self.flavor = flavor
        self.appearance = appearance
        guard let storage = textView?.textStorage else { return }
        if flavor == nil {
            if flavorChanged {
                clear(storage)
            }
        } else if flavorChanged {
            blocks = MarkdownSyntax.blocks(in: storage.string as NSString)
            highlight(NSRange(location: 0, length: storage.length), in: storage)
        } else {
            render(storage)
        }
    }

    func plainAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        guard attributes[.markdownStyle] != nil, let appearance else { return attributes }
        var attributes = attributes
        attributes[.markdownStyle] = nil
        attributes.merge(appearance.plainAttributes) { $1 }
        return attributes
    }

    private func storageDidProcessEditing() {
        guard flavor != nil, let storage = textView?.textStorage, storage.editedMask.contains(.editedCharacters)
        else { return }
        let edited = storage.editedRange
        let delta = storage.changeInLength
        blocks = blocks.map { block in
            var block = block
            block.range = Self.range(block.range, adjustedFor: edited, delta: delta)
            return block
        }
        pendingRange = pendingRange.map { NSUnionRange(Self.range($0, adjustedFor: edited, delta: delta), edited) }
            ?? edited
        pendingTask = pendingTask ?? Task { [weak self] in
            self?.highlightPending()
        }
    }

    private func highlightPending() {
        pendingTask = nil
        guard flavor != nil, let pendingRange, let storage = textView?.textStorage else { return }
        self.pendingRange = nil
        let string = storage.string as NSString
        let newBlocks = MarkdownSyntax.blocks(in: string)
        var range = pendingRange
        for block in Set(blocks).symmetricDifference(newBlocks) {
            range = NSUnionRange(range, block.range)
        }
        blocks = newBlocks
        highlight(NSIntersectionRange(range, NSRange(location: 0, length: storage.length)), in: storage)
    }

    private func highlight(_ range: NSRange, in storage: NSTextStorage) {
        guard let flavor, let appearance else { return }
        let string = storage.string as NSString
        let range = string.lineRange(for: range)
        let runs = MarkdownSyntax.runs(in: range, of: string, blocks: blocks, flavor: flavor)
        storage.beginEditing()
        storage.removeAttribute(.markdownStyle, range: range)
        storage.addAttributes(appearance.plainAttributes, range: range)
        for run in runs {
            storage.addAttribute(.markdownStyle, value: run.style.rawValue, range: run.range)
            render(run.style, in: run.range, of: storage, appearance: appearance)
        }
        storage.endEditing()
    }

    private func render(_ storage: NSTextStorage) {
        guard let appearance else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.enumerateAttribute(.markdownStyle, in: whole) { value, range, _ in
            guard let value = value as? Int else { return }
            render(MarkdownSyntax.Style(rawValue: value), in: range, of: storage, appearance: appearance)
        }
        storage.endEditing()
    }

    private func render(
        _ style: MarkdownSyntax.Style,
        in range: NSRange,
        of storage: NSTextStorage,
        appearance: Appearance
    ) {
        let color = if style.contains(.marker) {
            appearance.markerColor
        } else if style.contains(.code) {
            appearance.codeColor
        } else {
            appearance.textColor
        }
        let font = if !style.isDisjoint(with: [.code, .monospaced]) {
            appearance.codeFont
        } else if style.contains(.bold) {
            appearance.boldFont
        } else {
            appearance.font
        }
        storage.addAttributes([.font: font, .foregroundColor: color], range: range)
    }

    private func clear(_ storage: NSTextStorage) {
        blocks = []
        pendingRange = nil
        guard let appearance else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.enumerateAttribute(.markdownStyle, in: whole) { value, range, _ in
            guard value != nil else { return }
            storage.addAttributes(appearance.plainAttributes, range: range)
        }
        storage.removeAttribute(.markdownStyle, range: whole)
        storage.endEditing()
    }

    static func range(_ range: NSRange, adjustedFor edited: NSRange, delta: Int) -> NSRange {
        let replacedEnd = NSMaxRange(edited) - delta
        func adjust(_ location: Int, toward bound: Int) -> Int {
            if location <= edited.location {
                location
            } else if location >= replacedEnd {
                location + delta
            } else {
                bound
            }
        }
        let start = adjust(range.location, toward: edited.location)
        let end = adjust(NSMaxRange(range), toward: NSMaxRange(edited))
        return NSRange(start ..< max(start, end))
    }
}

private nonisolated extension NSColor {
    static var code: NSColor {
        NSColor(name: nil) { appearance in
            var green = NSColor.systemGreen
            appearance.performAsCurrentDrawingAppearance {
                green = green.usingColorSpace(.sRGB) ?? green
            }
            guard appearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua else { return green }
            return green.blended(withFraction: 0.4, of: .black) ?? green
        }
    }
}
