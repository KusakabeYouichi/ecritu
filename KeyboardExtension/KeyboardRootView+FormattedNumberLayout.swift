import SwiftUI

// 書式化数値入力モードのカテゴリー(当面4種)。単位ドラム/カレンダーの切替に使う。
// rawValue は設定永続化に備えて歴史的値を明示する(絵文字カテゴリーと同方針)。
enum FormattedNumberCategory: Int, CaseIterable, Identifiable {
    case siBase = 0
    case siDerived = 1
    case siNamed = 2
    case calendar = 3

    var id: Int { rawValue }

    // 下段カテゴリーバーの短ラベル。
    var shortLabel: String {
        switch self {
        case .siBase:
            return "基"
        case .siDerived:
            return "組"
        case .siNamed:
            return "固"
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
        VStack(spacing: keyboardRowSpacing) {
            Group {
                if selectedFormattedNumberCategory == .calendar {
                    formattedNumberCalendarTopArea
                } else {
                    formattedNumberUnitTopArea
                }
            }
            .frame(height: fourRowAlignedTopContentHeight)

            formattedNumberBottomBar
                .frame(height: mainFlickKeyHeight)
        }
        .frame(height: fourRowAlignedClusterHeight, alignment: .top)
    }

    // 単位カテゴリー: テンキー + 右エリア(プレビュー+単位ドラム+区切り/確定)。
    private var formattedNumberUnitTopArea: some View {
        HStack(spacing: keyboardRowSpacing) {
            formattedNumberTenkey
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            formattedNumberRightArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // カレンダーカテゴリー: 日付ホイール + 右エリア(プレビュー+書式ドラム+確定)。
    private var formattedNumberCalendarTopArea: some View {
        HStack(spacing: keyboardRowSpacing) {
            DatePicker("", selection: $formattedNumberDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            VStack(spacing: keyboardRowSpacing) {
                formattedNumberPreview
                    .frame(height: mainFlickKeyHeight)
                formattedNumberDateFormatDrum
                    .frame(maxHeight: .infinity)
                formattedNumberConfirmKey
                    .frame(height: mainFlickKeyHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // 書式ドラム: 内部書式でなくサンプル日付(3月4日・水)でレンダリングした実例を表示。
    private var formattedNumberDateFormatDrum: some View {
        Picker("", selection: formattedNumberDateTemplateBinding) {
            ForEach(DateFormatCatalog.variants(for: formattedNumberDateStyle), id: \.self) { template in
                Text(DateFormatCatalog.sampleRendered(template: template, style: formattedNumberDateStyle))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .tag(template)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
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

    // カテゴリー選択(前回値を保存)。
    private func selectFormattedNumberCategory(_ category: FormattedNumberCategory) {
        selectedFormattedNumberCategory = category
        FormattedNumberPreferences.saveCategory(category)
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
            // 入力欄は単位ドラムの上に置く(ユーザ指定)。右寄せ表示。
            formattedNumberPreview
                .frame(height: mainFlickKeyHeight)

            formattedNumberUnitSelector
                .frame(maxHeight: .infinity)

            HStack(spacing: keyboardRowSpacing) {
                formattedNumberGroupingToggle
                formattedNumberConfirmKey
                    .frame(maxWidth: .infinity)
            }
            .frame(height: mainFlickKeyHeight)
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

    private var formattedNumberBottomBar: some View {
        HStack(spacing: keyboardRowSpacing) {
            ActionKeyButton(
                title: "あい",
                fixedWidth: 56,
                action: { switchInputMode(.kana) }
            )
            .frame(height: mainFlickKeyHeight)

            ForEach(FormattedNumberCategory.allCases) { category in
                EmojiCategoryKeyButton(
                    icon: category.shortLabel,
                    isSelected: selectedFormattedNumberCategory == category,
                    action: { selectFormattedNumberCategory(category) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: mainFlickKeyHeight)
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
            .frame(height: mainFlickKeyHeight)
        }
    }
}
