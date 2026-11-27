// Mac 版の入力メニュー用のアイコン(MacInputMethod/Resources/ecritu.tiff)を作る。
// 使い方: swift tools/generate_mac_icon.swift <出力先の .tiff>
//
// 形は、透明の地に文字だけを黒で描いたもの(枠なし)。2026-11-25 にユーザが実機で見比べて決めた。
// 第三者製の入力メソッドでは、OS がこの 1 枚をメニューバー・メニュー・[入力ソース] の一覧・
// 切り替えのときの吹き出しの全部に使い、不透明の部分を状態の色で塗る(Info.plist の TISIconIsTemplate)。
//   文字だけ(この形)… 吹き出しは純正と揃う(選択中は青い丸に白い文字)。メニューと一覧は écritu だけ枠が無い
//   枠つき(黒い角丸の四角から文字を透明に抜く。純正の Hiragana.tiff の形)… メニューと一覧は揃うが、吹き出しで écritu だけ枠が付く
// 両方を揃える方法は見つかっていない。同日に試して使えなかった手:
//   - 画像の指定を外して TISIconLabels だけにする → 汎用のアプリのアイコンになる
//   - tsInputModeAlternateMenuIconFileKey を足す → 状態の色で塗られなくなる(メニューバーで黒いまま、選択中に見えない)
//   - tsInputModePaletteIconFileKey を足す → どこにも使われない
// 幅は 22 ポイントまで。24 にすると、メニューで OS に縮められた
import AppKit

let glyph = "é"
let pointSize = NSSize(width: 22, height: 16)

func bitmap(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pointSize.width) * scale, pixelsHigh: Int(pointSize.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    // どちらの解像度も、同じポイントの大きさの画像として扱わせる
    rep.size = pointSize

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // 座標はポイントの升目のまま描ける(rep.size から、ピクセルへの拡大は文脈が行なう)
    let font = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
    let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor.black])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.cgContext.textPosition = CGPoint(
        x: pointSize.width / 2 - bounds.midX,
        y: pointSize.height / 2 - bounds.midY
    )
    CTLineDraw(line, context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("使い方: swift tools/generate_mac_icon.swift <出力先の .tiff>\n".data(using: .utf8)!)
    exit(2)
}

let image = NSImage(size: pointSize)
image.addRepresentation(bitmap(scale: 2))
image.addRepresentation(bitmap(scale: 1))
guard let data = image.tiffRepresentation(using: .lzw, factor: 0) else {
    FileHandle.standardError.write("TIFF を作れませんでした\n".data(using: .utf8)!)
    exit(1)
}

try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("書き出しました: \(CommandLine.arguments[1])")
