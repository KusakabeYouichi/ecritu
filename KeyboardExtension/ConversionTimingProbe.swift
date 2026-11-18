import Foundation

// 調査用(3827): 実機で 1 打鍵の変換にかかった時間を段階ごとに集め、まとまった数ごとに 1 行の要約にする。
// 「変換が遅くなった」という体感が、変換の本体なのか、順番待ちや仕上げ(表示側)なのかを切り分けるためのもの。
// 記録するのは時間と読みの字数だけで、打った文字そのものは残さない。呼び出しはデバッグ版だけ(#if DEBUG)。
// 原因が分かったら外す(grep "調査用(3827)")。
struct ConversionTimingSample: Equatable {
    var readingLength: Int
    // 打鍵(main)から候補生成キューで順番が来るまで
    var queueWaitMs: Double
    // 単文節の変換
    var singleMs: Double
    // 連文節の変換
    var multiMs: Double
    // デバッグ版の変換トレースの記録
    var traceMs: Double
    // 変換が終わってから main で順番が来るまで
    var mainWaitMs: Double
    // main での仕上げ(補助候補の合流、並べ替え、日付など)
    var applyMs: Double
    // 打鍵から仕上げの終わりまで
    var totalMs: Double
}

struct ConversionTimingProbe {
    static let batchSize = 30
    static let storedSummaryLimit = 400

    private(set) var samples: [ConversionTimingSample] = []

    // batchSize 件たまったら要約を返して空にする
    mutating func record(_ sample: ConversionTimingSample) -> String? {
        samples.append(sample)
        guard samples.count >= Self.batchSize else {
            return nil
        }
        let line = Self.summary(of: samples)
        samples.removeAll(keepingCapacity: true)
        return line
    }

    static func summary(of samples: [ConversionTimingSample]) -> String {
        guard !samples.isEmpty else {
            return "n=0"
        }
        let lengths = samples.map { Double($0.readingLength) }
        let averageLength = lengths.reduce(0, +) / Double(lengths.count)
        let phases: [(String, [Double])] = [
            ("全体", samples.map(\.totalMs)),
            ("順番待ち", samples.map(\.queueWaitMs)),
            ("単文節", samples.map(\.singleMs)),
            ("連文節", samples.map(\.multiMs)),
            ("トレース", samples.map(\.traceMs)),
            ("main待ち", samples.map(\.mainWaitMs)),
            ("仕上げ", samples.map(\.applyMs))
        ]
        let phaseText = phases.map { name, values in
            "\(name)=\(rounded(percentile(values, 0.5)))/\(rounded(percentile(values, 0.9)))/\(rounded(values.max() ?? 0))"
        }.joined(separator: " ")
        return "n=\(samples.count) 読み平均=\(String(format: "%.1f", averageLength))字 "
            + "最長=\(Int(lengths.max() ?? 0))字 [中央/90%/最大 ms] \(phaseText)"
    }

    // 近い順位の値(0.5 = 中央値)
    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let sorted = values.sorted()
        let rank = Int((Double(sorted.count) * fraction).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private static func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
