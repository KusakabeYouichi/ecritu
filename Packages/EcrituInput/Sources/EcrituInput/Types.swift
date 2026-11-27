import Foundation

/// かな漢字変換を外から渡すための口。Mac のターゲットが変換エンジンをつないで実装する
public protocol ConversionProviding: AnyObject {
    /// 先頭が最良。空で返ることがある。precedingText は読みの直前にある確定済みの文字列(最大 8 文字。無ければ空)
    func candidates(reading: String, precedingText: String) -> [String]
    func learn(reading: String, candidate: String)
    /// 待たずに答えられるときだけ候補を返す。nil = まだ求めていない(candidates を呼ぶと、求め終わるまで待つ)。
    /// 打鍵のたびのライヴ変換は、これが nil の間はかなを表示し、裏で求め終わってから表示を差し替える
    func cachedCandidates(reading: String, precedingText: String) -> [String]?
}

public extension ConversionProviding {
    /// 初期の実装: いつでもその場で求める(待つ)。すぐ答えられる変換や、試験用の変換はこれで足りる
    func cachedCandidates(reading: String, precedingText: String) -> [String]? {
        candidates(reading: reading, precedingText: precedingText)
    }
}

/// 裏で求めておいてほしいライヴ変換。InputSession.prewarm に渡す
public struct LiveConversionRequest: Equatable, Sendable {
    public var reading: String
    public var precedingText: String
    /// 自動確定の判定を先送りにした要求(判定に要る、先頭と残りの変換も求める)
    public var wantsAutoCommit: Bool
}

/// 入力メソッドへ届くキー
public enum KeyInput: Equatable {
    /// 印字できる ASCII(U+0021...U+007E)。Shift や CapsLock は文字に反映済み(大文字で届く)
    case character(Character)
    case space, enter, backspace, escape, tab
    case left(shift: Bool), right(shift: Bool), up, down
    /// F6 / ⌃J、F7 / ⌃K
    case toHiragana, toKatakana
    case switchToLatin, switchToJapanese
}

/// 未確定の表示。区切りごとに見た目の種類を持つ
public struct MarkedText: Equatable {
    public enum Style { case target, converted, raw }
    public struct Segment: Equatable {
        public var text: String
        public var style: Style
    }
    public var segments: [Segment]
}

public struct CandidateList: Equatable {
    public var items: [String]
    public var selectedIndex: Int
}

public struct InputResult: Equatable {
    /// false ならホストへキーを通す
    public var handled: Bool
    /// 挿入する文字列(空なら無し)。キーを通すより前、marked の反映より前に挿入する
    public var committed: String
    /// nil = 未確定なし
    public var marked: MarkedText?
    /// nil = 候補ウインドウを閉じる
    public var candidates: CandidateList?
    /// nil でなければ、表示に要る変換がまだ求まっていない(marked はかなのまま)。
    /// 裏で InputSession.prewarm を呼び、終わったら refresh() の結果を反映する
    public var pendingConversion: LiveConversionRequest? = nil
}
