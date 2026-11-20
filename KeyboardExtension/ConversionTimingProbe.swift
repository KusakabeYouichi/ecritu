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
    // 連文節の変換の内訳(段の名前ごとの ms。3857)。実機では Mac ほど連文節が縮まず、どの段が時間を使っているかを見るため
    var multiPhaseMs: [String: Double] = [:]
}

// 連文節の変換の段ごとの時間を集める(3857)。変換は 1 本の直列のキューで動くので、打鍵ごとに begin して end で受け取る。
// 同じ打鍵の中で連文節が複数回走れば(短い読みの再試行など)足し合わせる
enum ConversionPhaseRecorder {
    static let phaseNames = ["供給", "表・前計算", "DP", "代替経路", "変種", "結果"]
    private static let lock = NSLock()
    private static var lastMarkAt: CFAbsoluteTime = 0
    private static var durations: [String: Double] = [:]

    static func begin() {
        lock.lock(); defer { lock.unlock() }
        durations.removeAll(keepingCapacity: true)
        isActive = false
        lastMarkAt = CFAbsoluteTimeGetCurrent()
    }

    // 段の終わりで呼ばれる(名前はその段)。供給 は連文節の始まりからの時間になるよう、連文節を呼ぶ直前に restart する
    static func mark(_ name: String) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock(); defer { lock.unlock() }
        // 単文節の変換の中から呼ばれる連文節(地名+さん の並べ替え、数字の後ろの末尾)は数えない
        guard isActive else { return }
        durations[name, default: 0] += (now - lastMarkAt) * 1000
        lastMarkAt = now
    }

    private static var isActive = false

    // 打鍵の本体の連文節を呼ぶ直前
    static func restart() {
        lock.lock(); defer { lock.unlock() }
        isActive = true
        lastMarkAt = CFAbsoluteTimeGetCurrent()
    }

    // 打鍵の本体の連文節が終わった直後
    static func pause() {
        lock.lock(); defer { lock.unlock() }
        isActive = false
    }

    static func end() -> [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return durations
    }
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
        // 連文節の内訳(記録のある打鍵だけ。中央/90%)
        let multiPhaseText = ConversionPhaseRecorder.phaseNames.compactMap { name -> String? in
            let values = samples.compactMap { $0.multiPhaseMs[name] }
            guard !values.isEmpty else { return nil }
            return "\(name)=\(rounded(percentile(values, 0.5)))/\(rounded(percentile(values, 0.9)))"
        }.joined(separator: " ")
        return "n=\(samples.count) 読み平均=\(String(format: "%.1f", averageLength))字 "
            + "最長=\(Int(lengths.max() ?? 0))字 [中央/90%/最大 ms] \(phaseText)"
            + (multiPhaseText.isEmpty ? "" : " 連文節の内訳[中央/90%] \(multiPhaseText)")
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
