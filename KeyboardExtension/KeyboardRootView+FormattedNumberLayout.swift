import SwiftUI

// 書式化数値入力モードのカテゴリー(当面4種)。単位ドラム/カレンダーの切替に使う。
// rawValue は設定永続化に備えて歴史的値を明示する(絵文字カテゴリーと同方針)。
enum FormattedNumberCategory: Int, CaseIterable, Identifiable {
    case siBase = 0
    case siDerived = 1
    case siNamed = 2
    case calendar = 3

    var id: Int { rawValue }

    // 下段カテゴリーバーの短ラベル(代表単位記号でカテゴリーを示唆)。
    var shortLabel: String {
        switch self {
        case .siBase:
            return "m"
        case .siDerived:
            return "m/s"
        case .siNamed:
            return "N"
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

    // 単位カテゴリー: テンキー + 右エリア(プレビュー+単位ドラム+区切り/確定)。
    // カレンダーと同様に「自然高さ」にする(テンキー行・ドラムを固定高さにして wheel の固有高さが
    // 上位へ伝播しないようにする)。上位 Group の maxHeight:.infinity がフィルしバーが最下部へ。
    private var formattedNumberUnitTopArea: some View {
        HStack(alignment: .top, spacing: keyboardRowSpacing) {
            formattedNumberTenkey
                .frame(maxWidth: .infinity)
            formattedNumberRightArea
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

    // 縦画面: カレンダー(ヘッダー上)+右に操作列(プレビュー/書式/確定)。従来どおり。
    private var formattedNumberCalendarTopAreaPortrait: some View {
        HStack(alignment: .top, spacing: keyboardRowSpacing) {
            formattedNumberScaledCalendar

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
    }

    // 横画面: 縦の余裕が乏しいので、カレンダーのナビを右縦積みにしセルを低くして見切れを防ぐ。
    // 右端に操作列(プレビュー/書式/確定)。横幅は充分あるので広めに取る。
    private var formattedNumberCalendarTopAreaLandscape: some View {
        HStack(alignment: .top, spacing: keyboardRowSpacing) {
            FormattedNumberCalendarGridView(
                selectedDate: $formattedNumberDate,
                weekStartsMonday: formattedNumberCalendarWeekStartsMonday,
                language: formattedNumberCalendarLanguage,
                sundayColor: formattedNumberCalendarSundayColor,
                navigationPlacement: .trailing,
                cellHeight: formattedNumberLandscapeCalendarCellHeight
            )
            .frame(maxWidth: .infinity, alignment: .top)

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

    private var formattedNumberTenkey: some View {
        VStack(spacing: keyboardRowSpacing) {
            ForEach(Array(formattedNumberTenkeyRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: keyboardRowSpacing) {
                    ForEach(row, id: \.self) { token in
                        ActionKeyButton(
                            title: token,
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

    // MARK: - 書式化(暫定: 小数点="." / 桁区切り="," 固定。記号割当はP4設定)

    // バッファ(素の数字文字列)を表示用に整形する。3桁区切りは formattedNumberGroupingEnabled 連動。
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
            result += "." + fractionText
        }
        return (isNegative ? "-" : "") + result
    }

    // 整数部に3桁ごとのカンマを挿入する。
    private func groupedIntegerString(_ digits: String) -> String {
        guard digits.count > 3 else {
            return digits
        }
        var grouped = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 {
                grouped.append(",")
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

    // 下段カテゴリーキー(単位記号は Avenir Next、カレンダーは絵文字)。選択で背景/枠を強調。
    private func formattedNumberCategoryKey(_ category: FormattedNumberCategory) -> some View {
        let selected = selectedFormattedNumberCategory == category
        let labelFont: Font = category == .calendar
            ? .system(size: 18)
            : .custom("Avenir Next", size: 18).weight(.medium)
        return Button {
            selectFormattedNumberCategory(category)
        } label: {
            Text(category.shortLabel)
                .font(labelFont)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundColor(KeyboardThemePalette.keyLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            selected
                                ? KeyboardThemePalette.categoryButtonBackgroundSelected
                                : KeyboardThemePalette.categoryButtonBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            selected
                                ? KeyboardThemePalette.keyBorderEmphasis
                                : KeyboardThemePalette.keyBorder,
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
        return unit.isEmpty ? number : number + unit
    }

    // MARK: - 右エリア(プレビュー+単位ドラム+区切りチェック+確定)

    private var formattedNumberPreviewText: String {
        if selectedFormattedNumberCategory == .calendar {
            return formattedNumberRenderedDate()
        }
        let number = formattedNumberBuffer.isEmpty ? "0" : formattedNumberDisplayString()
        let unit = formattedNumberCurrentUnitSymbol
        return unit.isEmpty ? number : number + unit
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
                formattedNumberConfirmKey
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 40)
        }
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
    private var formattedNumberGroupingToggle: some View {
        Button(action: { formattedNumberGroupingEnabled.toggle() }) {
            HStack(spacing: 3) {
                Image(systemName: formattedNumberGroupingEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                Text("3桁")
                    .font(.system(size: 12))
            }
            .foregroundColor(KeyboardThemePalette.keyLabel)
            .frame(width: 64)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KeyboardThemePalette.keyBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("3桁区切り")
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
