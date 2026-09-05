import SwiftUI
import UIKit

// 書式(暦・温度・数値)の設定セクション。SettingsSectionViews.swift(1737 行)から分割(2805 リファクタ)

// カレンダー関連設定を1囲みにまとめる(週開始→曜日表記→日曜列の色→日付書式)。
struct CalendarSettingsGroupSection: View {
    @Binding var weekStart: CalendarWeekStartOption
    @Binding var weekdayLanguage: CalendarWeekdayLanguageOption
    @Binding var sundayColor: CalendarDayColorOption
    @Binding var fridayColor: CalendarDayColorOption
    @Binding var saturdayColor: CalendarDayColorOption
    @Binding var dateFormatStyle: DateFormatStyleOption

    // 日曜/金曜は赤系、土曜は青系の4択。
    private static let redChoices: [CalendarDayColorOption] = [.bordeaux, .bourgogne, .dic156, .dicF101]
    private static let blueChoices: [CalendarDayColorOption] = [.dic641, .dicF46, .dic156, .dicF101]

    // App 側の表示用色(キーボード側 formattedNumberCalendar*Color と同値)。
    private func dayDisplayColor(_ option: CalendarDayColorOption) -> Color {
        switch option {
        case .off:
            return .primary
        case .bordeaux:
            // bordeaux = rgb(141,17,74)
            return Color(red: 141.0 / 255.0, green: 17.0 / 255.0, blue: 74.0 / 255.0)
        case .bourgogne:
            // bourgogne = rgb(112,23,64)
            return Color(red: 112.0 / 255.0, green: 23.0 / 255.0, blue: 64.0 / 255.0)
        case .dic156:
            // DIC-156 = rgb(241,0,46)
            return Color(red: 241.0 / 255.0, green: 0.0 / 255.0, blue: 46.0 / 255.0)
        case .dicF101:
            // DIC-F101 = #D31C30
            return Color(red: 211.0 / 255.0, green: 28.0 / 255.0, blue: 48.0 / 255.0)
        case .dic641:
            // DIC 641(鮮やかな青)= 近似 rgb(0,111,191)。正確値は要確認。
            return Color(red: 0.0 / 255.0, green: 111.0 / 255.0, blue: 191.0 / 255.0)
        case .dicF46:
            // DIC-F46(ロイヤルブルー系)= 近似 rgb(38,62,138)。正確値は要確認。
            return Color(red: 38.0 / 255.0, green: 62.0 / 255.0, blue: 138.0 / 255.0)
        }
    }

