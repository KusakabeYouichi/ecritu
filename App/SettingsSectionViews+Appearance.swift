import SwiftUI
import UIKit

// 見た目(記号順・アクセント色・テーマ色・フリックガイド)の設定セクション。SettingsSectionViews.swift(1737 行)から分割(2805 リファクタ)

struct BasicSymbolOrderSettingsSection: View {
    @Binding var selection: BasicSymbolOrderOption

    var body: some View {
        SegmentedSettingsCard(
            title: "基本記号の並び順",
            pickerTitle: "基本記号の並び順",
            selection: $selection,
            options: Array(BasicSymbolOrderOption.allCases),
            optionTitle: { $0.title },
            footnote: "記号モードの『基本記号』カテゴリーの並び順を切り替えます。初期設定は ASCII 順です。"
        )
    }
}

struct AccentColorSettingsSection: View {
    @Binding var selection: AccentColorOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アクセントカラー")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(AccentColorOption.allCases) { option in
                    let isSelected = selection == option

                    Button {
                        selection = option
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(option.color)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? AppTheme.selectedControlBackground
                                            : AppTheme.controlBackground
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(
                                        isSelected
                                            ? option.color.opacity(0.65)
                                            : AppTheme.subtleBorder,
                                        lineWidth: isSelected ? 1.3 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.cardInnerBackground)
            )

            Text("キー押下時のアクセント色を切り替えます。チュイレは瓦の色、エメロードは宝石の色です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct ThemeColorSettingsSection: View {
    @Binding var selection: KeyboardBackgroundThemeOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("テーマカラー")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(KeyboardBackgroundThemeOption.allCases) { option in
                    let isSelected = selection == option

                    Button {
                        selection = option
                    } label: {
                        HStack(alignment: .top, spacing: 9) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: option.gradientColors,
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 52, height: 30)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(AppTheme.subtleBorder, lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)

                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(
                                    isSelected
                                        ? Color.accentColor
                                        : AppTheme.subduedIcon
                                )
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isSelected
                                        ? AppTheme.selectedControlBackground
                                        : AppTheme.controlBackground
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isSelected
                                        ? AppTheme.emphasisBorder
                                        : AppTheme.subtleBorder,
                                    lineWidth: isSelected ? 1.2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.cardInnerBackground)
            )

            Text("キーボード背景のグラデイションを切り替えます。左の色見本は実際の背景色です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct FlickGuideDisplaySettingsSection: View {
    @Binding var kanaSelection: FlickGuideDisplayOption
    @Binding var latinSelection: FlickGuideDisplayOption
    @Binding var numberSelection: FlickGuideDisplayOption
    @Binding var modifierSelection: FlickGuideDisplayOption
    let isLatinGuideAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ガイド文字表示")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("かな入力")
                    .font(.subheadline.weight(.semibold))
                Picker("かな入力", selection: $kanaSelection) {
                    ForEach(FlickGuideDisplayOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("ラテン文字入力")
                    .font(.subheadline.weight(.semibold))
                Picker("ラテン文字入力", selection: $latinSelection) {
                    ForEach(FlickGuideDisplayOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!isLatinGuideAvailable)

                Text("数字入力")
                    .font(.subheadline.weight(.semibold))
                Picker("数字入力", selection: $numberSelection) {
                    ForEach(FlickGuideDisplayOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("濁点・半濁点・小文字キー")
                    .font(.subheadline.weight(.semibold))
                Picker("濁点・半濁点・小文字キー", selection: $modifierSelection) {
                    ForEach(FlickGuideDisplayOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("入力モードごとにガイド表示を選択できます。濁点・半濁点・小文字キーは入力モード設定と独立して適用されます。『下』はメイン文字の下にガイド文字を横並びで表示します。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !isLatinGuideAvailable {
                Text("ラテン文字配列が 3x3 以外のとき、ラテン文字配列のガイド文字は表示されません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsCardStyle()
    }
}
