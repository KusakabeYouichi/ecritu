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

// P1: モードの外枠(プレビュー / テンキー / 右エリア占位 / 下段バー)。
// 単位ドラム・書式化・カレンダーは後続フェーズで実装する。
extension KeyboardRootView {
    var formattedNumberKeyboardView: some View {
        VStack(spacing: keyboardRowSpacing) {
            formattedNumberPreviewRow
            HStack(spacing: keyboardRowSpacing) {
                formattedNumberTenkey
                    .frame(maxWidth: .infinity)
                formattedNumberRightArea
                    .frame(maxWidth: .infinity)
            }
            formattedNumberBottomBar
                .frame(height: mainFlickKeyHeight)
        }
        .frame(height: fourRowAlignedClusterHeight, alignment: .top)
    }

    private var formattedNumberPreviewText: String {
        formattedNumberBuffer.isEmpty ? "0" : formattedNumberBuffer
    }

    private var formattedNumberPreviewRow: some View {
        HStack {
            Text(formattedNumberPreviewText)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(KeyboardThemePalette.keyLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: mainFlickKeyHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardThemePalette.keyBackground)
        )
    }

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
                        .frame(height: mainFlickKeyHeight)
                    }
                }
            }
        }
    }

    private func appendFormattedNumberToken(_ token: String) {
        switch token {
        case "±":
            toggleFormattedNumberSign()
        default:
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

    @ViewBuilder
    private var formattedNumberRightArea: some View {
        if selectedFormattedNumberCategory == .calendar {
            VStack(spacing: keyboardRowSpacing) {
                placeholderCard("カレンダー(P3)")
                formattedNumberConfirmKey
            }
        } else {
            VStack(spacing: keyboardRowSpacing) {
                placeholderCard("単位ドラム(P2)")
                formattedNumberConfirmKey
            }
        }
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
                .frame(maxWidth: .infinity)
                .frame(height: mainFlickKeyHeight)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
    }

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
