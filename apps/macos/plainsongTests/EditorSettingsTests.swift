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
    func decidesManuscriptCellsFromReadableWidthAndWindow() {
        var settings = EditorSettings()
        settings.showsManuscriptGuide = true
        settings.fontSize = 16
        #expect(settings.manuscriptCells(clipLength: 500, minimumLeading: 32, minimumTrailing: 32) == 27)
        #expect(settings.lineInsets(clipLength: 500, minimumLeading: 32, minimumTrailing: 32) == (32, 36))

        settings.usesReadableWidth = true
        settings.readableWidth = .japaneseShort
        #expect(settings.manuscriptCells(clipLength: 500, minimumLeading: 32, minimumTrailing: 32) == 20)
        #expect(settings.lineInsets(clipLength: 500, minimumLeading: 32, minimumTrailing: 32) == (90, 90))
        #expect(settings.manuscriptCells(clipLength: 200, minimumLeading: 32, minimumTrailing: 32) == 8)
        #expect(settings.manuscriptCells(clipLength: 50, minimumLeading: 32, minimumTrailing: 32) == 1)
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
