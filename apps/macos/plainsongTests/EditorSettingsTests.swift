import Foundation
@testable import Plainsong
import Testing

@Suite
struct EditorSettingsTests {
    @Test
    func centersReadableWidth() {
        var settings = EditorSettings()
        settings.usesReadableWidth = true
        settings.readableWidth = .japanese
        let insets = settings.lineInsets(clipLength: 1000, minimumLeading: 60, minimumTrailing: 40)
        #expect(insets == (180, 180))
        #expect(settings.crossInsetExpansion(trailing: insets.trailing, minimumTrailing: 40) == 64)
    }

    @Test
    func keepsMinimumLeadingWhenCenteringDoesNotFit() {
        var settings = EditorSettings()
        settings.usesReadableWidth = true
        settings.readableWidth = .japanese
        let narrow = settings.lineInsets(clipLength: 600, minimumLeading: 80, minimumTrailing: 40)
        #expect(narrow == (80, 40))
        let tall = settings.lineInsets(clipLength: 800, minimumLeading: 40, minimumTrailing: 100)
        #expect(tall == (40, 120))
    }
}
