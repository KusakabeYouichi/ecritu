import XCTest

final class KeyboardCandidateMergingTests: XCTestCase {
    func testSupplementaryMergingKeepsConverterSlotsForTopCandidates() {
        let supplementary = (1...40).map { "補助候補\($0)" }
        let converter = ["カナダ", "金田", "叶田", "鐘田"] + (1...40).map { "変換候補\($0)" }

        let merged = SupplementaryCandidateMerger.mergeSupplementaryAndConverterCandidates(
            reading: "かなだ",
            supplementaryCandidates: supplementary,
            converterCandidates: converter,
            limit: 24
        )

        XCTAssertEqual(merged.count, 24)
        XCTAssertTrue(merged.contains("カナダ"), "merged=\(merged)")
    }

    func testSupplementaryMergingPrioritizesConverterBeforeSupplementary() {
        let supplementary = (1...20).map { "補助候補\($0)" }
        let converter = (1...20).map { "変換候補\($0)" }

        let merged = SupplementaryCandidateMerger.mergeSupplementaryAndConverterCandidates(
            reading: "かな",
            supplementaryCandidates: supplementary,
            converterCandidates: converter,
            limit: 24
        )

        // 短い読み(≤2文字)では変換候補を優先しつつ、補助候補(連絡先・ユーザー辞書 等)が
        // 完全に消えないよう一定スロットを確保する設計。limit=24では先頭18件が変換候補、
        // 残り6枠に補助候補を先頭4件+末尾2件のサンプリングで配置する。
        XCTAssertEqual(merged.count, 24)
        XCTAssertEqual(Array(merged.prefix(18)), Array(converter.prefix(18)))
        XCTAssertEqual(
            Array(merged.suffix(6)),
            ["補助候補1", "補助候補2", "補助候補3", "補助候補4", "補助候補19", "補助候補20"]
        )
    }

    func testSupplementaryMergingFallsBackWhenConverterIsSparse() {
        let supplementary = (1...20).map { "補助候補\($0)" }
        let converter = ["変換候補A", "変換候補B"]

        let merged = SupplementaryCandidateMerger.mergeSupplementaryAndConverterCandidates(
            reading: "かな",
            supplementaryCandidates: supplementary,
            converterCandidates: converter,
            limit: 12
        )

        XCTAssertEqual(merged.count, 12)
        XCTAssertTrue(merged.contains("変換候補A"), "merged=\(merged)")
        XCTAssertTrue(merged.contains("変換候補B"), "merged=\(merged)")
    }

    func testKatakanaSupplementaryForSameReadingIsDedupedAgainstConverter() {
        let split = SupplementaryCandidateMerger.splitSupplementaryCandidatesForMerge(
            reading: "やまだ",
            supplementaryCandidates: ["ヤマダ"],
            converterCandidates: ["山田", "ヤマダ"]
        )

        // split は変換候補「文字列」から同一読みを正規化して判定するため、漢字候補(山田)は
        // 読み「やまだ」と一致せず検出されない。よってカタカナ補助候補の defer は発生せず、
        // 重複排除は後段の merge(seen 集合)が担う。
        XCTAssertEqual(split.prioritized, ["ヤマダ"])
        XCTAssertTrue(split.deferred.isEmpty)

        let mergedPrimary = SupplementaryCandidateMerger.mergeSupplementaryAndConverterCandidates(
            reading: "やまだ",
            supplementaryCandidates: split.prioritized,
            converterCandidates: ["山田", "ヤマダ"],
            limit: 8
        )

        var merged = mergedPrimary

        if merged.count < 8 {
            for candidate in split.deferred where !merged.contains(candidate) {
                merged.append(candidate)
            }
        }

        XCTAssertEqual(merged.first, "山田", "merged=\(merged)")
        XCTAssertTrue(merged.contains("ヤマダ"), "merged=\(merged)")
    }
}
