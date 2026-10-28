import Foundation
import Observation

// 書式化数値の書式設定(共有 UserDefaults から読む値の写し)。
// 以前はビューの計算プロパティが描画のたびに 1 項目ずつ読んでいた。読む頻度は変えず、使う所で毎回 load する
struct FormattedNumberFormatSettings: Equatable {
    // 千の位区切り文字(既定=空白)。sep_mil オン時に3桁ごとに挿入。
    var thousandsSeparator: String
    // 小数点区切り文字(既定=".")。小数点キーの表示/挿入に反映。
    var decimalSeparator: String
    // que quatre: オンなら4桁の数値にも千区切りを付ける(オフは4桁を例外にする)。
    var groupsFourDigits: Bool
    // 単位の積の記号。内部は U+00B7(中点)で保持し、表示/確定時にこの設定へ変換する。
    var unitProductSeparator: String
    // リットルの記号。内部は常に大文字 L で保持し、表示/確定時にこの設定へ変換する。
    // 既定は小文字 l(SI が1879年から用いる記号)。
    var litreSymbol: String
    var degreeStyle: DegreeSymbolStyle
    // 方式(日本/仏/英/米)はコンテナー設定で選ぶ。
    var dateStyle: DateFormatStyle

    static func load(from defaults: UserDefaults?) -> FormattedNumberFormatSettings {
        let thousandsSeparator: String
        switch defaults?.string(forKey: KeyboardViewController.SharedDefaultsKeys.numberThousandsSeparator) {
        case "comma": thousandsSeparator = ","
        case "dot": thousandsSeparator = "."
        default: thousandsSeparator = " "
        }

        let unitProductSeparator: String
        switch defaults?.string(forKey: KeyboardViewController.SharedDefaultsKeys.numberUnitProductSeparator) {
        case "dotOperator": unitProductSeparator = "\u{22C5}"
        case "space": unitProductSeparator = " "
        default: unitProductSeparator = "\u{00B7}"
        }

        let litreSymbol: String
        switch defaults?.string(forKey: KeyboardViewController.SharedDefaultsKeys.numberLitreSymbol) {
        case "capital": litreSymbol = "L"
        case "script": litreSymbol = "\u{2113}"
        default: litreSymbol = "l"
        }

        let dateStyleRaw = defaults?
            .string(forKey: KeyboardViewController.SharedDefaultsKeys.dateFormatStyle) ?? ""

        return FormattedNumberFormatSettings(
            thousandsSeparator: thousandsSeparator,
            decimalSeparator: defaults?.string(forKey: KeyboardViewController.SharedDefaultsKeys.numberDecimalSeparator) == "comma" ? "," : ".",
            groupsFourDigits: defaults?.bool(forKey: KeyboardViewController.SharedDefaultsKeys.numberGroupFourDigits) ?? false,
            unitProductSeparator: unitProductSeparator,
            litreSymbol: litreSymbol,
            degreeStyle: DegreeSymbolStyle(sharedRawValue: defaults?.string(forKey: DegreeSymbolStyle.sharedDefaultsKey)),
            dateStyle: DateFormatStyle(rawValue: dateStyleRaw) ?? .japanese
        )
    }
}

// 書式化数値の整形の規則(純関数)。内部バッファは小数点="."。表示/出力で設定の区切り文字に変換する
enum FormattedNumberFormatting {
    // 桁数は当面8桁で足りるため、数字は8桁で頭打ちにする(符号/小数点は別カウント)。
    static let maxDigits = 8

    // テンキーのトークンをバッファへ足した結果。± は符号の付け外し、"." は 1 回だけ
    static func appendingToken(_ token: String, to buffer: String, maxDigits: Int) -> String {
        var buffer = buffer
        switch token {
        case "±":
            if buffer.hasPrefix("-") {
                buffer.removeFirst()
            } else {
                buffer = "-" + buffer
            }
        case ".":
            if !buffer.contains(".") {
                buffer.append(token)
            }
        default:
            let digitCount = buffer.filter { $0.isNumber }.count
            guard digitCount < maxDigits else {
                return buffer
            }
            buffer.append(token)
        }
        return buffer
    }

    // バッファ(素の数字文字列)を表示用に整形する。3桁区切りは sep_mil(groupingEnabled)
    // 連動、区切り文字と小数点はコンテナー設定に従う。
    static func displayString(
        buffer: String,
        groupingEnabled: Bool,
        settings: FormattedNumberFormatSettings
    ) -> String {
        var body = buffer
        let isNegative = body.hasPrefix("-")
        if isNegative {
            body.removeFirst()
        }

        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerText = parts.isEmpty ? "" : String(parts[0])
        let hasDecimalPoint = body.contains(".")
        let fractionText = parts.count > 1 ? String(parts[1]) : ""

        let groupedInteger = groupingEnabled
            ? groupedIntegerString(integerText, settings: settings)
            : integerText

        var result = groupedInteger
        if hasDecimalPoint {
            result += settings.decimalSeparator + fractionText
        }
        return (isNegative ? "-" : "") + result
    }

