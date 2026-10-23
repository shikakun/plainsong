import AppKit
import Foundation
@testable import Plainsong
import Testing

@Suite
struct ThemeTests {
    /// ユーザーが書いたテーマには、Ghosttyが受け付けるさまざまな書き方がありうる
    @Test
    func readsColorsLikeGhostty() {
        let theme = Theme(ghosttyConfig: """
        # background = #000000
        palette = 0=#111111
          background = 1e1e2e
        foreground = "#abc"
        cursor-color = #ff0000
        cursor-color =
        selection-background = cell-foreground
        selection-foreground = #12345
        """)
        #expect(hex(theme.background) == "1E1E2E")
        #expect(hex(theme.foreground) == "AABBCC")
        #expect(theme.cursor == nil)
        #expect(theme.selectionBackground == nil)
        #expect(theme.selectionForeground == nil)
    }

    @Test
    func bundledThemesHaveAllColors() throws {
        let library = ThemeLibrary()
        #expect(!library.bundledNames.isEmpty)
        for name in library.bundledNames {
            let theme = try #require(library.theme(for: .bundled(name)))
            let colors = [
                theme.background, theme.foreground, theme.cursor,
                theme.selectionBackground, theme.selectionForeground,
            ]
            #expect(colors.allSatisfy { $0 != nil }, "\(name)")
        }
    }

    @Test
    func importsCopiesWithoutOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let library = ThemeLibrary(importedDirectory: directory.appending(path: "Themes"))

        let theme = source.appending(path: "My Theme")
        try "background = #000000\n".write(to: theme, atomically: true, encoding: .utf8)
        #expect(try library.importTheme(from: theme) == "My Theme")
        try "background = #ffffff\n".write(to: theme, atomically: true, encoding: .utf8)
        #expect(try library.importTheme(from: theme) == "My Theme 2")
        #expect(hex(library.theme(for: .imported("My Theme"))?.background) == "000000")

        let notTheme = source.appending(path: "notes.txt")
        try "font-size = 14\n".write(to: notTheme, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try library.importTheme(from: notTheme) }
        #expect(library.importedNames == ["My Theme", "My Theme 2"])
    }

    private func hex(_ color: NSColor?) -> String? {
        guard let color = color?.usingColorSpace(.sRGB) else { return nil }
        return [color.redComponent, color.greenComponent, color.blueComponent]
            .map { String(format: "%02X", Int(($0 * 255).rounded())) }
            .joined()
    }
}
