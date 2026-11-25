// Mac 版の入力メニュー用のアイコン(MacInputMethod/Resources/ecritu.tiff)を作る。
// 使い方: swift tools/generate_mac_icon.swift <出力先の .tiff>
//
// 形は純正の入力メソッド(Hiragana.tiff など)に合わせる: 黒く塗った角丸の四角から、文字の形を透明に抜く。
// OS は不透明の部分を状態の色(選択中は青)で塗るので、文字だけを黒で描いた画像だと、
// 選択中の表示で文字が背景と同じ色になって見えなくなる(2026-11-25 に実機で確認)
import AppKit

let glyph = "é"

func bitmap(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    // どちらも 16 ポイントの画像として扱わせる(32 ピクセルは 2 倍の解像度)
    rep.size = NSSize(width: 16, height: 16)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // 座標は 16 ポイントの升目のまま描ける(rep.size から、ピクセルへの拡大は文脈が行なう)

    // 角丸の四角(純正と同じく、端に 1 ポイント足らずの余白)
    let box = NSRect(x: 0.5, y: 0.5, width: 15, height: 15)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5).fill()

    // 文字の形を透明に抜く
    let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor.black])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let origin = CGPoint(x: box.midX - bounds.midX, y: box.midY - bounds.midY)
    context.cgContext.setBlendMode(.destinationOut)
    context.cgContext.textPosition = origin
    CTLineDraw(line, context.cgContext)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("使い方: swift tools/generate_mac_icon.swift <出力先の .tiff>\n".data(using: .utf8)!)
    exit(2)
}
let image = NSImage(size: NSSize(width: 16, height: 16))
image.addRepresentation(bitmap(pixels: 32))
image.addRepresentation(bitmap(pixels: 16))
guard let data = image.tiffRepresentation(using: .lzw, factor: 0) else {
    FileHandle.standardError.write("TIFF を作れませんでした\n".data(using: .utf8)!)
    exit(1)
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("書き出しました: \(CommandLine.arguments[1])")
