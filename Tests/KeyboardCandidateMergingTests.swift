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

    func testKatakanaSupplementaryForSameReadingIsKeptAndDedupedAgainstConverter() {
        // 連絡先・ユーザー辞書由来のカタカナ候補(ヤマダ)は後ろに回さず通常の補助候補として
        // 扱う。変換候補が漢字を優先(山田が先頭)しつつ、カタカナ候補も保持され、
        // 変換候補側と重複する場合は merge の重複排除で1件にまとまる。
        let merged = SupplementaryCandidateMerger.mergeSupplementaryAndConverterCandidates(
            reading: "やまだ",
            supplementaryCandidates: ["ヤマダ"],
            converterCandidates: ["山田", "ヤマダ"],
            limit: 8
        )

        XCTAssertEqual(merged.first, "山田", "merged=\(merged)")
        XCTAssertTrue(merged.contains("ヤマダ"), "merged=\(merged)")
        XCTAssertEqual(merged.filter { $0 == "ヤマダ" }.count, 1, "merged=\(merged)")
    }

    // 「出来る」系は「できる」系より必ず後ろ。かな版が存在する時だけ漢字版を直後へ回す。
    func testDekiKanjiIsDemotedBelowKanaCounterpart() {
        let ordered = SupplementaryCandidateMerger.demotingDekiKanjiBelowKana(
            ["入力出来ちゃう", "入力できちゃう", "にゅうりょくできちゃう"]
        )
        let kanaIndex = ordered.firstIndex(of: "入力できちゃう")!
        let kanjiIndex = ordered.firstIndex(of: "入力出来ちゃう")!
        XCTAssertLessThan(kanaIndex, kanjiIndex, "ordered=\(ordered)")
        // 漢字版はかな版の直後に置かれる。
        XCTAssertEqual(kanjiIndex, kanaIndex + 1, "ordered=\(ordered)")
    }

    // かな版が候補に無い場合は漢字版を動かさない(欠落・順序破壊なし)。
    func testDekiKanjiUntouchedWhenNoKanaCounterpart() {
        let input = ["入力出来ちゃう", "その他候補"]
        XCTAssertEqual(SupplementaryCandidateMerger.demotingDekiKanjiBelowKana(input), input)
    }

    // 「出来事」「出来上がる」等(出来の直後が活用頭ひらがなでない)は誤発火しない。
    func testDekiKanjiNounFormsAreNotDemoted() {
        let input = ["出来事", "できごと", "出来上がる", "できあがる"]
        XCTAssertEqual(SupplementaryCandidateMerger.demotingDekiKanjiBelowKana(input), input)
    }
}
