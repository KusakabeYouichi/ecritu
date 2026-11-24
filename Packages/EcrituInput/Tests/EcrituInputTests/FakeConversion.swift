import XCTest
@testable import EcrituInput

/// 設計 5 章の偽の変換。呼び出し(reading, precedingText)と learn を記録する
final class FakeConversion: ConversionProviding {
    struct Call: Equatable {
        var reading: String
        var precedingText: String
    }

    struct Learned: Equatable {
        var reading: String
        var candidate: String
    }

    private(set) var calls: [Call] = []
    private(set) var learned: [Learned] = []
    /// 表に足す規則(S55・S56)。nil を返したら表を引く
    var additionalRule: ((String) -> [String]?)?

    private let table: [String: [String]] = [
        "かんじ": ["漢字", "感じ", "幹事"],
        "かん": ["缶", "感"],
        "じ": ["字", "時"],
        "こ": ["子", "個"],
        "あ": ["亜"],
        "えー": ["\u{FF21}", "ええ"],
        "だめ": ["\u{FF21}"],
        "そら": ["", "空"],
        "に": ["2"],
        "さ": ["差", "左", "佐", "砂", "鎖", "詐", "査", "沙", "些", "嵯", "瑳", "作"],
    ]

    func candidates(reading: String, precedingText: String) -> [String] {
        calls.append(Call(reading: reading, precedingText: precedingText))
        if let rule = additionalRule, let result = rule(reading) {
            return result
        }
        if reading == "こ", precedingText.hasSuffix("3") {
            return ["個", "子"]
        }
        return table[reading] ?? []
    }

    func learn(reading: String, candidate: String) {
        learned.append(Learned(reading: reading, candidate: candidate))
    }
}

extension InputSession {
    /// 文字列の各字を .character で順に送り、最後の結果を返す
    @discardableResult
    func type(_ text: String) -> InputResult {
        var last: InputResult?
        for character in text {
            last = handle(.character(character))
        }
        return last!
    }

    /// 結果を見ないで送るとき用(準備の手順)
    @discardableResult
    func press(_ key: KeyInput) -> InputResult {
        handle(key)
    }
}

extension InputResult {
    /// 未確定の表示を 1 本の文字列にしたもの(未確定なしは nil)
    var markedString: String? {
        marked?.segments.map(\.text).joined()
    }
}

func segment(_ text: String, _ style: MarkedText.Style) -> MarkedText.Segment {
    MarkedText.Segment(text: text, style: style)
}
