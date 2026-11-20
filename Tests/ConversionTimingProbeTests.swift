import XCTest

// 調査用(3827)の変換時間の集計の検証。ConversionTimingProbe.swift を外すときはこのファイルも一緒に消す
final class ConversionTimingProbeTests: XCTestCase {
    private func sample(total: Double, length: Int = 4) -> ConversionTimingSample {
        ConversionTimingSample(
            readingLength: length,
            queueWaitMs: 1,
            singleMs: 2,
            multiMs: total - 10,
            traceMs: 3,
            mainWaitMs: 1,
            applyMs: 3,
            totalMs: total
        )
    }

    func testSummaryIsReturnedOnlyWhenBatchIsFull() {
        var probe = ConversionTimingProbe()
        for index in 1..<ConversionTimingProbe.batchSize {
            XCTAssertNil(probe.record(sample(total: Double(index + 10))))
        }
        let line = probe.record(sample(total: 200, length: 12))
        XCTAssertNotNil(line)
        XCTAssertTrue(probe.samples.isEmpty)
        // 全体: 11...39 と 200 の 30 件。中央=15 番め(25)、90%=27 番め(37)、最大=200
        XCTAssertTrue(line?.contains("n=30") ?? false, "line=\(line ?? "")")
        XCTAssertTrue(line?.contains("全体=25/37/200") ?? false, "line=\(line ?? "")")
        XCTAssertTrue(line?.contains("最長=12字") ?? false, "line=\(line ?? "")")
        XCTAssertTrue(line?.contains("トレース=3/3/3") ?? false, "line=\(line ?? "")")
    }

    // 連文節の内訳(3857)は、記録のある打鍵があるときだけ行の終わりに付く
    func testSummaryAppendsMultiClausePhases() {
        var samples = (1...3).map { sample(total: Double($0 + 10)) }
        XCTAssertFalse(ConversionTimingProbe.summary(of: samples).contains("連文節の内訳"))
        samples[0].multiPhaseMs = ["供給": 10, "DP": 30]
        samples[1].multiPhaseMs = ["供給": 20, "DP": 50]
        let line = ConversionTimingProbe.summary(of: samples)
        XCTAssertTrue(line.contains("連文節の内訳[中央/90%] 供給=10/20 DP=30/50"), "line=\(line)")
    }

    func testPhaseRecorderCountsOnlyBetweenRestartAndPause() {
        ConversionPhaseRecorder.begin()
        ConversionPhaseRecorder.mark("供給")
        XCTAssertTrue(ConversionPhaseRecorder.end().isEmpty)
        ConversionPhaseRecorder.restart()
        ConversionPhaseRecorder.mark("供給")
        ConversionPhaseRecorder.mark("DP")
        ConversionPhaseRecorder.pause()
        ConversionPhaseRecorder.mark("変種")
        XCTAssertEqual(Set(ConversionPhaseRecorder.end().keys), ["供給", "DP"])
    }

    func testPercentileUsesNearestRank() {
        XCTAssertEqual(ConversionTimingProbe.percentile([], 0.5), 0)
        XCTAssertEqual(ConversionTimingProbe.percentile([7], 0.9), 7)
        XCTAssertEqual(ConversionTimingProbe.percentile([4, 1, 3, 2], 0.5), 2)
        XCTAssertEqual(ConversionTimingProbe.percentile([4, 1, 3, 2], 0.9), 4)
    }
}
