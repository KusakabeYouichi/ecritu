import SwiftUI

struct DirectionSettingsSection: View {
    @Binding var selection: DirectionOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("フリック方向")
                .font(.headline)

            Picker("フリック方向", selection: $selection) {
                ForEach(DirectionOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("Apple / écritu の切り替えは次回のキーボード表示時に反映されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct KanaLayoutSettingsSection: View {
    @Binding var selection: KanaLayoutOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("かな配列")
                .font(.headline)

            Picker("かな配列", selection: $selection) {
                ForEach(KanaLayoutOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("かなモードで使う配列を切り替えます。標準は 5x2、3x3+わ は Apple標準の日本語配列に合わせて各段5ボタン(3かな + 機能2)で表示します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct KanaModifierSettingsSection: View {
    @Binding var selection: KanaModifierPlacementOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("かな修飾")
                .font(.headline)

            Picker("かな修飾", selection: $selection) {
                ForEach(KanaModifierPlacementOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("濁点・半濁点・拗音/促音の入力方式を切り替えます。前置修飾は修飾を先に選択、後置修飾は文字入力後に修飾を選択します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct LatinLayoutSettingsSection: View {
    @Binding var selection: LatinLayoutOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ラテン文字配列")
                .font(.headline)

            Picker("ラテン文字配列", selection: $selection) {
                ForEach(LatinLayoutOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("abcモードで使う配列を切り替えます。qwerty/azertyでは文字キーを長押ししてアクセント付き文字を入力できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct NumberLayoutSettingsSection: View {
    @Binding var selection: NumberLayoutOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("数字配列")
                .font(.headline)

            Picker("数字配列", selection: $selection) {
                ForEach(NumberLayoutOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("123モードの数字キー配列を切り替えます。téléphone は上段が 1-2-3、calculette は上段が 7-8-9 です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
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
                                            ? Color.white.opacity(0.96)
                                            : Color.white.opacity(0.7)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(
                                        isSelected
                                            ? option.color.opacity(0.65)
                                            : Color.black.opacity(0.1),
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
                    .fill(Color(white: 0.9))
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
                                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
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
                                        : Color.black.opacity(0.22)
                                )
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isSelected
                                        ? Color.white.opacity(0.96)
                                        : Color.white.opacity(0.72)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isSelected
                                        ? Color.black.opacity(0.15)
                                        : Color.black.opacity(0.08),
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
                    .fill(Color(white: 0.9))
            )

            Text("キーボード背景のグラデイションを切り替えます。左の色見本は実際の背景色です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct DisplaySettingsSection: View {
    @Binding var showsFlickGuideCharacters: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("表示")
                .font(.headline)

            Toggle("フリックガイド文字", isOn: $showsFlickGuideCharacters)
                .tint(Color.orange)

            Text("各キーの4方向に表示するガイド文字のON/OFFを切り替えます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct KeyRepeatSettingsSection: View {
    @Binding var keyRepeatInitialDelay: Double
    @Binding var keyRepeatInterval: Double

    private func isAtRepeatDefault(_ value: Double, default defaultValue: Double) -> Bool {
        abs(value - defaultValue) <= 0.001
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("削除キーリピート")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("リピート開始までの時間")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        if isAtRepeatDefault(
                            keyRepeatInitialDelay,
                            default: RepeatSettings.initialDelayDefault
                        ) {
                            Text("デフォルト")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.orange.opacity(0.12))
                                )
                        }
                        Text("\(keyRepeatInitialDelay.formatted(.number.precision(.fractionLength(2)))) 秒")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $keyRepeatInitialDelay, in: RepeatSettings.initialDelayRange, step: 0.01)
                        .tint(Color.orange)

                    HStack {
                        Text("デフォルト: \(RepeatSettings.initialDelayDefault.formatted(.number.precision(.fractionLength(2)))) 秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        if !isAtRepeatDefault(
                            keyRepeatInitialDelay,
                            default: RepeatSettings.initialDelayDefault
                        ) {
                            Button("デフォルトに戻す") {
                                keyRepeatInitialDelay = RepeatSettings.initialDelayDefault
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("リピート速度(間隔)")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        if isAtRepeatDefault(
                            keyRepeatInterval,
                            default: RepeatSettings.intervalDefault
                        ) {
                            Text("デフォルト")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.orange.opacity(0.12))
                                )
                        }
                        Text("\(keyRepeatInterval.formatted(.number.precision(.fractionLength(2)))) 秒")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $keyRepeatInterval, in: RepeatSettings.intervalRange, step: 0.01)
                        .tint(Color.orange)

                    HStack {
                        Text("デフォルト: \(RepeatSettings.intervalDefault.formatted(.number.precision(.fractionLength(2)))) 秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        if !isAtRepeatDefault(
                            keyRepeatInterval,
                            default: RepeatSettings.intervalDefault
                        ) {
                            Button("デフォルトに戻す") {
                                keyRepeatInterval = RepeatSettings.intervalDefault
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }

            Text("削除キーは1回目の押下で削除され、上の時間が過ぎると設定した間隔で連続削除されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct SetupStepsSection: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("有効化手順")
                .font(.headline)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(step)
                        .font(.subheadline)
                }
            }
        }
        .settingsCardStyle()
    }
}

private extension View {
    func settingsCardStyle() -> some View {
        padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.94))
            )
    }
}
