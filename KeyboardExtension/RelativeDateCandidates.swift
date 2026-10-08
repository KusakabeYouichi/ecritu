import Foundation

// あさって/らいげつ/ことし 等の相対の日付語を、今日を起点にした実際の日付へ展開した候補(3445)。
// Apple 純正の日本語入力と同じ趣旨の機能。書式はコンテナーの「カレンダー > 日付書式」の方式
// (日本式/フランス式/英国式/米国式)に合わせ、日は DateFormatCatalog のドラムと同じ書式の一覧を使う。
// 日付は日ごとに変わるので学習の対象にしない(学習すると翌日以降に古い日付が先頭に出続ける)。
enum RelativeDateCandidates {
    enum Unit {
        case day
        case month
        case year
    }

    struct Offset {
        let unit: Unit
        let value: Int
    }

    // 候補の差し込み位置(0 起点)。純正と同じく、語の表記 2 つの直後に置く。
    static let insertionIndex = 2

    static let offsetsByReading: [String: Offset] = [
        "さきおととい": Offset(unit: .day, value: -3),
        "おととい": Offset(unit: .day, value: -2),
        "いっさくじつ": Offset(unit: .day, value: -2),
        "きのう": Offset(unit: .day, value: -1),
        "さくじつ": Offset(unit: .day, value: -1),
        "きょう": Offset(unit: .day, value: 0),
        "ほんじつ": Offset(unit: .day, value: 0),
        "あした": Offset(unit: .day, value: 1),
        "あす": Offset(unit: .day, value: 1),
        "みょうにち": Offset(unit: .day, value: 1),
        "あさって": Offset(unit: .day, value: 2),
        "みょうごにち": Offset(unit: .day, value: 2),
        "しあさって": Offset(unit: .day, value: 3),
        "せんせんげつ": Offset(unit: .month, value: -2),
        "せんげつ": Offset(unit: .month, value: -1),
        "こんげつ": Offset(unit: .month, value: 0),
        "らいげつ": Offset(unit: .month, value: 1),
        "さらいげつ": Offset(unit: .month, value: 2),
        "おととし": Offset(unit: .year, value: -2),
        "きょねん": Offset(unit: .year, value: -1),
        "さくねん": Offset(unit: .year, value: -1),
        "ことし": Offset(unit: .year, value: 0),
        "こんねん": Offset(unit: .year, value: 0),
        "らいねん": Offset(unit: .year, value: 1),
        "みょうねん": Offset(unit: .year, value: 1),
        "さらいねん": Offset(unit: .year, value: 2)
    ]

    // 月・年はドラムに書式が無いので、方式ごとにここで持つ(トークンは DateFormatCatalog と同じ)。
    static func monthTemplates(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese:
            return ["m月", "aaaa年m月"]
        case .french, .british, .american:
            return ["mmm", "mmm aaaa", "m/aaaa"]
        }
    }

    static func yearTemplates(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese:
            return ["aaaa年"]
        case .french, .british, .american:
            return ["aaaa"]
        }
    }

    // 日はドラムの書式一覧から前ゼロの書式(mm/jj)を除いたもの+曜日だけ(土曜日 / Saturday / samedi)。
    static func dayTemplates(for style: DateFormatStyle) -> [String] {
        DateFormatCatalog.variants(for: style).filter { !isZeroPadded($0) } + ["jjjj"]
    }

    // 月名(mmm)・曜日(jjj/jjjj)を除いて mm か jj が残れば前ゼロの書式
    static func isZeroPadded(_ template: String) -> Bool {
        let stripped = template
            .replacingOccurrences(of: "mmm", with: "_")
            .replacingOccurrences(of: "jjjj", with: "_")
            .replacingOccurrences(of: "jjj", with: "_")
        return stripped.contains("mm") || stripped.contains("jj")
    }

    static func candidates(
        for reading: String,
        style: DateFormatStyle,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [String] {
        guard let offset = offsetsByReading[reading] else {
            return []
        }

        let component: Calendar.Component
        let templates: [String]
        switch offset.unit {
        case .day:
            component = .day
            templates = dayTemplates(for: style)
        case .month:
            component = .month
            templates = monthTemplates(for: style)
        case .year:
            component = .year
            templates = yearTemplates(for: style)
        }

        guard let target = calendar.date(byAdding: component, value: offset.value, to: now) else {
            return []
        }
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: target)

        var seen = Set<String>()
        var rendered: [String] = []
        for template in templates {
            let text = DateFormatCatalog.render(
                template: template,
                style: style,
                year: parts.year ?? 2026,
                month: parts.month ?? 1,
                day: parts.day ?? 1,
                weekdayIndex: (parts.weekday ?? 1) - 1
            )
            if seen.insert(text).inserted {
                rendered.append(text)
            }
        }
        return rendered
    }

    // 表示候補へ日付を差し込む。既に同じ文字列があればそちらを除いてから入れる(重複させない)。
    static func inserting(
        into candidates: [String],
        reading: String,
        style: DateFormatStyle,
        now: Date = Date()
    ) -> [String] {
        let dates = Self.candidates(for: reading, style: style, now: now)
        guard !dates.isEmpty else {
            return candidates
        }
        let dateSet = Set(dates)
        var result = candidates.filter { !dateSet.contains($0) }
        result.insert(contentsOf: dates, at: min(insertionIndex, result.count))
        return result
    }

    // 学習の除外判定。方式を後から変えても漏れないよう、全方式で照合する。
    static func isGeneratedCandidate(_ candidate: String, reading rawReading: String, now: Date = Date()) -> Bool {
        let reading = KanaTextNormalizer.normalizedReading(rawReading)
        guard offsetsByReading[reading] != nil else {
            return false
        }
        return DateFormatStyle.allCases.contains { style in
            candidates(for: reading, style: style, now: now).contains(candidate)
        }
    }
}
