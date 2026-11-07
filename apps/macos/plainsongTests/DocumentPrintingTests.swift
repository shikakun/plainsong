import AppKit
import PDFKit
@testable import Plainsong
import Testing

@Suite
struct DocumentPrintingTests {
    private func printInfo(paperSize: NSSize) -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = paperSize
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        return info
    }

    private func operation(
        _ text: String,
        orientation: EditorSettings.Orientation = .horizontal,
        showsManuscriptGuide: Bool = false,
        configure: (DocumentPrintView) -> Void = { _ in }
    ) throws -> NSPrintOperation {
        var settings = EditorSettings()
        settings.orientation = orientation
        settings.showsManuscriptGuide = showsManuscriptGuide
        let operation = DocumentPrintView.operation(
            text: text,
            settings: settings,
            printInfo: printInfo(paperSize: NSSize(width: 595.28, height: 841.89))
        )
        try configure(#require(operation.view as? DocumentPrintView))
        return operation
    }

    private func pdf(printedBy operation: NSPrintOperation) throws -> PDFDocument {
        let key = NSPrintInfo.AttributeKey.jobSavingURL
        let url = try #require(operation.printInfo.dictionary()[key] as? URL)
        defer { try? FileManager.default.removeItem(at: url) }
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        return try #require(PDFDocument(data: Data(contentsOf: url)))
    }

    private func pages(printedBy operation: NSPrintOperation) throws -> [String] {
        let document = try pdf(printedBy: operation)
        return (0 ..< document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }

    private func firstPagePixels(printedBy operation: NSPrintOperation) throws -> [UInt8] {
        let page = try #require(pdf(printedBy: operation).page(at: 0))
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
        return Array(UnsafeRawBufferPointer(start: data, count: width * context.height))
    }

    private func manuscriptBodyPixels(
        _ text: String,
        orientation: EditorSettings.Orientation
    ) throws -> [UInt8] {
        try firstPagePixels(printedBy: operation(text, orientation: orientation, showsManuscriptGuide: true) {
            $0.showsManuscriptGrid = false
            $0.showsPageNumbers = false
        })
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func printsEveryLineOnceAcrossPages(orientation: EditorSettings.Orientation) throws {
        let text = String(repeating: "印あいうえ12月かきくけ", count: 400)
        let printed = try pages(printedBy: operation(text, orientation: orientation))
        #expect(printed.count > 1)
        #expect(printed.joined().count { $0 == "印" } == 400)
    }

    @Test
    func repaginatesTheSameViewForPaperSize() throws {
        let a4Operation = try operation(String(repeating: "印あいうえおかきくけ", count: 400))
        let a4 = try pages(printedBy: a4Operation)
        let view = try #require(a4Operation.view)

        let a5Info = printInfo(paperSize: NSSize(width: 419.53, height: 595.28))
        let a5 = try pages(printedBy: NSPrintOperation(view: view, printInfo: a5Info))

        #expect(a5.count > a4.count)
        #expect(a5.joined().count { $0 == "印" } == 400)
    }

    @Test
    func printsPageNumbersOnlyWhenEnabled() throws {
        let text = String(repeating: "あ\n", count: 200)
        let numbered = try pages(printedBy: operation(text) { $0.showsPageNumbers = true })
        #expect(numbered.count > 1)
        for (index, page) in numbered.enumerated() {
            #expect(page.contains(String(index + 1)))
        }

        let plain = try pages(printedBy: operation(text))
        #expect(plain.joined().allSatisfy { !$0.isNumber })
    }

    /// 高さが0だと、プリントパネルの中でチェックボックスが枠からはみ出す
    @Test
    func givesPrintPanelOptionsAFrame() throws {
        let options = try #require(operation("あ").printPanel.accessoryControllers.first)
        #expect(options.view.frame.height > 0)
    }

    /// 空行も1行に数え、末尾の改行のあとの空の行は数えない。枚数の表示と食い違わないよう、計算した行で組む
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func printsTwentyLinesPerManuscriptPage(orientation: EditorSettings.Orientation) throws {
        let wrapped = String(repeating: "印あいうえおかきくけこさしすせそたちつてと。「はい」12月とiPhone——", count: 40)
        for (text, pageCount) in [
            (String(repeating: "印\n", count: 20), 1),
            (String(repeating: "印\n", count: 21), 2),
            (String(repeating: "\n", count: 40) + "印", 3),
            ("", 1),
            (wrapped, ManuscriptPaper.pages(forLines: ManuscriptPaper().count(in: wrapped as NSString))),
        ] {
            let printed = try pages(
                printedBy: operation(text, orientation: orientation, showsManuscriptGuide: true)
            )
            #expect(printed.count == pageCount, "\(text.debugDescription)")
            #expect(printed.joined().count { $0 == "印" } == text.count { $0 == "印" })
        }
    }

    @Test
    func printsManuscriptGridOnlyWhenEnabled() throws {
        let withGrid = try firstPagePixels(printedBy: operation("", orientation: .vertical, showsManuscriptGuide: true))
        #expect(withGrid.count { $0 < 250 } > 1000)

        let withoutGrid = try manuscriptBodyPixels("", orientation: .vertical)
        #expect(withoutGrid.count { $0 < 250 } == 0)
    }

    /// 縦中横は回転させて描くので、位置を誤ると字が欠ける。横書きと同じ字形なので、同じくらいのインクになる
    @Test
    func printsTwoDigitsInACellAsInHorizontalText() throws {
        let vertical = try manuscriptBodyPixels("12", orientation: .vertical).count { $0 < 250 }
        let horizontal = try manuscriptBodyPixels("12", orientation: .horizontal).count { $0 < 250 }
        #expect(horizontal > 0)
        #expect(abs(vertical - horizontal) * 4 < horizontal, "\(vertical), \(horizontal)")
    }

    /// 字間を指定して組むとフォントの文字ペアの詰めが効き、モチベーションのーなどから後ろがマスからずれる
    /// 空白のあとの国と、詰めが効く文字のあとの国は同じマスにあるので、同じ画素になる
    @Test
    func printsCharactersInTheirCellsAfterKerningPairs() throws {
        let alone = try manuscriptBodyPixels(String(repeating: "　", count: 8) + "国", orientation: .vertical)
        let afterPairs = try manuscriptBodyPixels("モチベーションで国", orientation: .vertical)
        let ink = alone.indices.filter { alone[$0] < 128 }
        #expect(ink.count > 10)
        let differing = ink.count { afterPairs[$0] >= 128 }
        #expect(differing * 20 < ink.count, "\(differing) / \(ink.count)")
    }
}
