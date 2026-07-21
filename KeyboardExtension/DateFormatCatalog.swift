import Foundation

// 日付書式のトークン(内部表現):
//   aaaa=年 / m=月 / mm=月(0埋め) / j=日 / jj=日(0埋め) / jjj=曜日略称 / jjjj=曜日フルネーム
// 月名/曜日名は方式(日本/フランス/英国/米国)で差し替える。方式はコンテナー設定で選び、
// ドラムの選択肢(バリアント一覧)を切り替える。今回は日本式を実装。
enum DateFormatStyle: String, CaseIterable {
    case japanese
    case french
    case british
    case american
}

enum DateFormatCatalog {
    // 日本式の書式バリアント(内部書式)。ドラムにはサンプル日付でレンダリングして表示する。
    static let japaneseVariants: [String] = [
        "m月j日",
        "m月j日(jjj)",
        "m月j日jjjj",
        "mm月jj日",
        "mm月jj日(jjj)",
        "mm月jj日jjjj",
        "aaaa年m月j日",
        "aaaa年m月j日 (jjj)",
        "aaaa年m月j日 jjjj",
        "aaaa年mm月jj日",
        "aaaa年mm月jj日 (jjj)",
        "aaaa年mm月jj日 jjjj"
    ]

    // 曜日は Calendar の weekday(1=日曜)を 0 起点に直した index で引く。
    static let japaneseWeekdayShort = ["日", "月", "火", "水", "木", "金", "土"]
    static let japaneseWeekdayFull = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
    // mmm(月名を名前で表記)用。日本式は和風月名(index=月-1)。
    static let japaneseMonthNames = [
        "睦月", "如月", "弥生", "卯月", "皐月", "水無月",
        "文月", "葉月", "長月", "神無月", "霜月", "師走"
    ]

    static func variants(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese:
            return japaneseVariants
        case .french, .british, .american:
            // 他方式は後続で実装。暫定で日本式を返す。
            return japaneseVariants
        }
    }

    // ドラム表示用のサンプル日付: 2026年3月4日(水)。1桁の月/日で m/mm・j/jj の差が見えるようにする。
    static func sampleRendered(template: String, style: DateFormatStyle) -> String {
        render(template: template, style: style, year: 2026, month: 3, day: 4, weekdayIndex: 3)
    }

    // 内部書式をレンダリングする。トークンは最長一致で置換し、その他の文字は素通し。
    static func render(
        template: String,
        style: DateFormatStyle,
        year: Int,
        month: Int,
        day: Int,
        weekdayIndex: Int
    ) -> String {
        let short = weekdayShort(for: style)
        let full = weekdayFull(for: style)
        let monthNames = monthNames(for: style)
        let safeIndex = max(0, min(6, weekdayIndex))
        let safeMonthIndex = max(0, min(11, month - 1))

        let characters = Array(template)
        var output = ""
        var index = 0
        while index < characters.count {
            if matches(characters, at: index, token: "aaaa") {
                output += String(year)
                index += 4
            } else if matches(characters, at: index, token: "jjjj") {
                output += full[safeIndex]
                index += 4
            } else if matches(characters, at: index, token: "jjj") {
                output += short[safeIndex]
                index += 3
            } else if matches(characters, at: index, token: "mmm") {
                output += monthNames[safeMonthIndex]
                index += 3
            } else if matches(characters, at: index, token: "mm") {
                output += String(format: "%02d", month)
                index += 2
            } else if matches(characters, at: index, token: "jj") {
                output += String(format: "%02d", day)
                index += 2
            } else if characters[index] == "m" {
                output += String(month)
                index += 1
            } else if characters[index] == "j" {
                output += String(day)
                index += 1
            } else {
                output.append(characters[index])
                index += 1
            }
        }
        return output
    }

    private static func matches(_ characters: [Character], at index: Int, token: String) -> Bool {
        let tokenChars = Array(token)
        guard index + tokenChars.count <= characters.count else {
            return false
        }
        for offset in 0..<tokenChars.count where characters[index + offset] != tokenChars[offset] {
            return false
        }
        return true
    }

    private static func weekdayShort(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese, .french, .british, .american:
            return japaneseWeekdayShort
        }
    }

    private static func weekdayFull(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese, .french, .british, .american:
            return japaneseWeekdayFull
        }
    }

    // 月名(mmm 用)。仏/英は各方式実装時に janvier/July 等へ差し替える。
    private static func monthNames(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese, .french, .british, .american:
            return japaneseMonthNames
        }
    }
}
