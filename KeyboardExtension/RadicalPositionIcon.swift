import SwiftUI

// 漢字の枠(マス)のどこを部首が占めるかを描く抽象アイコン。枠は共通の角丸矩形で、
// 塗りの位置だけがカテゴリーの違いを表す。画像アセットを持たずサイズ自由。
struct RadicalPositionIcon: Shape {
    let category: RadicalPositionCategory

    func path(in rect: CGRect) -> Path {
        // 32×32 の設計座標を rect に合わせる。枠は 3〜29(内側26)。
        let unit = min(rect.width, rect.height) / 32
        let origin = CGPoint(
            x: rect.midX - unit * 16,
            y: rect.midY - unit * 16
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
        }
        func band(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(
                origin: point(x0, y0),
                size: CGSize(width: (x1 - x0) * unit, height: (y1 - y0) * unit)
            )
        }

        var path = Path()
        let third: CGFloat = 12
        let far: CGFloat = 20

        switch category {
        case .hen:
            path.addRect(band(3, 3, third, 29))
        case .tsukuri:
            // 旁は偏より広いのが通例なので右1/2(偏は1/3)
            path.addRect(band(16, 3, 29, 29))
        case .kanmuri:
            path.addRect(band(3, 3, 29, third))
        case .ashi:
            path.addRect(band(3, far, 29, 29))
        case .tare:
            // 上の帯 + 左へ垂れる(广)
            path.addRect(band(3, 3, 29, third))
            path.addRect(band(3, third, third, 29))
        case .nyou:
            // 左 + 下へ回り込む(辶)
            path.addRect(band(3, 3, third, 29))
            path.addRect(band(third, far, 29, 29))
        case .kamae:
            // 門の形。左右の柱+上の帯で、下の真ん中1/3は開ける(間/開)
            path.addRect(band(3, 3, 29, third))
            path.addRect(band(3, third, third, 29))
            path.addRect(band(far, third, 29, 29))
        case .independent:
            // 位置を持たない = 中央の小さな塊
            path.addRect(band(11, 11, 21, 21))
        }
        return path
    }
}
