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
