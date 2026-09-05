import SwiftUI
import UIKit

// 配列・向き・横向きレイアウトの設定セクション。SettingsSectionViews.swift(1737 行)から分割(2805 リファクタ)

struct DirectionSettingsSection: View {
    @Binding var selection: DirectionOption

    var body: some View {
        SegmentedSettingsCard(
            title: "フリック方向",
            pickerTitle: "フリック方向",
            selection: $selection,
            options: Array(DirectionOption.allCases),
            optionTitle: { $0.title },
            footnote: "style iPhone は iPhone 標準キーボードと同じ方向割り当て、style écritu は écritu 独自の割り当てです。切り替えは次回のキーボード表示時に反映されます。"
        )
    }
}

struct KanaModifierSettingsSection: View {
    @Binding var selection: KanaModifierPlacementOption

    var body: some View {
        SegmentedSettingsCard(
            title: "かな修飾",
            pickerTitle: "かな修飾",
            selection: $selection,
            options: Array(KanaModifierPlacementOption.allCases),
            optionTitle: { $0.title },
            footnote: "濁点・半濁点・拗音/促音の入力方式を切り替えます。前置修飾は修飾を先に選択、後置修飾は文字入力後に修飾を選択します。"
        )
    }
}

struct KanaLayoutSettingsSection: View {
    @Binding var selection: KanaLayoutOption

    var body: some View {
        SegmentedSettingsCard(
            title: "かな配列",
            pickerTitle: "かな配列",
            selection: $selection,
            options: Array(KanaLayoutOption.allCases),
            optionTitle: { $0.title },
            footnote: "かなモードで使う配列を切り替えます。標準は 5x2、3x3+わ は iPhone 標準の日本語配列に合わせて各段5ボタン(3かな + 機能2)で表示します。"
        )
    }
}

struct LandscapeCandidateSideSettingsSection: View {
    @Binding var selection: LandscapeCandidateSideOption
    @Binding var latinSuggestionMode: LandscapeLatinSuggestionModeOption

    private var paneOrder: [LatinCandidatePaneArrangementItem] {
        selection == .left ? [.candidate, .latin] : [.latin, .candidate]
    }

    private var usesLandscapeLatinSuggestionPane: Bool {
        latinSuggestionMode == .sidebar
    }

    private func updateSelection(from order: [LatinCandidatePaneArrangementItem]) {
        guard let first = order.first else {
            return
        }

        selection = first == .candidate ? .left : .right
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ラテン文字候補ペイン (horizontal)")
                .font(.headline)

            Button {
                latinSuggestionMode = usesLandscapeLatinSuggestionPane ? .off : .sidebar
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: usesLandscapeLatinSuggestionPane ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(usesLandscapeLatinSuggestionPane ? Color.accentColor : .secondary)

                    Text("横向きラテン文字入力で候補ペインを使う")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.cardInnerBackground)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("横向きラテン文字入力で候補ペインを使う")
            .accessibilityValue(usesLandscapeLatinSuggestionPane ? "オン" : "オフ")

            DraggablePanePairRow(
                items: paneOrder,
                title: { $0.title },
                onReorder: updateSelection
            )
            .disabled(!usesLandscapeLatinSuggestionPane)
            .opacity(usesLandscapeLatinSuggestionPane ? 1 : 0.55)

            Text("『ラテン文字』『候補』をドラグして並び順を入れ替えます。オン/オフは横向きラテン文字入力時のみ有効です。チェックを外している間は左右配置を変更できません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct LandscapeNumberPaneSideSettingsSection: View {
    @Binding var selection: LandscapeCandidateSideOption

    private var paneOrder: [NumberPaneArrangementItem] {
        selection == .left ? [.number, .symbols] : [.symbols, .number]
    }

    private func updateSelection(from order: [NumberPaneArrangementItem]) {
        guard let first = order.first else {
            return
        }

        selection = first == .number ? .left : .right
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("数字ペイン配列 (horizontal)")
                .font(.headline)

            DraggablePanePairRow(
                items: paneOrder,
                title: { $0.title },
                onReorder: updateSelection
            )

            Text("『数字』『記号』をドラグして並び順を入れ替えます。横向きの数字3x3入力時に反映され、かな入力モードの候補配置には影響しません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct LatinLayoutSettingsSection: View {
    @Binding var selection: LatinLayoutOption

    var body: some View {
        SegmentedSettingsCard(
            title: "ラテン文字配列",
            pickerTitle: "ラテン文字配列",
            selection: $selection,
            options: Array(LatinLayoutOption.allCases),
            optionTitle: { $0.title },
            footnote: "abcモードで使う配列を切り替えます。qwerty/azertyでは文字キーを長押ししてアクセント付き文字を入力できます。"
        )
    }
}

struct NumberLayoutSettingsSection: View {
    @Binding var selection: NumberLayoutOption
    @Binding var formattedNumberKeypad: FormattedNumberKeypadOption

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("数字配列")
                .font(.headline)

            settingsSubItem("数字入力") {
                Picker("数字入力", selection: $selection) {
                    ForEach(NumberLayoutOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("téléphone は上段が 1-2-3、calculette は上段が 7-8-9、clavier は AZERTY 風の数字+記号配列(shift で 2 種類の記号セットを切替)です。clavier は縦画面のみ対応。横画面では自動的に calculette が使われます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            settingsSubItem("書式化数値入力") {
                Picker("書式化数値入力", selection: $formattedNumberKeypad) {
                    ForEach(FormattedNumberKeypadOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("書式化数値入力のテンキー配列です。téléphone は上段が 1-2-3、calculette は上段が 7-8-9。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsCardStyle()
    }
}