    private func colorOnBinding(_ binding: Binding<CalendarDayColorOption>, defaultOn: CalendarDayColorOption) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue != .off },
            set: { isOn in
                binding.wrappedValue = isOn ? (binding.wrappedValue == .off ? defaultOn : binding.wrappedValue) : .off
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("カレンダー")
                .font(.headline)

            settingsSubItem("週開始") {
                Picker("週開始", selection: $weekStart) {
                    ForEach(CalendarWeekStartOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            settingsSubItem("曜日表記") {
                Picker("曜日表記", selection: $weekdayLanguage) {
                    ForEach(CalendarWeekdayLanguageOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            dayColorSubItem("日曜列の色", binding: $sundayColor, choices: Self.redChoices, defaultOn: .dic156)
            dayColorSubItem("土曜列の色", binding: $saturdayColor, choices: Self.blueChoices, defaultOn: .dic641)
            dayColorSubItem("金曜列の色", binding: $fridayColor, choices: Self.redChoices, defaultOn: .bourgogne)

            settingsSubItem("日付書式") {
                Picker("日付書式", selection: $dateFormatStyle) {
                    ForEach(DateFormatStyleOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("書式化数値モードのカレンダーの設定です。方式に応じてドラムの書式候補と月名・曜日名が変わります。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }

    // 曜日列の色サブ項目(オン/オフ + 4色チューザー)。
    @ViewBuilder
    private func dayColorSubItem(
        _ title: String,
        binding: Binding<CalendarDayColorOption>,
        choices: [CalendarDayColorOption],
        defaultOn: CalendarDayColorOption
    ) -> some View {
        settingsSubItem(title) {
            Toggle("色を付ける", isOn: colorOnBinding(binding, defaultOn: defaultOn))
            if binding.wrappedValue != .off {
                HStack(spacing: 8) {
                    ForEach(choices) { option in
                        Button {
                            binding.wrappedValue = option
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(binding.wrappedValue == option ? .bold : .regular))
                                .foregroundColor(dayDisplayColor(option))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            binding.wrappedValue == option ? dayDisplayColor(option) : Color.secondary.opacity(0.3),
                                            lineWidth: binding.wrappedValue == option ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// degré: 温度の度記号(°C・°F / ℃・℉)。format numérique とは別グループ — 数値入力モードだけでなく
// 変換候補(せっし/かし/せるしうす/ふぁーれんはいと、数字+ど)にも効くため(ユーザ指定 2773)
struct DegreSettingsSection: View {
    @Binding var degreeSymbol: DegreeSymbolOption

    var body: some View {
        let prefersFahrenheit = DegreeSymbolOption.prefersFahrenheit
        let otherScaleNote = prefersFahrenheit
            ? "Celsius(せっし・せるしうす)でも同様です(°C / ℃)。"
            : "Fahrenheit(かし・ふぁーれんはいと)でも同様です(°F / ℉)。"
        VStack(alignment: .leading, spacing: 16) {
            Text("degré")
                .font(.headline)

            Picker("degré", selection: $degreeSymbol) {
                ForEach(DegreeSymbolOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(Self.description(prefersFahrenheit: prefersFahrenheit, otherScaleNote: otherScaleNote))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }

    private static func description(prefersFahrenheit: Bool, otherScaleNote: String) -> String {
        var text: String
        if prefersFahrenheit {
            text = "SI(国際単位系)では、Celsius 温度についてしか規定されていませんが、度記号「°」の後に大文字「C」の 2 文字で表すことになっています(Fahrenheit に当てはめると 77 °F)。"
            text += "℉(1 文字)は SI の規定にはない互換文字で、日本語環境で広く使われています。\n"
        } else {
            text = "SI(国際単位系)では、Celsius 温度の単位記号は度記号「°」と大文字「C」の 2 文字 °C と規定され、数値との間に空白を置きます(25 °C)。"
            text += "℃(1 文字)は SI の規定にはない互換文字で、日本語環境で広く使われています。\n"
        }
        let ownReadings = prefersFahrenheit ? "かし・ふぁーれんはいと" : "せっし・せるしうす"
        text += "ここで選んだ字形は、数値入力モードの単位ドラムと、変換候補(" + ownReadings + "、数字のあとの「ど」)の両方に使われます。"
        text += "初期設定は " + (prefersFahrenheit ? "°F (U+00B0+F)" : "°C (U+00B0+C)") + " です。\n"
        text += otherScaleNote
        return text
    }
}

struct FormatNumeriqueSettingsSection: View {
    @Binding var thousandsSeparator: ThousandsSeparatorOption
    @Binding var groupFourDigits: Bool
    @Binding var decimalSeparator: DecimalSeparatorOption
    @Binding var unitProductSeparator: UnitProductSeparatorOption
    @Binding var litreSymbol: LitreSymbolOption

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("format numérique")
                .font(.headline)

            settingsSubItem("Séparateur de milliers") {
                separatorPicker(
                    options: Array(ThousandsSeparatorOption.allCases),
                    isSelected: { $0 == thousandsSeparator },
                    title: { $0.title },
                    onSelect: { thousandsSeparator = $0 }
                )

                HStack {
                    Spacer()
                    Toggle("que quatre", isOn: $groupFourDigits)
                        .fixedSize()
                }

                Text("千の位の区切りです(キーボードの sep mil がオンのとき挿入)。que quatre をオンにすると4桁の数値にも区切りを付けます(オフなら4桁は例外)。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            settingsSubItem("Séparateur décimal") {
                separatorPicker(
                    options: Array(DecimalSeparatorOption.allCases),
                    isSelected: { $0 == decimalSeparator },
                    title: { $0.title },
                    onSelect: { decimalSeparator = $0 }
                )

                Text("小数点の記号です。入力キーの表示/機能に反映されます。国際単位系(SI)における小数点は、ピリオドまたはカンマのいずれか、と規定されています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            settingsSubItem("単位の積の記号") {
                Picker("単位の積の記号", selection: $unitProductSeparator) {
                    ForEach(UnitProductSeparatorOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("N·m のような組立単位の積の記号です。\n・U+00B7: 一般テキストや化学式・単位の積を表す中黒\n・U+22C5: 数学的なドット演算子\n・U+0020: 1文字分のスペース")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            settingsSubItem("リットルの記号") {
                Picker("リットルの記号", selection: $litreSymbol) {
                    ForEach(LitreSymbolOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(
                    "単位ドラムのリットルに使う字形です。接頭辞と組み合わせた h\u{2113}・c\u{2113}・m\u{2113} にも反映されます。初期設定は l です。\n・"
                    + LitreSymbolOption.small.standardNote
                    + "\n・" + LitreSymbolOption.capital.standardNote
                    + "\n・" + LitreSymbolOption.script.standardNote
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .settingsCardStyle()
    }

    // 標準のセグメントピッカー風(グレーのトラック+白い選択サム+標準文字色)。他の設定と色・高さを
    // 揃えつつ、記号(. ,)だけ大きめに表示できるよう自前で描く。
    private func separatorPicker<Option: Identifiable>(
        options: [Option],
        isSelected: @escaping (Option) -> Bool,
        title: @escaping (Option) -> String,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = isSelected(option)
                Button {
                    onSelect(option)
                } label: {
                    separatorLabel(title(option))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selected ? Color(.systemBackground) : Color.clear)
                                .shadow(color: selected ? Color.black.opacity(0.14) : .clear, radius: 1, y: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(.secondarySystemFill))
        )
    }

    // 区切り記号(. や ,)はセグメント高さ(28)に収まる大きめ太字で、, と . の区別を付けやすく
    // する(espace は語なので通常サイズ)。
    @ViewBuilder
    private func separatorLabel(_ title: String) -> some View {
        if ["·", "⋅", "␣", ".", ","].contains(title) {
            Text(title)
                .font(.system(size: 22, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.primary)
        } else {
            Text(title)
                .font(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.primary)
        }
    }
}