    // 整数部に3桁ごとの区切り文字を挿入する。que quatre オフのときは4桁を例外(5桁以上のみ区切る)。
    static func groupedIntegerString(_ digits: String, settings: FormattedNumberFormatSettings) -> String {
        let threshold = settings.groupsFourDigits ? 3 : 4
        guard digits.count > threshold else {
            return digits
        }
        let separator = settings.thousandsSeparator
        var grouped = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 {
                grouped.append(separator)
            }
            grouped.append(character)
        }
        return String(grouped.reversed())
    }

    // 内部保持の記号を、設定に合わせた表示/確定用の記号にする。
    // ・中点(U+00B7)→ 積の記号設定
    // ・大文字 L → リットルの記号設定(L を含む単位はリットルだけなので単純置換で安全。
    //   小文字 l は mol・lm・lx 等と衝突するため内部保持には使わない)
    static func displayUnitSymbol(_ symbol: String, settings: FormattedNumberFormatSettings) -> String {
        var result = symbol
        let separator = settings.unitProductSeparator
        if separator != "\u{00B7}" {
            result = result.replacingOccurrences(of: "\u{00B7}", with: separator)
        }
        let litre = settings.litreSymbol
        if litre != "L" {
            result = result.replacingOccurrences(of: "L", with: litre)
        }
        // 度記号(内部は SI 形 °C)→ 設定 degreeSymbol の字形(°C / ℃)
        result = settings.degreeStyle.styled(result)
        return result
    }

    // 数値と単位/記号の連結。金額は前後スイッチ(currencySymbolBefore)に従う。
    // 他カテゴリーの単位は後置(1,000N)。単位なしは数値のみ。
    static func join(
        number: String,
        unit: String,
        category: FormattedNumberCategory,
        currencySymbolBefore: Bool,
        unitSpacing: Bool
    ) -> String {
        guard !unit.isEmpty else {
            return number
        }
        if category == .currency {
            if currencySymbolBefore {
                // 通貨記号が前のときは負号を記号の前に出す(¥-100 ではなく -¥100)。
                if number.hasPrefix("-") {
                    return "-" + unit + String(number.dropFirst())
                }
                return unit + number
            }
            return number + unit
        }
        // 単位3カテゴリー: 空白スイッチが入っていれば数値と単位の間に空白を入れる。
        return unitSpacing ? number + " " + unit : number + unit
    }

    // 選択中の書式が現方式のバリアントに無ければ先頭にフォールバックする。
    static func effectiveDateTemplate(_ template: String, style: DateFormatStyle) -> String {
        let variants = DateFormatCatalog.variants(for: style)
        if variants.contains(template) {
            return template
        }
        return variants.first ?? template
    }

    // 日付を書式でレンダリングした文字列。template は effectiveDateTemplate を通したものを渡す
    static func renderedDate(
        _ date: Date,
        template: String,
        style: DateFormatStyle,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekdayIndex = (components.weekday ?? 1) - 1
        return DateFormatCatalog.render(
            template: template,
            style: style,
            year: components.year ?? 2026,
            month: components.month ?? 1,
            day: components.day ?? 1,
            weekdayIndex: weekdayIndex
        )
    }
}

// 書式化数値の入力の状態(バッファ・カテゴリー・単位/接頭辞の選択・区切りと前後と空白のスイッチ・日付と書式)。
// 以前は KeyboardRootView の @State だったものを、配列(iPhone/iPad)をまたいで使えるように外へ出した。
// 持ち主はビュー木の根(@State で持つ)。クロージャーと描画設定は持たない。
// 前回の選択の保存先は今どおり FormattedNumberPreferences(App Group の共有 UserDefaults)
@Observable
@MainActor
final class FormattedNumberState {
    var buffer: String = ""
    var selectedCategory: FormattedNumberCategory = FormattedNumberPreferences.lastCategory()
    var groupingEnabled: Bool = true
    var unitSelection: [Int: String] = FormattedNumberPreferences.loadUnitSelection()
    // 接頭辞(補助単位)はSI単位系カテゴリーごとに独立保持。
    var prefixSelection: [Int: String] = FormattedNumberPreferences.loadPrefixSelection()
    // 金額カテゴリー: 通貨記号を数値の前に付けるか(既定は選択通貨の慣習に追従、スイッチで反転可)。
    var currencySymbolBefore: Bool = FormattedNumberPreferences.lastCurrencySymbolBefore()
    // 単位3カテゴリー: 数値と単位の間に空白を入れるか(既定なし)。
    var unitSpacing: Bool = FormattedNumberPreferences.lastUnitSpacing()
    var date: Date = Date()
    var dateFormatTemplate: String = DateFormatCatalog.japaneseVariants.first ?? "m月j日"

    init() {}

    // テンキーからの数字/記号入力はホストへ流さず、ローカルバッファに溜める
    func appendToken(_ token: String) {
        let next = FormattedNumberFormatting.appendingToken(
            token,
            to: buffer,
            maxDigits: FormattedNumberFormatting.maxDigits
        )
        if next != buffer {
            buffer = next
        }
    }

