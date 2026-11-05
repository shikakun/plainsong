@testable import Plainsong
import Testing

@Suite
struct ExtensionItemTests {
    @Test
    func insertsNewKindsIntoSavedOrder() {
        #expect(ExtensionItem<ToolbarItemKind>.order(saved: [.delete, .copy, .save, .share])
            == [.delete, .copy, .find, .save, .share])
        #expect(ExtensionItem<ToolbarItemKind>.order(saved: [.share, .find, .save, .delete])
            == [.copy, .share, .find, .save, .delete])
    }
}
