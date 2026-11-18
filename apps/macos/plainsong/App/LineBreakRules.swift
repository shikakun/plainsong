import Foundation

/// 原稿用紙と通常の表示で、同じ字をぶら下げる
nonisolated enum LineBreakRules {
    /// JLREQがぶら下げを認める句点類（cl-06）と読点類（cl-07）。半角の.,は欧文の行末にも現れるので、全角だけをぶら下げる
    private static let hanging = Set("、。，．".unicodeScalars)
    /// stone_engineのSTKinsoku（MIT License, Copyright 2024 Nihon Design Center）に、全角の！，．：；とゝゞを足したもの
    private static let notStarting = Set(
        " ,.?:;!)）]］｝、〕〉》」』】〙〗〟’”｠»ヽヾゝゞァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎゕゖㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ々〻？！，．：；‼⁇⁈⁉。.™".unicodeScalars
    )
    private static let notEnding = Set("(（[［｛〔〈《「『【〘〖〝‘“｟«\"'".unicodeScalars)

    /// 次の字も行頭に置けないときにぶら下げると、その字の行き場がなくなる
    static func canHang(_ scalar: Unicode.Scalar?, before next: Unicode.Scalar?) -> Bool {
        guard let scalar, hanging.contains(scalar) else { return false }
        return !isNotStarting(next)
    }

    static func isNotStarting(_ scalar: Unicode.Scalar?) -> Bool {
        scalar.map(notStarting.contains) ?? false
    }

    static func isNotEnding(_ scalar: Unicode.Scalar?) -> Bool {
        scalar.map(notEnding.contains) ?? false
    }

    static func isParagraphBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x85 || character == 0x2029
    }

    static func isLineBreak(_ character: unichar) -> Bool {
        isParagraphBreak(character) || character == 0x2028
    }
}
