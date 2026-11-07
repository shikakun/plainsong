import AppKit

extension EditorWindowController {
    private static let frameName = "Editor"

    /// ほかのウィンドウが出ていれば、少しずらして重ねる。状態を復元するときは、あとから元の位置と大きさになる
    /// 大きさは、最後に大きさを変えたか閉じたウィンドウに合わせる。残した位置は使わない
    func place() {
        guard let window else { return }
        window.setFrameUsingName(Self.frameName)
        let front = NSApp.orderedWindows.first { $0.isVisible && $0.windowController is EditorWindowController }
        guard let front else {
            window.center()
            return
        }
        window.cascadeTopLeft(from: front.cascadeTopLeft(from: .zero))
    }

    /// 原稿用紙のマスが見切れないよう、行の方向の長さを保つ。今のウィンドウが足りなければ、左上を保って広げる
    func keepContentLength(_ length: CGFloat?, isVertical: Bool) {
        guard let window else { return }
        let minimum = length.map { isVertical ? NSSize(width: 1, height: $0) : NSSize(width: $0, height: 1) }
            ?? NSSize(width: 1, height: 1)
        guard window.contentMinSize != minimum else { return }
        window.contentMinSize = minimum
        guard !window.styleMask.contains(.fullScreen),
              let content = window.contentView?.frame.size,
              content.width < minimum.width || content.height < minimum.height
        else { return }
        var frame = window.frame
        let height = max(minimum.height - content.height, 0)
        frame.origin.y -= height
        frame.size.height += height
        frame.size.width += max(minimum.width - content.width, 0)
        window.setFrame(frame, display: true)
    }

    func windowDidEndLiveResize(_: Notification) {
        saveFrame()
    }

    func windowWillClose(_: Notification) {
        saveFrame()
    }

    /// ウィンドウはいくつも開くので、`frameAutosaveName`は使えない。全画面のあいだは画面の大きさになっているので残さない
    private func saveFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.saveFrame(usingName: Self.frameName)
    }
}
