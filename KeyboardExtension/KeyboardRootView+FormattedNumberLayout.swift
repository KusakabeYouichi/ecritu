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

// P1: モードの外枠(テンキー / 右エリア=プレビュー+単位ドラム占位+確定 / 下段バー)。
// キーボードは横長で縦の余白が乏しいため、上段は高さいっぱいに可変分割し、下段バーだけ
// 固定1段にする(絵文字画面と同じ縦配分)。単位ドラム・書式化・カレンダーは後続フェーズ。
extension KeyboardRootView {
    var formattedNumberKeyboardView: some View {
        VStack(spacing: keyboardRowSpacing) {
            HStack(spacing: keyboardRowSpacing) {
                formattedNumberTenkey
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                formattedNumberRightArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: fourRowAlignedTopContentHeight)

            formattedNumberBottomBar
                .frame(height: mainFlickKeyHeight)
        }
        .frame(height: fourRowAlignedClusterHeight, alignment: .top)
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

    // MARK: - 右エリア(プレビュー+単位ドラム占位+区切りチェック+確定)

    private var formattedNumberPreviewText: String {
        formattedNumberBuffer.isEmpty ? "0" : formattedNumberDisplayString()
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

            placeholderCard(selectedFormattedNumberCategory == .calendar ? "カレンダー(P3)" : "単位ドラム(P2)")
                .frame(maxHeight: .infinity)

            HStack(spacing: keyboardRowSpacing) {
                formattedNumberGroupingToggle
                formattedNumberConfirmKey
                    .frame(maxWidth: .infinity)
            }
            .frame(height: mainFlickKeyHeight)
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
                    action: { selectedFormattedNumberCategory = category }
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
