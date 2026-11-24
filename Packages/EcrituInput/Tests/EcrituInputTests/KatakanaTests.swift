import XCTest
@testable import EcrituInput

/// 設計 5 章「カタカナ化」K1〜K4
final class KatakanaTests: XCTestCase {
    func testK1LongVowelMarkIsKept() {
        XCTAssertEqual(katakana(from: "こんぴゅーたー"), "コンピューター")
    }

    func testK2SmallVuBecomesKatakanaVu() {
        XCTAssertEqual(katakana(from: "ゔぁいおりん"), "ヴァイオリン")
    }

    func testK3LatinLettersAreKept() {
        XCTAssertEqual(katakana(from: "qあか"), "qアカ")
    }

    func testK4EveryHiraganaMapsIntoKatakanaRange() {
        for value in UInt32(0x3041)...UInt32(0x3096) {
            let hiragana = String(Unicode.Scalar(value)!)
            let result = katakana(from: hiragana).unicodeScalars
            XCTAssertEqual(result.count, 1, hiragana)
            XCTAssertTrue((0x30A1...0x30F6).contains(result.first!.value), hiragana)
        }
    }
}
