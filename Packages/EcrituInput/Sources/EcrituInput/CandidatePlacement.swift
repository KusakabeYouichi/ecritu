import CoreGraphics

/// 候補ウインドウを出す場所の計算(画面の座標は左下が原点、y は上向き)
public enum CandidatePlacement {
    /// 未確定の行と候補ウインドウの間のすき間(上に出すときも下に出すときも同じ。ユーザ指定 2026-11-27)
    public static let gap: CGFloat = 2

    /// 未確定の行(anchor)の下に、すき間をあけて出す。下に入りきらなければ行の上に出す。
    /// 左右と上下は、画面の使える範囲(visibleFrame)からはみ出さないように寄せる
    public static func origin(size: CGSize, anchor: CGRect, visibleFrame: CGRect) -> CGPoint {
        var y = anchor.minY - gap - size.height
        if y < visibleFrame.minY {
            // 下に入らない。行の上に出す
            y = anchor.maxY + gap
        }
        // 上にも入らないほど大きいときなどは、範囲の中へ寄せる(下端を優先して見せる)
        y = min(y, visibleFrame.maxY - size.height)
        y = max(y, visibleFrame.minY)

        var x = anchor.minX
        x = min(x, visibleFrame.maxX - size.width)
        x = max(x, visibleFrame.minX)
        return CGPoint(x: x, y: y)
    }
}
