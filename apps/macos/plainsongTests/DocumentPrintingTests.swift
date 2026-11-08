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
        guide: EditorSettings.Guide = .blank,
        paperSize: NSSize = NSSize(width: 595.28, height: 841.89),
        configure: (DocumentPrintView) -> Void = { _ in }
    ) throws -> NSPrintOperation {
        var settings = EditorSettings()
        settings.orientation = orientation
        settings.guide = guide
        let operation = DocumentPrintView.operation(
            text: text,
            settings: settings,
            printInfo: printInfo(paperSize: paperSize)
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

    private func firstPageBitmap(printedBy operation: NSPrintOperation) throws -> (pixels: [UInt8], width: Int) {
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
        return (Array(UnsafeRawBufferPointer(start: data, count: width * context.height)), width)
    }

    private func manuscriptBody(
        _ text: String,
        orientation: EditorSettings.Orientation
    ) throws -> (pixels: [UInt8], width: Int) {
        try firstPageBitmap(printedBy: operation(text, orientation: orientation, guide: .manuscriptPaper) {
            $0.showsGuide = false
            $0.showsPageNumbers = false
        })
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func printsEveryLineOnceAcrossPages(orientation: EditorSettings.Orientation) throws {
        let text = String(repeating: "印あいうえ12月かきくけ", count: 400)
        let printed = try pages(printedBy: operation(text, orientation: orientation))
        #expect(printed.count > 1)
        #expect(printed.joined().count { $0 == "印" } == 400)
        #expect(printed.joined().count { $0 == "1" } == 400)
    }

    @Test
    func ignoresTheEmptyLineAfterATrailingNewline() throws {
        let paperSize = NSSize(width: 300, height: 300)
        for lines in 1 ... 12 {
            let text = Array(repeating: "あ", count: lines).joined(separator: "\n")
            let withoutNewline = try pages(printedBy: operation(text, paperSize: paperSize))
            let withNewline = try pages(printedBy: operation(text + "\n", paperSize: paperSize))
            #expect(withNewline.count == withoutNewline.count, "\(lines)")
        }
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
    @Test
    func printsTwentyLinesPerManuscriptPage() throws {
        let wrapped = String(repeating: "印あいうえおかきくけこさしすせそたちつてと。「はい」12月とiPhone——", count: 40)
        for (text, pageCount) in [
            (String(repeating: "印\n", count: 20), 1),
            (String(repeating: "印\n", count: 21), 2),
            (String(repeating: "\n", count: 40) + "印", 3),
            ("", 1),
            (wrapped, ManuscriptPaper.pages(forLines: ManuscriptPaper().count(in: wrapped as NSString))),
        ] {
            let printed = try pages(printedBy: operation(text, guide: .manuscriptPaper))
            #expect(printed.count == pageCount, "\(text.debugDescription)")
            #expect(printed.joined().count { $0 == "印" } == text.count { $0 == "印" })
        }
    }

    @Test(arguments: EditorSettings.Guide.allCases)
    func printsGuideOnlyWhenEnabled(guide: EditorSettings.Guide) throws {
        func ink(showsGuide: Bool) throws -> Int {
            try firstPageBitmap(printedBy: operation("", orientation: .vertical, guide: guide) {
                $0.showsGuide = showsGuide
                $0.showsPageNumbers = false
            }).pixels.count { $0 < 250 }
        }
        if guide == .blank {
            #expect(try ink(showsGuide: true) == 0)
        } else {
            #expect(try ink(showsGuide: true) > 1000)
            #expect(try ink(showsGuide: false) == 0)
        }
    }

    /// 用紙の幅の半分を超えて線が続く位置を罫線、それ以外のインクのある位置を字として、行に直交する方向の座標で返す
    private func ruledPage(
        _ text: String,
        orientation: EditorSettings.Orientation
    ) throws -> (rules: [Int], glyphs: [Int]) {
        let bitmap = try firstPageBitmap(printedBy: operation(text, orientation: orientation, guide: .ruledLines) {
            $0.showsPageNumbers = false
        })
        let height = bitmap.pixels.count / bitmap.width
        let isVertical = orientation == .vertical
        var ink = [Int](repeating: 0, count: isVertical ? bitmap.width : height)
        for (index, pixel) in bitmap.pixels.enumerated() where pixel < 250 {
            ink[isVertical ? index % bitmap.width : index / bitmap.width] += 1
        }
        let threshold = (isVertical ? height : bitmap.width) / 2
        return (
            ink.indices.filter { ink[$0] > threshold },
            ink.indices.filter { ink[$0] > 0 && ink[$0] <= threshold }
        )
    }

    private func bands(_ positions: [Int]) -> [ClosedRange<Int>] {
        var bands: [ClosedRange<Int>] = []
        for position in positions {
            if let last = bands.last, last.upperBound + 1 == position {
                bands[bands.count - 1] = last.lowerBound ... position
            } else {
                bands.append(position ... position)
            }
        }
        return bands
    }

    /// 空行のあとの行も含めて、字のかたまりのあいだの罫線は、その空きに均等に並ぶ
    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical])
    func printsRuledLinesHalfwayBetweenLines(orientation: EditorSettings.Orientation) throws {
        let page = try ruledPage("あ\n\nあ\nあ", orientation: orientation)
        let rules = bands(page.rules)
        let glyphs = bands(page.glyphs)
        try #require(glyphs.count == 3)
        // 縦書きは右の列から読むので、空行のある空きは座標の大きいほうにくる
        let gaps = zip(glyphs, glyphs.dropFirst()).map { $0.upperBound ... $1.lowerBound }
        let counts = gaps.map { gap in rules.count { gap.contains($0.lowerBound) } }
        #expect(counts == (orientation == .vertical ? [1, 2] : [2, 1]))
        for gap in gaps {
            let inside = rules.filter { gap.contains($0.lowerBound) }
            let first = try #require(inside.first?.lowerBound)
            let last = try #require(inside.last?.upperBound)
            #expect(abs((first - gap.lowerBound) - (gap.upperBound - last)) <= 2, "\(gap): \(inside)")
        }
        #expect(rules.count > 10)
    }

    /// 縦中横は回転させて描くので、位置を誤ると字が欠ける。横書きと同じ字形なので、同じくらいのインクになる
    @Test(arguments: ["12", "ｶﾞ"])
    func printsAPairInACellAsInHorizontalText(pair: String) throws {
        let vertical = try manuscriptBody(pair, orientation: .vertical).pixels.count { $0 < 250 }
        let horizontal = try manuscriptBody(pair, orientation: .horizontal).pixels.count { $0 < 250 }
        #expect(horizontal > 0)
        #expect(abs(vertical - horizontal) * 4 < horizontal, "\(vertical), \(horizontal)")
    }

    /// 字の進む方向でのインクの範囲
    private func inkExtent(_ text: String, orientation: EditorSettings.Orientation) throws -> ClosedRange<Int> {
        let page = try manuscriptBody(text, orientation: orientation)
        let extent = page.pixels.indices.filter { page.pixels[$0] < 128 }
            .map { orientation == .vertical ? $0 / page.width : $0 % page.width }
        return try #require(extent.min()) ... #require(extent.max())
    }

    @Test(arguments: [EditorSettings.Orientation.horizontal, .vertical], ["ｶﾞ", "かﾞ", "é"])
    func printsCharactersWithoutOneFullWidthGlyphInsideTheirCells(
        orientation: EditorSettings.Orientation,
        character: String
    ) throws {
        let ink = try inkExtent(character, orientation: orientation)
        let reference = try inkExtent("国", orientation: orientation)
        #expect(ink.count <= reference.count + 2, "\(ink), \(reference)")
        let offset = abs(ink.lowerBound + ink.upperBound - reference.lowerBound - reference.upperBound)
        #expect(offset <= 4, "\(ink), \(reference)")
    }

    /// 字間を指定して組むとフォントの文字ペアの詰めが効き、モチベーションのーなどから後ろがマスからずれる
    /// 空白のあとの国と、詰めが効く文字のあとの国は同じマスにあるので、同じ画素になる
    @Test
    func printsCharactersInTheirCellsAfterKerningPairs() throws {
        let alone = try manuscriptBody(String(repeating: "　", count: 8) + "国", orientation: .vertical).pixels
        let afterPairs = try manuscriptBody("モチベーションで国", orientation: .vertical).pixels
        let ink = alone.indices.filter { alone[$0] < 128 }
        #expect(ink.count > 10)
        let differing = ink.count { afterPairs[$0] >= 128 }
        #expect(differing * 20 < ink.count, "\(differing) / \(ink.count)")
    }
}
