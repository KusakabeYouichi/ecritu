import Foundation

/// ひらがな(U+3041...U+3096)をカタカナ(U+30A1...U+30F6)にする。ほかの文字はそのまま。
/// エンジンにも同じ関数があるが、このパッケージはエンジンに依存させないので小さく持つ
func katakana(from text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        if (0x3041...0x3096).contains(scalar.value), let shifted = Unicode.Scalar(scalar.value + 0x60) {
            scalars.append(shifted)
        } else {
            scalars.append(scalar)
        }
    }
    return String(scalars)
}
