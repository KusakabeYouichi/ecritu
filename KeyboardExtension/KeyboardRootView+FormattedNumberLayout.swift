import SwiftUI

// 書式化数値入力モードのカテゴリー(当面4種)。単位ドラム/カレンダーの切替に使う。
// rawValue は設定永続化に備えて歴史的値を明示する(絵文字カテゴリーと同方針)。
enum FormattedNumberCategory: Int, CaseIterable, Identifiable {
    // 宣言順が下段バーの並び順。rawValue は永続化用の歴史的値(calendar=3 を保持しつつ
    // currency を siNamed とカレンダーの間に差し込むため 4 を採番)。
    case siBase = 0
    case siDerived = 1
    case siNamed = 2
    case currency = 4
    case calendar = 3

    var id: Int { rawValue }

    // 下段カテゴリーバーの短ラベル(代表記号でカテゴリーを示唆)。
    var shortLabel: String {
        switch self {
        case .siBase:
            return "kg"
        case .siDerived:
            return "m/s²"
        case .siNamed:
            return "N"
        case .currency:
            return "¥"
        case .calendar:
            return "📅"
        }
    }

    // ヘッダー等で使う名称。
    var displayName: String {
        switch self {
        case .siBase:
            return "SI基本単位"
        case .siDerived:
            return "SI組立単位"
        case .siNamed:
            return "固有の名称を持つSI組立単位"
        case .currency:
            return "金額"
        case .calendar:
            return "カレンダー"
        }
    }
}

// 書式化数値モードの「前回の選択」を App Group の共有 UserDefaults に保存/復元する。
// 次回モードを開いたとき、前回のカテゴリー・単位(カテゴリー別)・接頭辞が選択済みで開く。
enum FormattedNumberPreferences {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: KeyboardViewController.SharedDefaultsKeys.appGroupID)
    }

    private static let categoryKey = "formattedNumber.lastCategory"
    private static let prefixKey = "formattedNumber.lastPrefix"
    private static func unitKey(_ categoryRawValue: Int) -> String {
        "formattedNumber.lastUnit.\(categoryRawValue)"
    }

    static func lastCategory() -> FormattedNumberCategory {
        guard let defaults,
            let category = FormattedNumberCategory(rawValue: defaults.integer(forKey: categoryKey)) else {
            return .siBase
        }
        return category
    }

    static func saveCategory(_ category: FormattedNumberCategory) {
        defaults?.set(category.rawValue, forKey: categoryKey)
    }

    static func lastPrefixSymbol() -> String {
        defaults?.string(forKey: prefixKey) ?? ""
    }

    static func savePrefixSymbol(_ symbol: String) {
        defaults?.set(symbol, forKey: prefixKey)
    }

    static func loadUnitSelection() -> [Int: String] {
        guard let defaults else {
            return [:]
        }
        var selection: [Int: String] = [:]
        for category in FormattedNumberCategory.allCases {
            if let symbol = defaults.string(forKey: unitKey(category.rawValue)) {
                selection[category.rawValue] = symbol
            }
        }
        return selection
    }

    static func saveUnit(_ symbol: String, for category: FormattedNumberCategory) {
        defaults?.set(symbol, forKey: unitKey(category.rawValue))
    }

    // 起動時の通貨記号前後位置の初期値。前回選択した通貨(なければ先頭)の既定に従う。
    // これをしないと再読込時に @State 既定(前)のままになり、ユーロ等(後ろが既定)がずれる。
    static func lastCurrencySymbolBefore() -> Bool {
        let symbol = loadUnitSelection()[FormattedNumberCategory.currency.rawValue]
            ?? SIUnitCatalog.currencies.first?.symbol
            ?? ""
        return SIUnitCatalog.currencySymbolBeforeAmount(symbol)
    }

    private static let unitSpacingKey = "formattedNumber.unitSpacing"

    // 数値と単位の間の空白の有無(単位3カテゴリー用)。既定は空白なし。
    static func lastUnitSpacing() -> Bool {
        defaults?.bool(forKey: unitSpacingKey) ?? false
    }

    static func saveUnitSpacing(_ enabled: Bool) {
        defaults?.set(enabled, forKey: unitSpacingKey)
    }
}

