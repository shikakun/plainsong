import Foundation
@testable import Plainsong
import Testing

@Suite
struct EditorSettingsTests {
    @Test
    func hidesLineNumbersAndMarkersInVerticalOrientation() {
        var settings = EditorSettings()
        settings.showsNewlines = true
        settings.showsWhitespace = true
        settings.showsLineNumbers = true
        #expect(settings.displaysNewlines && settings.displaysWhitespace && settings.displaysLineNumbers)

        settings.orientation = .vertical
        #expect(!settings.displaysNewlines && !settings.displaysWhitespace && !settings.displaysLineNumbers)
        #expect(!settings.isAvailable(\.showsLineNumbers))
        #expect(settings.isAvailable(\.usesKerning))
        // 設定の値は残す
        #expect(settings.showsNewlines && settings.showsWhitespace && settings.showsLineNumbers)
    }

    @Test
    func usesMinimumLineInsetsWithoutReadableWidth() {
        let settings = EditorSettings()
        let insets = settings.lineInsets(clipLength: 2000, minimumLeading: 60, minimumTrailing: 40)
        #expect(insets == (60, 40))
    }

    @Test
    func centersReadableWidth() {
        var settings = EditorSettings()
        settings.usesReadableWidth = true
        settings.readableWidth = .japanese
        // 16pt × 40字 = 640pt
        let insets = settings.lineInsets(clipLength: 1000, minimumLeading: 60, minimumTrailing: 40)
        #expect(insets == (180, 180))
        #expect(settings.crossInsetExpansion(trailing: insets.trailing, minimumTrailing: 40) == 64)
    }

    @Test
    func keepsMinimumLeadingWhenCenteringDoesNotFit() {
        var settings = EditorSettings()
        settings.usesReadableWidth = true
        settings.readableWidth = .japanese
        let insets = settings.lineInsets(clipLength: 760, minimumLeading: 80, minimumTrailing: 40)
        #expect(insets == (80, 40))
        let narrow = settings.lineInsets(clipLength: 600, minimumLeading: 80, minimumTrailing: 40)
        #expect(narrow == (80, 40))
        // 終わりの最小の余白が始めより大きくても、両方の最小の余白を守る
        let tall = settings.lineInsets(clipLength: 800, minimumLeading: 40, minimumTrailing: 100)
        #expect(tall == (40, 120))
    }
}
