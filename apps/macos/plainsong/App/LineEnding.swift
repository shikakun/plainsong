import Foundation

/// ファイルの改行コード。本文は読み込んだときの改行をそのまま持ち、保存するときに、いちばん多い改行コードにそろえる
/// 改行はどれもASCIIの文字なので、UTF-8のバイト列のまま数える
nonisolated enum LineEnding: String {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"

    var name: String {
        switch self {
        case .lf: "LF"
        case .crlf: "CRLF"
        case .cr: "CR"
        }
    }

    /// いちばん多い改行コードと、ほかの改行コードが混ざっているかを返す。\nと同じ数なら\nにする
    static func detect(in string: String) -> (lineEnding: LineEnding, isMixed: Bool) {
        var string = string
        let counts = string.withUTF8(Counts.init)
        let lineEnding: LineEnding = if counts.crlf > counts.lf, counts.crlf >= counts.cr {
            .crlf
        } else if counts.cr > counts.lf, counts.cr > counts.crlf {
            .cr
        } else {
            .lf
        }
        return (lineEnding, counts.hasOthers(than: lineEnding))
    }

    func normalizing(_ string: String) -> String {
        var string = string
        let normalized: String? = string.withUTF8 { bytes in
            guard Counts(bytes).hasOthers(than: self) else { return nil }
            let lineEnding = Array(rawValue.utf8)
            var output: [UInt8] = []
            output.reserveCapacity(bytes.count)
            var index = 0
            while index < bytes.count {
                switch bytes[index] {
                case 0x0D:
                    output += lineEnding
                    if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                        index += 1
                    }
                case 0x0A:
                    output += lineEnding
                default:
                    output.append(bytes[index])
                }
                index += 1
            }
            return String(bytes: output, encoding: .utf8)
        }
        return normalized ?? string
    }

    private struct Counts {
        var lf = 0
        var cr = 0
        var crlf = 0

        init(_ bytes: UnsafeBufferPointer<UInt8>) {
            var index = 0
            while index < bytes.count {
                switch bytes[index] {
                case 0x0D where index + 1 < bytes.count && bytes[index + 1] == 0x0A:
                    crlf += 1
                    index += 1
                case 0x0D: cr += 1
                case 0x0A: lf += 1
                default: break
                }
                index += 1
            }
        }

        func hasOthers(than lineEnding: LineEnding) -> Bool {
            switch lineEnding {
            case .lf: cr + crlf > 0
            case .crlf: lf + cr > 0
            case .cr: lf + crlf > 0
            }
        }
    }
}
