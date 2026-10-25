@testable import Plainsong
import Testing

@Suite
struct ExtensionItemTests {
    @Test
    func usesDefaultOrderWithoutSavedOrder() {
        #expect(ExtensionItem<ToolbarItemKind>.order(saved: []) == ToolbarItemKind.allCases)
    }

    @Test
    func keepsSavedOrder() {
        let saved: [ToolbarItemKind] = [.delete, .share, .save, .find, .copy]
        #expect(ExtensionItem<ToolbarItemKind>.order(saved: saved) == saved)
    }

    @Test
    func insertsNewKindAfterItsPredecessor() {
        let order = ExtensionItem<ToolbarItemKind>.order(saved: [.delete, .copy, .save, .share])
        #expect(order == [.delete, .copy, .find, .save, .share])
    }

    @Test
    func insertsNewFirstKindAtTop() {
        let order = ExtensionItem<ToolbarItemKind>.order(saved: [.share, .find, .save, .delete])
        #expect(order == [.copy, .share, .find, .save, .delete])
    }
}
