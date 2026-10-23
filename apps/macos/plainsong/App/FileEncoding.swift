import Foundation

nonisolated struct FileEncoding: Equatable {
    static let utf8 = FileEncoding(encoding: .utf8, hasByteOrderMark: false)
    /// テキストエディットなどがファイルに付ける、文字コードの拡張属性。値は「SHIFT_JIS;2561」のように、IANAの名前とCFStringEncodingの値を並べたもの
    private static let attributeName = "com.apple.TextEncoding"
    private static let suggestions: [String.Encoding] = [.shiftJIS, .japaneseEUC, .iso2022JP, .utf16]

    var encoding: String.Encoding
    var hasByteOrderMark: Bool

    var name: String {
        switch encoding {
        case .utf8: hasByteOrderMark ? "UTF-8 BOM" : "UTF-8"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        case .utf16: "UTF-16"
        default:
            switch ianaName?.uppercased() {
            case "SHIFT_JIS", "CP932", "WINDOWS-31J": "Shift-JIS"
            case let name?: name
            case nil: String.localizedName(of: encoding)
            }
        }
    }

    private var ianaName: String? {
        CFStringConvertEncodingToIANACharSetName(cfEncoding) as String?
    }

    private var cfEncoding: CFStringEncoding {
        CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
    }

    private var byteOrderMark: Data {
        guard hasByteOrderMark else { return Data() }
        return switch encoding {
        case .utf8: Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndian: Data([0xFF, 0xFE])
        case .utf16BigEndian: Data([0xFE, 0xFF])
        default: Data()
        }
    }

    /// 保存できない文字があればnilを返す。文字を「?」に置き換えて保存すると、書いた内容が失われる
    func encode(_ string: String) -> Data? {
        let data = encoding == .utf8 ? Data(string.utf8) : string.data(using: encoding, allowLossyConversion: false)
        return data.map { byteOrderMark + $0 }
    }

    /// UTF-8のファイルには付けない。ほかの文字コードは、NSDocumentが保存するたびに属性を消すので、付け直さないと次に開いたときに推測が外れることがある
    private var attributeValue: Data? {
        guard encoding != .utf8, let ianaName else { return nil }
        return Data("\(ianaName);\(cfEncoding)".utf8)
    }

    func writeAttribute(to url: URL) {
        guard let value = attributeValue else { return }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = value.withUnsafeBytes { setxattr(path, Self.attributeName, $0.baseAddress, value.count, 0, 0) }
        }
    }

    /// ファイルに残っている文字コードは古いことがあるので、UTF-8として正しく読めるならUTF-8を選ぶ
    static func decode(_ data: Data, attributeEncoding: String.Encoding? = nil) throws -> (String, FileEncoding) {
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            let fileEncoding = FileEncoding(encoding: encoding, hasByteOrderMark: true)
            let byteOrderMark = fileEncoding.byteOrderMark
            guard data.starts(with: byteOrderMark),
                  let string = String(data: data.dropFirst(byteOrderMark.count), encoding: encoding)
            else { continue }
            return (string, fileEncoding)
        }
        if let string = String(data: data, encoding: .utf8) {
            return (string, .utf8)
        }
        if let attributeEncoding, let string = String(data: data, encoding: attributeEncoding) {
            return (string, FileEncoding(encoding: attributeEncoding, hasByteOrderMark: false))
        }
        var converted: NSString?
        let encoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: suggestions.map { NSNumber(value: $0.rawValue) },
                .allowLossyKey: false,
            ],
            convertedString: &converted,
            usedLossyConversion: nil
        )
        guard encoding != 0, let converted else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let fileEncoding = FileEncoding(encoding: String.Encoding(rawValue: encoding), hasByteOrderMark: false)
        return (converted as String, fileEncoding)
    }

    static func attributeEncoding(at url: URL) -> String.Encoding? {
        let value: String? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let size = getxattr(path, attributeName, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: size)
            guard getxattr(path, attributeName, &bytes, size, 0, 0) == size else { return nil }
            return String(bytes: bytes, encoding: .ascii)
        }
        return value.flatMap(encoding(fromAttribute:))
    }

    static func encoding(fromAttribute value: String) -> String.Encoding? {
        let parts = value.split(separator: ";")
        guard let name = parts.first else { return nil }
        let cfEncoding = parts.count > 1
            ? UInt32(parts[1]) ?? kCFStringEncodingInvalidId
            : CFStringConvertIANACharSetNameToEncoding(String(name) as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}
