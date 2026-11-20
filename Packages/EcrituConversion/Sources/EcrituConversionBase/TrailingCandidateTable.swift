import Foundation

// 生成ファイル。tools/build_trailing_candidate_table.py が references/fiefs.plist から作る。手で直さない(3860)
// 候補の後ろのほうに足す語(藩の名前)。読み全体がこの読みのときだけ、単文節の候補に足す(先頭は奪わない)
public enum TrailingCandidateTable {
    public static let surfacesByReading: [String: [String]] = [
        "あきはん": ["安芸藩"],
        "あんじはん": ["安志藩"],
        "いいのはん": ["飯野藩"],
        "いくさかはん": ["生坂藩"],
        "おおたきはん": ["大多喜藩"],
        "おかはん": ["岡藩"],
        "おしはん": ["忍藩"],
        "おゆみはん": ["生実藩"],
        "かのうはん": ["加納藩"],
        "かわらはん": ["香春藩"],
        "かんべはん": ["神戸藩"],
        "くろいしはん": ["黒石藩"],
        "ころもはん": ["挙母藩"],
        "ごとうはん": ["五島藩"],
        "さぬきはん": ["佐貫藩"],
        "さのはん": ["佐野藩"],
        "さやまはん": ["狭山藩"],
        "しんじょうはん": ["新庄藩"],
        "じょうざいはん": ["請西藩"],
        "たかはしはん": ["高梁藩"],
        "たこはん": ["多古藩"],
        "たてはん": ["館藩"],
        "たのくちはん": ["田野口藩"],
        "ちくぜんはん": ["筑前藩"],
        "ちづかはん": ["千束藩"],
        "つはん": ["津藩"],
        "となみはん": ["斗南藩"],
        "にいやはん": ["新谷藩"],
        "にしばたはん": ["西端藩"],
        "はかたはん": ["伯太藩"],
        "はすのいけはん": ["蓮池藩"],
        "ひじはん": ["日出藩"],
        "びぜんはん": ["備前藩"],
        "ふきあげはん": ["吹上藩"],
        "ましまはん": ["真島藩"],
        "まつみねはん": ["松嶺藩"],
        "もりはん": ["母里藩", "森藩"],
        "やまかみはん": ["山上藩"],
        "やまがはん": ["山家藩"],
        "やまさきはん": ["山崎藩"],
        "ゆながやはん": ["湯長谷藩"],
    ]

    // 足す位置(0 始まり)。候補がこれより少なければ末尾
    public static let insertionIndex = 2

    public static func inserted(reading: String, candidates: [String]) -> [String] {
        guard let surfaces = surfacesByReading[reading] else {
            return candidates
        }
        let missing = surfaces.filter { !candidates.contains($0) }
        guard !missing.isEmpty else {
            return candidates
        }
        var result = candidates
        result.insert(contentsOf: missing, at: min(insertionIndex, result.count))
        return result
    }
}
