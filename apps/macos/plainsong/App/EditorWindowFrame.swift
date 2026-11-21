import AppKit

extension EditorWindowController {
    private static let frameName = "Editor"

    /// 状態を復元するときは、あとから元の位置と大きさになる
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

    /// ウィンドウはいくつも開くので、`frameAutosaveName`は使えない
    private func saveFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.saveFrame(usingName: Self.frameName)
    }
}
