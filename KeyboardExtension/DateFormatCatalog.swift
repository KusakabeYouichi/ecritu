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

    // 英語(英国/米国共通)の名称。
    static let englishWeekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let englishWeekdayFull = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let englishMonthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    // フランス語の名称。
    static let frenchWeekdayShort = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    static let frenchWeekdayFull = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    static let frenchMonthNames = [
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre"
    ]

    // 英国式(日→月→年 / 区切り「/」/ 月頭大文字 / 年前カンマなし / 序数 jo=4th)。
    static let britishVariants: [String] = [
        "j/m/aaaa",
        "jj/mm/aaaa",
        "j mmm aaaa",
        "jo mmm aaaa",
        "jjjj, j mmm aaaa",
        "j mmm",
        "jo mmm"
    ]

    // 米国式(月→日→年 / 区切り「/」/ 月頭大文字 / 年前カンマあり / 序数 jo=4th)。
    static let americanVariants: [String] = [
        "m/j/aaaa",
        "mm/jj/aaaa",
        "mmm j, aaaa",
        "mmm jo, aaaa",
        "jjjj, mmm j, aaaa",
        "mmm j",
        "mmm jo"
    ]

    // フランス式(日→月→年 / 区切り「/」または「.」/ 月頭小文字 / 年前カンマなし / 序数 jo=1のみ1er)。
    static let frenchVariants: [String] = [
        "j/mm/aaaa",
        "jj/mm/aaaa",
        "jj.mm.aaaa",
        "j mmm aaaa",
        "jo mmm aaaa",
        "jjjj j mmm aaaa",
        "j mmm"
    ]

    // 自前カレンダーグリッドの曜日表記の言語(コンテナー設定)。
    enum CalendarWeekdayLanguage: String {
        case japanese
        case english
        case french
    }

    // 日曜始まりの並びの曜日略称(週開始が月曜のときは呼び出し側で並べ替える)。
    static func calendarWeekdayLabels(_ language: CalendarWeekdayLanguage) -> [String] {
        switch language {
        case .japanese:
            return japaneseWeekdayShort
        case .english:
            return englishWeekdayShort
        case .french:
            return frenchWeekdayShort
        }
    }

    // カレンダー見出し(年月)。
    static func calendarMonthTitle(_ language: CalendarWeekdayLanguage, year: Int, month: Int) -> String {
        let monthIndex = max(1, min(12, month)) - 1
        switch language {
        case .japanese:
            return "\(year)年\(monthIndex + 1)月"
        case .english:
            return "\(englishMonthNames[monthIndex]) \(year)"
        case .french:
            return "\(frenchMonthNames[monthIndex]) \(year)"
        }
    }

    static func variants(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese:
            return japaneseVariants
        case .french:
            return frenchVariants
        case .british:
            return britishVariants
        case .american:
            return americanVariants
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
            } else if matches(characters, at: index, token: "jo") {
                output += ordinalDay(day, style: style)
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
        case .japanese:
            return japaneseWeekdayShort
        case .british, .american:
            return englishWeekdayShort
        case .french:
            return frenchWeekdayShort
        }
    }

    private static func weekdayFull(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese:
            return japaneseWeekdayFull
        case .british, .american:
            return englishWeekdayFull
        case .french:
            return frenchWeekdayFull
        }
    }

    private static func monthNames(for style: DateFormatStyle) -> [String] {
        switch style {
        case .japanese:
            return japaneseMonthNames
        case .british, .american:
            return englishMonthNames
        case .french:
            return frenchMonthNames
        }
    }

    // jo(序数付きの日)。英語=1st/2nd/3rd/4th…(11-13はth)、フランス語=1のみ「1er」他は数字、
    // 日本語=数字のまま。
    private static func ordinalDay(_ day: Int, style: DateFormatStyle) -> String {
        switch style {
        case .british, .american:
            let suffix: String
            if (11...13).contains(day % 100) {
                suffix = "th"
            } else {
                switch day % 10 {
                case 1: suffix = "st"
                case 2: suffix = "nd"
                case 3: suffix = "rd"
                default: suffix = "th"
                }
            }
            return "\(day)\(suffix)"
        case .french:
            return day == 1 ? "1er" : String(day)
        case .japanese:
            return String(day)
        }
    }
}
