// 標準入力の各行(単語)を、キーボード実行時と同一の折り畳み
// (KanaKanjiStore.latinSuggestionSearchKey と同じオプション・ロケール)で
// 検索キーへ変換して出力する。build_latin_suggestion_lexicon.py から呼ばれる。
import Foundation

while let line = readLine(strippingNewline: true) {
    let key = line
        .folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
        .lowercased()
    print(key)
}
