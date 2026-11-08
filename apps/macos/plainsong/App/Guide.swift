import AppKit

extension EditorSettings {
    enum Guide: String, CaseIterable {
        case blank
        case ruledLines
        case manuscriptPaper

        var title: String {
            switch self {
            case .blank: String(localized: "settings.guide.blank")
            case .ruledLines: String(localized: "settings.guide.ruledLines")
            case .manuscriptPaper: String(localized: "settings.guide.manuscriptPaper")
            }
        }
    }

    var showsManuscriptGuide: Bool {
        guide == .manuscriptPaper
    }

    /// 原稿用紙のマスと罫線は一定の行送りに揃えるので、段落の間隔を空けない
    var usesParagraphSpacing: Bool {
        addsParagraphSpacing && guide == .blank
    }

    /// 原稿用紙では字をマスに揃えるので、カーニングを切り替えられない
    func allowsToggling(_ keyPath: KeyPath<EditorSettings, Bool>) -> Bool {
        keyPath != \.usesKerning || !showsManuscriptGuide
    }
}

class GuideLineView: NSView {
    let textView: NSTextView

    var color = NSColor.labelColor {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    private var lineColor: NSColor {
        color.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.55 : 0.18)
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        if let clipView = textView.enclosingScrollView?.contentView {
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(redraw(_:)),
                    name: name,
                    object: clipView
                )
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(redraw(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    @objc func redraw(_: Notification) {
        needsDisplay = true
    }

    /// テキストビューの座標で返す。縦書きでは右の列からの距離になる
    var firstLineMiddle: CGFloat? {
        textView.textLayoutManager?.firstLineMiddle.map { $0 + textView.textContainerOrigin.y }
    }

    func snapped(_ position: CGFloat, _ edge: CGFloat) -> CGPoint {
        let scale = window?.backingScaleFactor ?? 1
        let point = convert(CGPoint(x: position, y: edge), from: textView)
        return CGPoint(
            x: ((point.x * scale).rounded(.down) + 0.5) / scale,
            y: ((point.y * scale).rounded(.down) + 0.5) / scale
        )
    }

    func stroke(_ path: NSBezierPath) {
        path.lineWidth = 1 / (window?.backingScaleFactor ?? 1)
        lineColor.setStroke()
        path.stroke()
    }
}

extension NSTextLayoutManager {
    /// 空の文書にはレイアウトフラグメントがないので、カーソルの位置から求める
    var firstLineMiddle: CGFloat? {
        guard let start = textContentManager?.documentRange.location,
              let range = NSTextRange(location: start, end: start)
        else { return nil }
        var first: CGFloat?
        enumerateTextSegments(in: range, type: .standard) { _, frame, _, _ in
            first = frame.midY
            return false
        }
        return first
    }
}

extension EditorWindowController {
    func addGuideView(_ view: GuideLineView) {
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view, positioned: .above, relativeTo: scrollView)
    }
}

final class GuideOptions: NSObject {
    private let model: SettingsModel
    private let button = NSPopUpButton()

    init(model: SettingsModel) {
        self.model = model
        super.init()
        button.addItems(for: EditorSettings.Guide.self, title: \.title)
        button.target = self
        button.action = #selector(change(_:))
    }

    func makeSection() -> NSGridView {
        let guide = String(localized: "settings.guide")
        button.setAccessibilityLabel(guide)
        return SettingsPane.columns([[SettingsPane.label(guide), button]])
    }

    func update(with settings: EditorSettings) {
        button.selectItem(for: settings.guide)
    }

    @objc private func change(_ sender: NSPopUpButton) {
        guard let guide = sender.selectedCase(of: EditorSettings.Guide.self) else { return }
        model.update { $0.guide = guide }
    }
}
