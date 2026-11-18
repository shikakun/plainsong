import Foundation

extension EditorSettings {
    /// 本文の左右の余白の最小値。行番号を出すときは、左だけこの2倍にして番号を置く
    var minimumInset: CGFloat {
        fontSize * 2
    }

    var lineNumberGutter: CGFloat {
        minimumInset * 2
    }

    func lineInsets(
        clipLength: CGFloat,
        minimumLeading: CGFloat,
        minimumTrailing: CGFloat
    ) -> (leading: CGFloat, trailing: CGFloat) {
        if showsManuscriptGuide, !usesReadableWidth {
            let cells = manuscriptCells(
                clipLength: clipLength,
                minimumLeading: minimumLeading,
                minimumTrailing: minimumTrailing
            )
            return (minimumLeading, clipLength - minimumLeading - fontSize * CGFloat(cells))
        }
        guard usesReadableWidth else { return (minimumLeading, minimumTrailing) }
        let maximumLength = showsManuscriptGuide
            ? fontSize * CGFloat(manuscriptCells(
                clipLength: clipLength,
                minimumLeading: minimumLeading,
                minimumTrailing: minimumTrailing
            ))
            : fontSize * readableWidth.ems(in: orientation)
        let centeringInset = ((clipLength - maximumLength) / 2).rounded(.down)
        if centeringInset >= max(minimumLeading, minimumTrailing) {
            return (centeringInset, centeringInset)
        }
        return (minimumLeading, max(minimumTrailing, (clipLength - maximumLength - minimumLeading).rounded(.down)))
    }

    func manuscriptCells(clipLength: CGFloat, minimumLeading: CGFloat, minimumTrailing: CGFloat) -> Int {
        let fitting = max(Int((clipLength - minimumLeading - minimumTrailing) / fontSize), 1)
        return usesReadableWidth ? min(Int(readableWidth.ems(in: orientation)), fitting) : fitting
    }

    /// 原稿用紙のマス数がウィンドウで決まるあいだ、行末の余白はマスに満たない端数で増減する。広げると、幅を変えるたびに本文とマス目が揺れる
    func crossInsetExpansion(clipLength: CGFloat, minimumLeading: CGFloat, minimumTrailing: CGFloat) -> CGFloat {
        if showsManuscriptGuide {
            let cells = manuscriptCells(
                clipLength: clipLength,
                minimumLeading: minimumLeading,
                minimumTrailing: minimumTrailing
            )
            guard usesReadableWidth, cells >= Int(readableWidth.ems(in: orientation)) else { return 0 }
        }
        let trailing = lineInsets(
            clipLength: clipLength,
            minimumLeading: minimumLeading,
            minimumTrailing: minimumTrailing
        ).trailing
        return min((trailing - minimumTrailing) / 2, fontSize * 4).rounded(.down)
    }
}
