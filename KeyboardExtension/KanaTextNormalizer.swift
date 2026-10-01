import Foundation

enum KanaTextNormalizer {
    static func normalizedKanaCharacter(from text: String) -> Character? {
        // 速い道(3296): 単一スカラーの文字は ICU の文字変換を通さずに決める。ICU の Hiragana-Katakana 変換は
        // 初回に変換表を組み立てて約 0.7MB をプロセスが終わるまで持ち続ける(実機メモリグラフの記録で確認)。
        // 打鍵ごと・候補のかな判定(漢字 1 字ずつ)で呼ばれるので、ふつうの文字はここで決着させる。
        // 結果は旧実装と全文字で一致する(testKanaNormalizerMatchesLegacyForAllCharacters)
        let scalars = text.unicodeScalars
        if let scalar = scalars.first, scalars.index(after: scalars.startIndex) == scalars.endIndex {
            let value = scalar.value
            if (0x3041...0x3096).contains(value) || value == 0x30FC || (0x309D...0x309E).contains(value) {
                return Character(scalar)
            }
            // ヵ ヶ(30F5/30F6)は旧実装が か け にするので遅い道へ(ゕ ゖ にしない)
            if (0x30A1...0x30F4).contains(value), let hiragana = Unicode.Scalar(value - 0x60) {
                return Character(hiragana)
            }
            // かな・カタカナ・半角カタカナ・小書きカタカナ拡張・丸囲みカタカナ(㋐ → あ)の外は、どう変換してもかなにならない
            if !(0x3040...0x30FF).contains(value), !(0xFF61...0xFF9F).contains(value), !(0x31F0...0x31FF).contains(value),
                !(0x32D0...0x32FE).contains(value) {
                return nil
            }
        }
        return slowNormalizedKanaCharacter(from: text)
    }

    // まれな文字(濁点が別の文字の か+゙、ヷ〜ヺ、ゟ/ヿ、半角カタカナ 等)だけ旧来の道で決める
    private static func slowNormalizedKanaCharacter(from text: String) -> Character? {
        guard text.count == 1 else {
            return nil
        }

        let source = text.precomposedStringWithCanonicalMapping
        let normalized = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

        guard normalized.count == 1,
                let character = normalized.first,
                isKanaCharacter(character) else {
            return nil
        }

        return character
    }

    static func normalizedReading(_ text: String) -> String {
        var normalized = ""
        normalized.reserveCapacity(text.utf8.count)

        for character in text {
            // 速い道(3096): 単一スカラーの基本ひらがな・長音・踊り字はそのまま、基本カタカナはコード点をずらして
            // ひらがなへ。Foundation の正規化+文字変換(1 字ごとに数個の確保、打鍵あたり約 2000 回)を通さない。
            // 結果は遅い道と同じ(NFC 済みの単一スカラーに正規化は何もせず、カタカナ→ひらがな変換は -0x60)
            let scalars = character.unicodeScalars
            if scalars.count == 1, let scalar = scalars.first {
                let value = scalar.value
                if (0x3041...0x3096).contains(value) || value == 0x30FC || (0x309D...0x309E).contains(value) {
                    normalized.unicodeScalars.append(scalar)
                    continue
                }
                if (0x30A1...0x30F6).contains(value), let hiragana = Unicode.Scalar(value - 0x60) {
                    normalized.unicodeScalars.append(hiragana)
                    continue
                }
            }
            if let kanaCharacter = normalizedKanaCharacter(from: String(character)) {
                normalized.append(kanaCharacter)
            }
        }

        return normalized
    }

    private static func isKanaCharacter(_ character: Character) -> Bool {
        guard let scalar = String(character).unicodeScalars.first else {
            return false
        }

        if (0x3040...0x309F).contains(scalar.value) {
            return true
        }

        return scalar.value == 0x30FC
    }
}