// P1: モードの外枠(テンキー / 右エリア=プレビュー+単位ドラム占位+確定 / 下段バー)。
// キーボードは横長で縦の余白が乏しいため、上段は高さいっぱいに可変分割し、下段バーだけ
// 固定1段にする(絵文字画面と同じ縦配分)。単位ドラム・書式化・カレンダーは後続フェーズ。
extension KeyboardRootView {
    var formattedNumberKeyboardView: some View {
        // 記号/絵文字/顔文字と同じ「固定高さクラスタ」構造にして下段バーの位置・高さを完全一致させる
        // (filling+Spacer だと実機でバーが約8pt上にずれる)。書式化数値はヘッダーを畳んでいる分
        // (candidateHeaderHeight)を上部エリアに回してカレンダー/テンキーの縦余裕を確保する。
        // rootView が下端寄せするので、クラスタ末尾のバーは基準モードと同じ最下部に落ちる。
        VStack(spacing: keyboardRowSpacing) {
            Group {
                if selectedFormattedNumberCategory == .calendar {
                    formattedNumberCalendarTopArea
                } else {
                    formattedNumberUnitTopArea
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: formattedNumberTopContentHeight, alignment: .top)
            .clipped()

            formattedNumberBottomBar(height: mainFlickKeyHeight)
                .frame(height: mainFlickKeyHeight)
        }
        .frame(height: formattedNumberClusterHeight, alignment: .top)
    }

    // 記号/絵文字と同じ基準クラスタ高さ+畳んだヘッダー分の余白(上部エリアに回す)。
    private var formattedNumberClusterHeight: CGFloat {
        fourRowAlignedClusterHeight + candidateHeaderHeight
    }

    private var formattedNumberTopContentHeight: CGFloat {
        formattedNumberClusterHeight - mainFlickKeyHeight - keyboardRowSpacing
    }

    // 単位/金額カテゴリー: 縦画面と横画面でレイアウトを明確に分岐(横の変更が縦に影響しない)。
    @ViewBuilder
    private var formattedNumberUnitTopArea: some View {
        if isLandscapeLayout {
            formattedNumberUnitTopAreaLandscape
        } else {
            formattedNumberUnitTopAreaPortrait
        }
    }

    // 縦画面: テンキー(4段)+右エリア(プレビュー/ドラム/区切り・確定)。
    // 左右どちらをテンキーにするかは landscapeNumberPaneSide 設定に従う(縦画面でも有効)。
    private var formattedNumberUnitTopAreaPortrait: some View {
        HStack(alignment: .top, spacing: keyboardRowSpacing) {
            if landscapeNumberPaneSide == .left {
                formattedNumberTenkey
                    .frame(maxWidth: .infinity)
                formattedNumberRightArea
                    .frame(maxWidth: .infinity)
            } else {
                formattedNumberRightArea
                    .frame(maxWidth: .infinity)
                formattedNumberTenkey
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // 横画面: 左右2ペイン(50:50)。テンキーペイン=1〜9+±/0/. の4列等幅×3段。
    // 表示ペイン=プレビュー+ドラム+(3桁/前後/確定)。左右どちらをテンキーにするかは
    // landscapeNumberPaneSide 設定(数字モードと共通)に従う。
    private var formattedNumberUnitTopAreaLandscape: some View {
        HStack(alignment: .top, spacing: keyboardRowSpacing) {
            if landscapeNumberPaneSide == .left {
                formattedNumberTenkeyPaneLandscape
                    .frame(maxWidth: .infinity)
                formattedNumberDisplayPaneLandscape
                    .frame(maxWidth: .infinity)
            } else {
                formattedNumberDisplayPaneLandscape
                    .frame(maxWidth: .infinity)
                formattedNumberTenkeyPaneLandscape
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // 横画面テンキーの1行高さ(3段が上部エリアに収まる値)。
    private var formattedNumberLandscapeKeyRowHeight: CGFloat {
        max(34, (formattedNumberTopContentHeight - keyboardRowSpacing * 2) / 3)
    }

    private func formattedNumberLandscapeKey(_ token: String) -> some View {
        ActionKeyButton(
            title: formattedNumberKeyTitle(token),
            fontSize: 20,
            action: { appendFormattedNumberToken(token) }
        )
        .frame(maxWidth: .infinity)
        .frame(height: formattedNumberLandscapeKeyRowHeight)
    }

    // テンキーペイン: 4列(1〜9 + ±/0/.)を等幅で3段。0/./± は 1〜9 と同じ幅(ペイン4等分)。
    private var formattedNumberTenkeyPaneLandscape: some View {
        VStack(spacing: keyboardRowSpacing) {
            ForEach([["7", "8", "9", "±"], ["4", "5", "6", "0"], ["1", "2", "3", "."]], id: \.self) { row in
                HStack(spacing: keyboardRowSpacing) {
                    ForEach(row, id: \.self) { token in
                        formattedNumberLandscapeKey(token)
                    }
                }
            }
        }
    }

    // 表示ペイン: 左に操作列(3桁/前後/確定)を縦積みし、右にプレビュー+ドラム(幅を狭める)。
    // 操作列はペインが左右どちらに来ても常に表示欄・ドラムの「左」に置く。
    // ドラムは Color.clear ベースで wheel の高さ伝播を封じ、固定高さで収める。
    private var formattedNumberDisplayPaneLandscape: some View {
        HStack(alignment: .top, spacing: keyboardRowSpacing) {
            VStack(spacing: keyboardRowSpacing) {
                formattedNumberGroupingToggle
                    .frame(maxHeight: .infinity)
                if selectedFormattedNumberCategory == .currency {
                    formattedNumberCurrencyPlacementToggle
                        .frame(maxHeight: .infinity)
                } else {
                    formattedNumberUnitSpacingToggle
                        .frame(maxHeight: .infinity)
                }
                formattedNumberConfirmKey
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 66)

            VStack(spacing: keyboardRowSpacing) {
                formattedNumberPreview
                    .frame(height: 34)
                Color.clear
                    .frame(height: max(46, formattedNumberTopContentHeight - 34 - keyboardRowSpacing))
                    .overlay(formattedNumberUnitSelector)
                    .clipped()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // カレンダーカテゴリー: 縦画面と横画面でレイアウトを明確に分岐する(横の変更が縦に影響しない)。
    @ViewBuilder
    private var formattedNumberCalendarTopArea: some View {
        if isLandscapeLayout {
            formattedNumberCalendarTopAreaLandscape
        } else {
            formattedNumberCalendarTopAreaPortrait
        }
    }

    // 縦画面: カレンダー(ヘッダー上)+操作列(プレビュー/書式/確定)。左右はペイン設定に追従。
    private var formattedNumberCalendarTopAreaPortrait: some View {
        HStack(alignment: .top, spacing: keyboardRowSpacing) {
            if landscapeNumberPaneSide == .left {
                formattedNumberScaledCalendar
                formattedNumberCalendarControlColumnPortrait
            } else {
                formattedNumberCalendarControlColumnPortrait
                formattedNumberScaledCalendar
            }
        }
    }

    private var formattedNumberCalendarControlColumnPortrait: some View {
        VStack(spacing: keyboardRowSpacing) {
            formattedNumberPreview
                .frame(height: 50)
            formattedNumberDateFormatMenu
                .frame(height: 47)
            formattedNumberConfirmKey
                .frame(height: 44)
        }
        .frame(width: 150)
    }

    // 横画面: カレンダーのナビを内側に縦積みしセルを低くして見切れを防ぐ。操作列は反対側。
    // 左右はペイン設定に追従(カレンダーが右ペインならナビは左=内側へ反転)。
    private var formattedNumberCalendarTopAreaLandscape: some View {
        HStack(alignment: .top, spacing: keyboardRowSpacing) {
            if landscapeNumberPaneSide == .left {
                formattedNumberLandscapeCalendarGrid(navigation: .trailing)
                    .frame(maxWidth: .infinity, alignment: .top)
                formattedNumberCalendarControlColumnLandscape
            } else {
                formattedNumberCalendarControlColumnLandscape
                formattedNumberLandscapeCalendarGrid(navigation: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func formattedNumberLandscapeCalendarGrid(
        navigation: FormattedNumberCalendarGridView.NavigationPlacement
    ) -> some View {
        FormattedNumberCalendarGridView(
            selectedDate: $formattedNumberDate,
            weekStartsMonday: formattedNumberCalendarWeekStartsMonday,
            language: formattedNumberCalendarLanguage,
            sundayColor: formattedNumberCalendarSundayColor,
            navigationPlacement: navigation,
            cellHeight: formattedNumberLandscapeCalendarCellHeight,
            columnSpacing: 10
        )
    }

    private var formattedNumberCalendarControlColumnLandscape: some View {
        VStack(spacing: keyboardRowSpacing) {
            formattedNumberPreview
                .frame(height: 40)
            formattedNumberDateFormatMenu
                .frame(height: 40)
            formattedNumberConfirmKey
                .frame(height: 40)
        }
        .frame(width: 300)
    }

    // 横画面カレンダーのセル高さ。上部エリア高さ(クラスタ−バー)に6行+曜日行が収まる値。
    private var formattedNumberLandscapeCalendarCellHeight: CGFloat {
        let available = formattedNumberTopContentHeight
        // 曜日行(約13)+VStack spacing(3)+6行分の行間(5×2=10)を差し引いた残りを6等分。
        let usable = available - 13 - 3 - 10
        return max(15, min(22, usable / 6))
    }

    // 自前の月グリッド(常時表示・コンパクト)。週開始・曜日表記はコンテナー設定から読む。
    private var formattedNumberScaledCalendar: some View {
        FormattedNumberCalendarGridView(
            selectedDate: $formattedNumberDate,
            weekStartsMonday: formattedNumberCalendarWeekStartsMonday,
            language: formattedNumberCalendarLanguage,
            sundayColor: formattedNumberCalendarSundayColor
        )
        // 固定セルの自然高さ(常時6行)。横画面は幅上限を設けて中央寄せ。
        .frame(maxWidth: isLandscapeLayout ? 430 : .infinity, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // 数値書式設定(共有 UserDefaults から直接読む)。
    private var formattedNumberSharedDefaults: UserDefaults? {
        UserDefaults(suiteName: KeyboardViewController.SharedDefaultsKeys.appGroupID)
    }

    // 千の位区切り文字(既定=空白)。sep_mil オン時に3桁ごとに挿入。
    var formattedNumberThousandsSeparator: String {
        switch formattedNumberSharedDefaults?.string(forKey: "numberThousandsSeparator") {
        case "comma": return ","
        case "dot": return "."
        default: return " "
        }
    }

    // 小数点区切り文字(既定=".")。小数点キーの表示/挿入に反映。
    var formattedNumberDecimalSeparator: String {
        formattedNumberSharedDefaults?.string(forKey: "numberDecimalSeparator") == "comma" ? "," : "."
    }

    // que quatre: オンなら4桁の数値にも千区切りを付ける(オフは4桁を例外にする)。
    private var formattedNumberGroupsFourDigits: Bool {
        formattedNumberSharedDefaults?.bool(forKey: "numberGroupFourDigits") ?? false
    }

    // カレンダー設定(共有 UserDefaults から直接読む)。既定は月曜始まり。
    private var formattedNumberCalendarWeekStartsMonday: Bool {
        let raw = UserDefaults(suiteName: KeyboardViewController.SharedDefaultsKeys.appGroupID)?
            .string(forKey: "calendarWeekStart") ?? "monday"
        return raw != "sunday"
    }

    private var formattedNumberCalendarLanguage: DateFormatCatalog.CalendarWeekdayLanguage {
        let raw = UserDefaults(suiteName: KeyboardViewController.SharedDefaultsKeys.appGroupID)?
            .string(forKey: "calendarWeekdayLanguage") ?? ""
        return DateFormatCatalog.CalendarWeekdayLanguage(rawValue: raw) ?? .japanese
    }

    // 日曜列の色(オフ=nil)。DIC は近似値(正確値は要確認)。
    private var formattedNumberCalendarSundayColor: Color? {
        let raw = UserDefaults(suiteName: KeyboardViewController.SharedDefaultsKeys.appGroupID)?
            .string(forKey: "calendarSundayColor") ?? "off"
        switch raw {
        case "bordeaux":
            // bordeaux = rgb(141,17,74)
            return Color(red: 141.0 / 255.0, green: 17.0 / 255.0, blue: 74.0 / 255.0)
        case "bourgogne":
            // bourgogne = rgb(112,23,64)
            return Color(red: 112.0 / 255.0, green: 23.0 / 255.0, blue: 64.0 / 255.0)
        case "dic156":
            // DIC-156 = rgb(241,0,46)
            return Color(red: 241.0 / 255.0, green: 0.0 / 255.0, blue: 46.0 / 255.0)
        case "dicF101":
            // DIC-F101 = #D31C30
            return Color(red: 211.0 / 255.0, green: 28.0 / 255.0, blue: 48.0 / 255.0)
        default:
            return nil
        }
    }

    // 書式プルダウン: 内部書式でなくサンプル日付(3月4日・水)でレンダリングした実例を表示。
    private var formattedNumberDateFormatMenu: some View {
        Picker("", selection: formattedNumberDateTemplateBinding) {
            ForEach(DateFormatCatalog.variants(for: formattedNumberDateStyle), id: \.self) { template in
                Text(DateFormatCatalog.sampleRendered(template: template, style: formattedNumberDateStyle))
                    .tag(template)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardThemePalette.keyBackground)
        )
    }

    // 方式(日本/仏/英/米)はコンテナー設定で選ぶ。共有 UserDefaults から直接読む。
    private var formattedNumberDateStyle: DateFormatStyle {
        let raw = UserDefaults(suiteName: KeyboardViewController.SharedDefaultsKeys.appGroupID)?
            .string(forKey: "dateFormatStyle") ?? ""
        return DateFormatStyle(rawValue: raw) ?? .japanese
    }

    // 選択中の書式が現方式のバリアントに無ければ先頭にフォールバックする。
    private var formattedNumberEffectiveDateTemplate: String {
        let variants = DateFormatCatalog.variants(for: formattedNumberDateStyle)
        if variants.contains(formattedNumberDateFormatTemplate) {
            return formattedNumberDateFormatTemplate
        }
        return variants.first ?? formattedNumberDateFormatTemplate
    }

    private var formattedNumberDateTemplateBinding: Binding<String> {
        Binding(
            get: { formattedNumberEffectiveDateTemplate },
            set: { formattedNumberDateFormatTemplate = $0 }
        )
    }

    // 選択中のカレンダー日付を選択書式でレンダリングした文字列。
    func formattedNumberRenderedDate() -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: formattedNumberDate)
        let weekdayIndex = (components.weekday ?? 1) - 1
        return DateFormatCatalog.render(
            template: formattedNumberEffectiveDateTemplate,
            style: formattedNumberDateStyle,
            year: components.year ?? 2026,
            month: components.month ?? 1,
            day: components.day ?? 1,
            weekdayIndex: weekdayIndex
        )
    }

    // MARK: - テンキー(左側)

    private var formattedNumberTenkeyRows: [[String]] {
        [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"], ["±", "0", "."]]
    }

    // キーの表示文字。小数点キー(内部トークン ".")は設定の小数区切り(. か ,)を表示する。
    private func formattedNumberKeyTitle(_ token: String) -> String {
        token == "." ? formattedNumberDecimalSeparator : token
    }

    private var formattedNumberTenkey: some View {
        VStack(spacing: keyboardRowSpacing) {
            ForEach(Array(formattedNumberTenkeyRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: keyboardRowSpacing) {
                    ForEach(row, id: \.self) { token in
                        ActionKeyButton(
                            title: formattedNumberKeyTitle(token),
                            fontSize: 20,
                            action: { appendFormattedNumberToken(token) }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: formattedNumberTenkeyRowHeight)
                    }
                }
            }
        }
    }

    // テンキー4行の合計高さをカレンダー上部エリア(約183pt)以内に収める行高さ。上位 Group が
    // フィルするので、上部エリアが利用可能高さ以内であれば下段バーは常に最下部に落ちる。
    private var formattedNumberTenkeyRowHeight: CGFloat {
        41
    }

    // 桁数は当面8桁で足りるため、数字は8桁で頭打ちにする(符号/小数点は別カウント)。
    private var formattedNumberMaxDigits: Int { 8 }

    private func appendFormattedNumberToken(_ token: String) {
        switch token {
        case "±":
            toggleFormattedNumberSign()
        case ".":
            if !formattedNumberBuffer.contains(".") {
                appendFormattedNumber(token)
            }
        default:
            let digitCount = formattedNumberBuffer.filter { $0.isNumber }.count
            guard digitCount < formattedNumberMaxDigits else {
                return
            }
            appendFormattedNumber(token)
        }
    }

    private func toggleFormattedNumberSign() {
        if formattedNumberBuffer.hasPrefix("-") {
            formattedNumberBuffer.removeFirst()
        } else {
            formattedNumberBuffer = "-" + formattedNumberBuffer
        }
    }

    // MARK: - 書式化(内部バッファは小数点="."。表示/出力で設定の区切り文字に変換)

    // バッファ(素の数字文字列)を表示用に整形する。3桁区切りは sep_mil(formattedNumberGroupingEnabled)
    // 連動、区切り文字と小数点はコンテナー設定に従う。
    func formattedNumberDisplayString() -> String {
        var body = formattedNumberBuffer
        let isNegative = body.hasPrefix("-")
        if isNegative {
            body.removeFirst()
        }

        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerText = parts.isEmpty ? "" : String(parts[0])
        let hasDecimalPoint = body.contains(".")
        let fractionText = parts.count > 1 ? String(parts[1]) : ""

        let groupedInteger = formattedNumberGroupingEnabled
            ? groupedIntegerString(integerText)
            : integerText

        var result = groupedInteger
        if hasDecimalPoint {
            result += formattedNumberDecimalSeparator + fractionText
        }
        return (isNegative ? "-" : "") + result
    }

    // 整数部に3桁ごとの区切り文字を挿入する。que quatre オフのときは4桁を例外(5桁以上のみ区切る)。
    private func groupedIntegerString(_ digits: String) -> String {
        let threshold = formattedNumberGroupsFourDigits ? 3 : 4
        guard digits.count > threshold else {
            return digits
        }
        let separator = formattedNumberThousandsSeparator
        var grouped = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 {
                grouped.append(separator)
            }
            grouped.append(character)
        }
        return String(grouped.reversed())
    }

    // MARK: - 単位選択

    // 現在カテゴリーで選択中の基本記号(接頭辞なし)。未選択時は先頭。単位なしは空文字。
    private var formattedNumberSelectedBaseSymbol: String {
        let units = SIUnitCatalog.units(for: selectedFormattedNumberCategory)
        guard !units.isEmpty else {
            return ""
        }
        if let selected = formattedNumberUnitSelection[selectedFormattedNumberCategory.rawValue],
            units.contains(where: { $0.symbol == selected }) {
            return selected
        }
        return units.first?.symbol ?? ""
    }

    // 出力用の単位記号。SI基本のみ接頭辞ドラムの選択を前置する(k+g=kg 等)。
    var formattedNumberCurrentUnitSymbol: String {
        let base = formattedNumberSelectedBaseSymbol
        guard !base.isEmpty else {
            return ""
        }
        if selectedFormattedNumberCategory == .siBase {
            return formattedNumberPrefixSymbol + base
        }
        return base
    }

    private var formattedNumberUnitBinding: Binding<String> {
        Binding(
            get: { formattedNumberSelectedBaseSymbol },
            set: {
                formattedNumberUnitSelection[selectedFormattedNumberCategory.rawValue] = $0
                FormattedNumberPreferences.saveUnit($0, for: selectedFormattedNumberCategory)
                // 通貨を変えたら、その通貨の慣習(前/後)に前後スイッチを合わせる。
                if selectedFormattedNumberCategory == .currency {
                    formattedNumberCurrencySymbolBefore = SIUnitCatalog.currencySymbolBeforeAmount($0)
                }
            }
        )
    }

    private var formattedNumberPrefixBinding: Binding<String> {
        Binding(
            get: { formattedNumberPrefixSymbol },
            set: {
                formattedNumberPrefixSymbol = $0
                FormattedNumberPreferences.savePrefixSymbol($0)
            }
        )
    }

    // 下段カテゴリーキー。記号入力のカテゴリー選択と同じく accent の tint で選択を強調し、
    // 入力キー(暗め)と見分けやすくする。SI単位は正式なローマン体(Times New Roman)で表記。
    private func formattedNumberCategoryKey(_ category: FormattedNumberCategory) -> some View {
        let selected = selectedFormattedNumberCategory == category
        let isCalendar = category == .calendar
        let tint = accentColor
        let labelFont: Font = isCalendar
            ? .system(size: 18)
            : .custom("Times New Roman", size: 19)
        return Button {
            selectFormattedNumberCategory(category)
        } label: {
            Text(category.shortLabel)
                .font(labelFont)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundColor(isCalendar ? KeyboardThemePalette.keyLabel : (selected ? tint : tint.opacity(0.8)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            selected
                                ? tint.opacity(0.22)
                                : KeyboardThemePalette.categoryButtonBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            selected ? tint.opacity(0.75) : KeyboardThemePalette.keyBorder,
                            lineWidth: selected ? 1.4 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
    }

    // カテゴリー選択(前回値を保存し、カレンダー↔単位の高さ差を反映させる)。
    private func selectFormattedNumberCategory(_ category: FormattedNumberCategory) {
        let previous = selectedFormattedNumberCategory
        selectedFormattedNumberCategory = category
        FormattedNumberPreferences.saveCategory(category)
        // 金額に切り替えたら、選択中通貨の慣習に前後スイッチを合わせる。
        if category == .currency {
            formattedNumberCurrencySymbolBefore =
                SIUnitCatalog.currencySymbolBeforeAmount(formattedNumberSelectedBaseSymbol)
        }
        if (previous == .calendar) != (category == .calendar) {
            onFormattedNumberCategoryChanged()
        }
    }

    // 確定/プレビューに使う最終文字列。カレンダーはレンダリング日付、単位系は数値+単位。
    // 単位との間隔は当面なし(P4で設定化)。
    func formattedNumberOutputString() -> String {
        if selectedFormattedNumberCategory == .calendar {
            return formattedNumberRenderedDate()
        }
        let number = formattedNumberDisplayString()
        let unit = formattedNumberCurrentUnitSymbol
        return formattedNumberJoin(number: number, unit: unit)
    }

    // 数値と単位/記号の連結。金額は前後スイッチ(formattedNumberCurrencySymbolBefore)に従う。
    // 他カテゴリーの単位は後置(1,000N)。単位なしは数値のみ。
    private func formattedNumberJoin(number: String, unit: String) -> String {
        guard !unit.isEmpty else {
            return number
        }
        if selectedFormattedNumberCategory == .currency {
            return formattedNumberCurrencySymbolBefore ? unit + number : number + unit
        }
        // 単位3カテゴリー: 空白スイッチが入っていれば数値と単位の間に空白を入れる。
        return formattedNumberUnitSpacing ? number + " " + unit : number + unit
    }

    // MARK: - 右エリア(プレビュー+単位ドラム+区切りチェック+確定)

    private var formattedNumberPreviewText: String {
        if selectedFormattedNumberCategory == .calendar {
            return formattedNumberRenderedDate()
        }
        let number = formattedNumberBuffer.isEmpty ? "0" : formattedNumberDisplayString()
        let unit = formattedNumberCurrentUnitSymbol
        return formattedNumberJoin(number: number, unit: unit)
    }

    private var formattedNumberPreview: some View {
        HStack {
            Spacer(minLength: 0)
            Text(formattedNumberPreviewText)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(KeyboardThemePalette.keyLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardThemePalette.keyBackground)
        )
    }

    private var formattedNumberRightArea: some View {
        VStack(spacing: keyboardRowSpacing) {
            // 入力欄は単位ドラムの上に置く(ユーザ指定)。右寄せ表示。プレビュー/確定は
            // ドラムに縦を回すため控えめの高さにする(全体高さはかな入力と同一で頭打ち)。
            formattedNumberPreview
                .frame(height: 38)

            // ドラム(Picker wheel)は固有高さ(約200pt)が上位に伝播しレイアウトを乱す(遅延して
            // せり上がる)。Color.clear を固定高さのベースにして overlay で重ね .clipped() し、
            // サイズ決定をベース基準に固定して wheel の伝播を完全に断つ(はみ出しは clip)。
            Color.clear
                .frame(height: 92)
                .overlay(formattedNumberUnitSelector)
                .clipped()

            HStack(spacing: keyboardRowSpacing) {
                formattedNumberGroupingToggle
                if selectedFormattedNumberCategory == .currency {
                    formattedNumberCurrencyPlacementToggle
                } else {
                    formattedNumberUnitSpacingToggle
                }
                formattedNumberConfirmKey
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 40)
        }
    }

    // 数値と単位の間に空白を入れるかのスイッチ(単位3カテゴリーのみ。金額は前後スイッチ側)。
    // 選択中単位で実例表示(例: 1 m / 1m)。
    private var formattedNumberUnitSpacingToggle: some View {
        let symbol = formattedNumberSelectedBaseSymbol
        let sample = formattedNumberUnitSpacing ? "1 \(symbol)" : "1\(symbol)"
        return Button(action: {
            formattedNumberUnitSpacing.toggle()
            FormattedNumberPreferences.saveUnitSpacing(formattedNumberUnitSpacing)
        }) {
            VStack(spacing: 1) {
                Text(sample)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(formattedNumberUnitSpacing ? "空白" : "詰")
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
            .foregroundColor(KeyboardThemePalette.keyLabel)
            .frame(width: 50)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KeyboardThemePalette.keyBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(formattedNumberUnitSpacing ? "数値と単位の間に空白を入れる" : "数値と単位を詰める")
    }

    // 金額の通貨記号を数値の前/後どちらに付けるかのスイッチ。選択中通貨で実例表示(例: ¥1 / 1¥)。
    private var formattedNumberCurrencyPlacementToggle: some View {
        let symbol = formattedNumberSelectedBaseSymbol
        let sample = formattedNumberCurrencySymbolBefore ? "\(symbol)1" : "1\(symbol)"
        return Button(action: { formattedNumberCurrencySymbolBefore.toggle() }) {
            VStack(spacing: 1) {
                Text(sample)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(formattedNumberCurrencySymbolBefore ? "前" : "後")
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
            .foregroundColor(KeyboardThemePalette.keyLabel)
            .frame(width: 50)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KeyboardThemePalette.keyBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(formattedNumberCurrencySymbolBefore ? "通貨記号を前に付ける" : "通貨記号を後ろに付ける")
    }

    // ドラム行ラベル: 記号は固定サイズ、読みは小さい固定サイズ。幅が足りないときは
    // 縮小せず読みの末尾を「…」で切り詰める(truncationMode(.tail))。
    private func formattedNumberDrumLabel(symbol: String, reading: String) -> Text {
        var symbolPart = AttributedString(symbol)
        symbolPart.font = .system(size: 18, weight: .semibold)
        guard !reading.isEmpty else {
            return Text(symbolPart)
        }
        var readingPart = AttributedString((symbol.isEmpty ? "" : " ") + reading)
        readingPart.font = .system(size: 11)
        readingPart.foregroundColor = KeyboardThemePalette.keyLabel.opacity(0.6)
        return Text(symbolPart + readingPart)
    }

    // 単位ドラム。SI基本のみ「接頭辞ドラム+基本単位ドラム」の2連。カレンダー/空は占位。
    @ViewBuilder
    private var formattedNumberUnitSelector: some View {
        if selectedFormattedNumberCategory == .calendar {
            placeholderCard("カレンダー(P3)")
        } else if selectedFormattedNumberCategory == .siBase {
            HStack(spacing: keyboardRowSpacing) {
                Picker("", selection: formattedNumberPrefixBinding) {
                    ForEach(SIUnitCatalog.prefixes) { prefix in
                        formattedNumberDrumLabel(symbol: prefix.symbol, reading: prefix.reading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(prefix.symbol)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Picker("", selection: formattedNumberUnitBinding) {
                    ForEach(SIUnitCatalog.siBase) { unit in
                        formattedNumberDrumLabel(symbol: unit.symbol, reading: unit.reading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(unit.symbol)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        } else {
            let units = SIUnitCatalog.units(for: selectedFormattedNumberCategory)
            if units.isEmpty {
                placeholderCard("単位")
            } else {
                Picker("", selection: formattedNumberUnitBinding) {
                    ForEach(units) { unit in
                        formattedNumberDrumLabel(symbol: unit.symbol, reading: unit.reading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(unit.symbol)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
    }

    // 3桁区切りON/OFFのチェック。確定ボタンの左に置く。
    // sep mil: 千区切りの ON/OFF。チェックボックスではなく CapsLock 風のトグルボタン。
    // ロック(オン)色はラテン文字 Shift ロックと同じパレット accent(システム青だと分かりにくいため)。
    private var formattedNumberGroupingToggle: some View {
        let isOn = formattedNumberGroupingEnabled
        return Button(action: { formattedNumberGroupingEnabled.toggle() }) {
            Text("sep mil")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundColor(isOn ? .white : KeyboardThemePalette.keyLabel)
                .frame(width: 64)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? accentColor : KeyboardThemePalette.keyBackground)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("千区切り(sep mil)")
        .accessibilityValue(isOn ? "オン" : "オフ")
    }

    private func placeholderCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(KeyboardThemePalette.keyLabel.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KeyboardThemePalette.keyBackground)
            )
    }

    private var formattedNumberConfirmKey: some View {
        Button(action: commitFormattedNumber) {
            Text("確定")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 下段バー([あい] / カテゴリー / ⌫)

    // 下段バー。内部ボタンも指定高さで作る(外枠だけ縮めるとボタンがはみ出して上にずれるため)。
    private func formattedNumberBottomBar(height: CGFloat) -> some View {
        HStack(spacing: keyboardRowSpacing) {
            ActionKeyButton(
                title: "あい",
                fixedWidth: 56,
                action: { switchInputMode(.kana) }
            )
            .frame(height: height)

            ForEach(FormattedNumberCategory.allCases) { category in
                formattedNumberCategoryKey(category)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }

            ActionKeyButton(
                title: "⌫",
                accessibilityLabel: "削除",
                fontSize: 26,
                fixedWidth: 56,
                repeatsWhileHolding: true,
                repeatInitialDelay: keyRepeatInitialDelay,
                repeatInterval: keyRepeatInterval,
                action: deleteFormattedNumberBackward
            )
            .frame(height: height)
        }
    }
}
