import AppKit
import PDFKit
@testable import Plainsong
import Testing

@Suite
struct DocumentPrintingTests {
    private static let a4 = NSSize(width: 595.28, height: 841.89)
    private static let a5 = NSSize(width: 419.53, height: 595.28)

    private func printInfo(paperSize: NSSize, savingTo url: URL) -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = paperSize
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        return info
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    }

    private func pages(printedBy operation: NSPrintOperation, to url: URL) throws -> [String] {
        defer { try? FileManager.default.removeItem(at: url) }
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        let document = try #require(PDFDocument(url: url))
        return (0 ..< document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }

    private func operation(
        _ text: String,
        orientation: EditorSettings.Orientation,
        showsManuscriptGuide: Bool = false,
        savingTo url: URL
    ) -> NSPrintOperation {
        var settings = EditorSettings()
        settings.orientation = orientation
        settings.showsManuscriptGuide = showsManuscriptGuide
        return DocumentPrintView.operation(
            text: text,
            settings: settings,
            printInfo: printInfo(paperSize: Self.a4, savingTo: url)
        )
    }

    /// 1つの段落がページをまたいでも、どの文字も欠けず、重複して描かれないことを確かめる
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func printsEveryLineOnceAcrossPages(orientation: EditorSettings.Orientation) throws {
        let url = temporaryURL()
        let text = String(repeating: "印あいうえ12月かきくけ", count: 400)
        let printed = try pages(printedBy: operation(text, orientation: orientation, savingTo: url), to: url)
        #expect(printed.count > 1)
        #expect(printed.joined().count { $0 == "印" } == 400)
    }

    /// プリントパネルで用紙を変えると、同じビューを組み直す
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func repaginatesTheSameViewForPaperSize(orientation: EditorSettings.Orientation) throws {
        let text = String(repeating: "印あいうえおかきくけ", count: 400)
        let a4URL = temporaryURL()
        let a4Operation = operation(text, orientation: orientation, savingTo: a4URL)
        let a4 = try pages(printedBy: a4Operation, to: a4URL)
        let view = try #require(a4Operation.view)

        let a5URL = temporaryURL()
        let a5Info = printInfo(paperSize: Self.a5, savingTo: a5URL)
        a5Info.orientation = orientation == .vertical ? .landscape : .portrait
        let a5 = try pages(printedBy: NSPrintOperation(view: view, printInfo: a5Info), to: a5URL)

        #expect(a5.count > a4.count)
        #expect(a5.joined().count { $0 == "印" } == 400)
    }

    @Test
    func printsPageNumbersOnlyWhenEnabled() throws {
        let text = String(repeating: "あ\n", count: 200)
        let numberedURL = temporaryURL()
        let numberedOperation = operation(text, orientation: .horizontal, savingTo: numberedURL)
        (numberedOperation.view as? DocumentPrintView)?.showsPageNumbers = true
        let numbered = try pages(printedBy: numberedOperation, to: numberedURL)
        #expect(numbered.count > 1)
        for (index, page) in numbered.enumerated() {
            #expect(page.contains(String(index + 1)))
        }

        let plainURL = temporaryURL()
        let plain = try pages(printedBy: operation(text, orientation: .horizontal, savingTo: plainURL), to: plainURL)
        #expect(plain.joined().allSatisfy { !$0.isNumber })
    }

    /// 高さが0だと、プリントパネルの中でチェックボックスが枠からはみ出す
    @Test
    func givesPrintPanelOptionsAFrame() throws {
        let printOperation = operation("あ", orientation: .horizontal, savingTo: temporaryURL())
        let options = try #require(printOperation.printPanel.accessoryControllers.first)
        #expect(options.view.frame.height > 0)
        #expect(options.view.frame.width > 0)
    }

    /// 空行も1行に数え、末尾の改行のあとの空の行は数えない
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func printsTwentyLinesPerManuscriptPage(orientation: EditorSettings.Orientation) throws {
        for (text, pageCount) in [
            (String(repeating: "印\n", count: 20), 1),
            (String(repeating: "印\n", count: 21), 2),
            (String(repeating: "\n", count: 40) + "印", 3),
            ("", 1),
        ] {
            let url = temporaryURL()
            let printed = try pages(
                printedBy: operation(text, orientation: orientation, showsManuscriptGuide: true, savingTo: url),
                to: url
            )
            #expect(printed.count == pageCount, "\(text.debugDescription)")
            #expect(printed.joined().count { $0 == "印" } == text.count { $0 == "印" })
        }
    }

    /// 枚数の表示と印刷の枚数が食い違わないよう、計算した行で組むことを確かめる
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func printsManuscriptWithThePageCountOfThePaper(orientation: EditorSettings.Orientation) throws {
        let text = String(repeating: "印あいうえおかきくけこさしすせそたちつてと。「はい」12月とiPhone——", count: 40)
        let url = temporaryURL()
        let printed = try pages(
            printedBy: operation(text, orientation: orientation, showsManuscriptGuide: true, savingTo: url),
            to: url
        )
        let lines = ManuscriptPaper().count(in: text as NSString)
        #expect(printed.count == ManuscriptPaper.pages(forLines: lines))
        #expect(printed.joined().count { $0 == "印" } == 40)
    }

    /// ページの1ページ目を画素にする。画素は左上から行ごとに並ぶ
    private func renderedPixels(
        printedBy operation: NSPrintOperation,
        to url: URL
    ) throws -> (pixels: [UInt8], width: Int) {
        defer { try? FileManager.default.removeItem(at: url) }
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        let page = try #require(PDFDocument(url: url)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width)
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: Int(bounds.height),
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: bounds.size))
        page.draw(with: .mediaBox, to: context)
        let data = try #require(context.data)
        let buffer = UnsafeRawBufferPointer(start: data, count: width * context.height)
        return (Array(buffer), width)
    }

    private func inkedPixels(printedBy operation: NSPrintOperation, to url: URL) throws -> Int {
        try renderedPixels(printedBy: operation, to: url).pixels.count { $0 < 250 }
    }

    /// 本文がなくてもマス目は印刷し、選択を外せば消える
    @Test
    func printsManuscriptGridOnlyWhenEnabled() throws {
        let withGridURL = temporaryURL()
        let withGrid = operation("", orientation: .vertical, showsManuscriptGuide: true, savingTo: withGridURL)
        #expect(try inkedPixels(printedBy: withGrid, to: withGridURL) > 1000)

        let withoutGridURL = temporaryURL()
        let withoutGrid = operation("", orientation: .vertical, showsManuscriptGuide: true, savingTo: withoutGridURL)
        let view = try #require(withoutGrid.view as? DocumentPrintView)
        view.showsManuscriptGrid = false
        view.showsPageNumbers = false
        #expect(try inkedPixels(printedBy: withoutGrid, to: withoutGridURL) == 0)
    }

    /// 縦中横は回転させて描くので、位置を誤ると字が欠ける。横書きと同じ字形なので、同じくらいのインクになる
    @Test
    func printsTwoDigitsInACellAsInHorizontalText() throws {
        func ink(_ orientation: EditorSettings.Orientation) throws -> Int {
            let url = temporaryURL()
            let printOperation = operation("12", orientation: orientation, showsManuscriptGuide: true, savingTo: url)
            let view = try #require(printOperation.view as? DocumentPrintView)
            view.showsManuscriptGrid = false
            view.showsPageNumbers = false
            return try inkedPixels(printedBy: printOperation, to: url)
        }
        let vertical = try ink(.vertical)
        let horizontal = try ink(.horizontal)
        #expect(horizontal > 0)
        #expect(abs(vertical - horizontal) * 4 < horizontal, "\(vertical), \(horizontal)")
    }

    /// 字間を指定して組むとフォントの文字ペアの詰めが効き、モチベーションのーなどから後ろがマスからずれる
    /// 空白のあとの国と、詰めが効く文字のあとの国は同じマスにあるので、同じ画素になる
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func printsCharactersInTheirCellsAfterKerningPairs(orientation: EditorSettings.Orientation) throws {
        func rendered(_ text: String) throws -> (pixels: [UInt8], width: Int) {
            let url = temporaryURL()
            let printOperation = operation(text, orientation: orientation, showsManuscriptGuide: true, savingTo: url)
            let view = try #require(printOperation.view as? DocumentPrintView)
            view.showsManuscriptGrid = false
            view.showsPageNumbers = false
            return try renderedPixels(printedBy: printOperation, to: url)
        }
        let alone = try rendered(String(repeating: "　", count: 8) + "国")
        let afterPairs = try rendered("モチベーションで国")
        let ink = alone.pixels.indices.filter { alone.pixels[$0] < 128 }
        #expect(ink.count > 10)
        let differing = ink.count { afterPairs.pixels[$0] >= 128 }
        #expect(differing * 20 < ink.count, "\(differing) / \(ink.count)")
    }
}
