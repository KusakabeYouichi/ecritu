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

        XCTAssertEqual(Array(merged.prefix(20)), Array(converter.prefix(20)))
        XCTAssertEqual(Array(merged.suffix(4)), Array(supplementary.prefix(4)))
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

    func testKatakanaSupplementaryForSameReadingIsDeferredBehindConverter() {
        let split = SupplementaryCandidateMerger.splitSupplementaryCandidatesForMerge(
            reading: "やまだ",
            supplementaryCandidates: ["ヤマダ"],
            converterCandidates: ["山田", "ヤマダ"]
        )

        XCTAssertTrue(split.prioritized.isEmpty)
        XCTAssertEqual(split.deferred, ["ヤマダ"])

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