    func deleteBackward() {
        guard !buffer.isEmpty else {
            return
        }
        buffer.removeLast()
    }

    func resetBuffer() {
        buffer = ""
    }

    // 現在カテゴリーで選択中の基本記号(接頭辞なし)。未選択時は先頭。単位なしは空文字。
    var selectedBaseSymbol: String {
        let units = SIUnitCatalog.units(for: selectedCategory)
        guard !units.isEmpty else {
            return ""
        }
        if let selected = unitSelection[selectedCategory.rawValue],
            units.contains(where: { $0.symbol == selected }) {
            return selected
        }
        return units.first?.symbol ?? ""
    }

    var selectedPrefix: String {
        prefixSelection[selectedCategory.rawValue] ?? ""
    }

    // 出力用の単位記号。SI単位系(基本/組立/固有)は接頭辞ドラムの選択を前置する(k+g=kg, k+N=kN 等)。
    func currentUnitSymbol(settings: FormattedNumberFormatSettings) -> String {
        let base = selectedBaseSymbol
        guard !base.isEmpty else {
            return ""
        }
        if selectedCategory.usesSIPrefix {
            let prefix = prefixSelection[selectedCategory.rawValue] ?? ""
            return FormattedNumberFormatting.displayUnitSymbol(prefix + base, settings: settings)
        }
        return base
    }

    func selectUnit(_ symbol: String) {
        unitSelection[selectedCategory.rawValue] = symbol
        FormattedNumberPreferences.saveUnit(symbol, for: selectedCategory)
        // 通貨を変えたら、その通貨の慣習(前/後)に前後スイッチを合わせる。
        if selectedCategory == .currency {
            currencySymbolBefore = SIUnitCatalog.currencySymbolBeforeAmount(symbol)
        }
    }

    func selectPrefix(_ symbol: String) {
        prefixSelection[selectedCategory.rawValue] = symbol
        FormattedNumberPreferences.savePrefix(symbol, for: selectedCategory)
    }

    // カテゴリー選択(前回値を保存する)。戻り値=カレンダーと単位の境をまたいだか(高さ差の反映が要る)
    func selectCategory(_ category: FormattedNumberCategory) -> Bool {
        let previous = selectedCategory
        selectedCategory = category
        FormattedNumberPreferences.saveCategory(category)
        // 金額に切り替えたら、選択中通貨の慣習に前後スイッチを合わせる。
        if category == .currency {
            currencySymbolBefore =
                SIUnitCatalog.currencySymbolBeforeAmount(selectedBaseSymbol)
        }
        return (previous == .calendar) != (category == .calendar)
    }

    func toggleUnitSpacing() {
        unitSpacing.toggle()
        FormattedNumberPreferences.saveUnitSpacing(unitSpacing)
    }

    func toggleGrouping() {
        groupingEnabled.toggle()
    }

    func toggleCurrencySymbolBefore() {
        currencySymbolBefore.toggle()
    }

    func effectiveDateTemplate(settings: FormattedNumberFormatSettings) -> String {
        FormattedNumberFormatting.effectiveDateTemplate(dateFormatTemplate, style: settings.dateStyle)
    }

    // 選択中のカレンダー日付を選択書式でレンダリングした文字列。
    func renderedDate(settings: FormattedNumberFormatSettings) -> String {
        FormattedNumberFormatting.renderedDate(
            date,
            template: effectiveDateTemplate(settings: settings),
            style: settings.dateStyle,
            calendar: Calendar.current
        )
    }

    func displayString(settings: FormattedNumberFormatSettings) -> String {
        FormattedNumberFormatting.displayString(
            buffer: buffer,
            groupingEnabled: groupingEnabled,
            settings: settings
        )
    }

    private func join(number: String, settings: FormattedNumberFormatSettings) -> String {
        FormattedNumberFormatting.join(
            number: number,
            unit: currentUnitSymbol(settings: settings),
            category: selectedCategory,
            currencySymbolBefore: currencySymbolBefore,
            unitSpacing: unitSpacing
        )
    }

    // 確定/プレビューに使う最終文字列。カレンダーはレンダリング日付、単位系は数値+単位。
    func outputString(settings: FormattedNumberFormatSettings) -> String {
        if selectedCategory == .calendar {
            return renderedDate(settings: settings)
        }
        return join(number: displayString(settings: settings), settings: settings)
    }

    // プレビュー。数値が空なら "0" を出す
    func previewString(settings: FormattedNumberFormatSettings) -> String {
        if selectedCategory == .calendar {
            return renderedDate(settings: settings)
        }
        let number = buffer.isEmpty ? "0" : displayString(settings: settings)
        return join(number: number, settings: settings)
    }

    // 確定する文字列を取り出してバッファを空にする。
    // カレンダーは日付ホイールから常に確定できる。単位系は数値未入力なら nil(何も確定しない)
    func takeCommitText(settings: FormattedNumberFormatSettings) -> String? {
        if selectedCategory != .calendar, buffer.isEmpty {
            return nil
        }
        let text = outputString(settings: settings)
        buffer = ""
        return text
    }
}
