import SwiftUI

struct ContentView: View {
    private enum SettingsKeys {
        static let appGroupID = "group.com.kusakabe.ecritu"
        static let directionProfile = "flickDirectionProfile"
        static let kanaLayoutMode = "kanaLayoutMode"
        static let kanaModifierPlacement = "kanaModifierPlacement"
        static let latinLayoutMode = "latinLayoutMode"
        static let numberLayoutMode = "numberLayoutMode"
        static let accentPalette = "accentPalette"
        static let keyboardBackgroundTheme = "keyboardBackgroundTheme"
        static let showsFlickGuideCharacters = "showsFlickGuideCharacters"
        static let keyRepeatInitialDelay = "keyRepeatInitialDelay"
        static let keyRepeatInterval = "keyRepeatInterval"
    }

    private enum RepeatSettings {
        static let initialDelayDefault = 0.5
        static let initialDelayRange: ClosedRange<Double> = 0.1...0.8
        static let intervalDefault = 0.1
        static let intervalRange: ClosedRange<Double> = 0.05...0.2
        static let snapThreshold = 0.01
    }

    private enum KanaLayoutOption: String, CaseIterable, Identifiable {
        case fiveByTwo
        case threeByThreePlusWa

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fiveByTwo: return "5x2"
            case .threeByThreePlusWa: return "3x3+わ"
            }
        }
    }

    private enum KanaModifierPlacementOption: String, CaseIterable, Identifiable {
        case prefix
        case postfix

        var id: String { rawValue }

        var title: String {
            switch self {
            case .prefix: return "前置修飾"
            case .postfix: return "後置修飾"
            }
        }
    }

    private enum DirectionOption: String, CaseIterable, Identifiable {
        case apple
        case ecritu

        var id: String { rawValue }

        var title: String {
            switch self {
            case .apple: return "Apple"
            case .ecritu: return "écritu"
            }
        }
    }

    private enum LatinLayoutOption: String, CaseIterable, Identifiable {
        case azerty
        case qwerty
        case flick

        var id: String { rawValue }

        var title: String {
            switch self {
            case .flick: return "3x3"
            case .qwerty: return "qwerty"
            case .azerty: return "azerty"
            }
        }
    }

    private enum NumberLayoutOption: String, CaseIterable, Identifiable {
        case calculette
        case telephone

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calculette: return "calculette"
            case .telephone: return "téléphone"
            }
        }
    }

    private enum AccentColorOption: String, CaseIterable, Identifiable {
        case tuile
        case emeraude

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tuile: return "tuilé"
            case .emeraude: return "émeraude"
            }
        }

        var color: Color {
            switch self {
            case .tuile:
                return Color(red: 136.0 / 255.0, green: 63.0 / 255.0, blue: 53.0 / 255.0)
            case .emeraude:
                return Color(red: 0.06, green: 0.73, blue: 0.56)
            }
        }
    }

    private enum KeyboardBackgroundThemeOption: String, CaseIterable, Identifiable {
        case bleu
        case sakura

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bleu: return "bleu ciel brumeux"
            case .sakura: return "rose sakura poudré"
            }
        }

        var subtitle: String {
            switch self {
            case .bleu: return "brume douce et lumière du ciel"
            case .sakura: return "rose poudré inspiré des fleurs"
            }
        }

        var gradientColors: [Color] {
            switch self {
            case .bleu:
                return [
                    Color(red: 0.86, green: 0.91, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0)
                ]
            case .sakura:
                return [
                    Color(red: 1.0, green: 0.88, blue: 0.93),
                    Color(red: 1.0, green: 0.95, blue: 0.97)
                ]
            }
        }
    }

    private static let sharedDefaults = UserDefaults(suiteName: SettingsKeys.appGroupID)

    @AppStorage(
        SettingsKeys.directionProfile,
        store: Self.sharedDefaults
    )
    private var directionProfileRawValue: String = DirectionOption.ecritu.rawValue

    @AppStorage(
        SettingsKeys.kanaLayoutMode,
        store: Self.sharedDefaults
    )
    private var kanaLayoutModeRawValue: String = KanaLayoutOption.fiveByTwo.rawValue

    @AppStorage(
        SettingsKeys.kanaModifierPlacement,
        store: Self.sharedDefaults
    )
    private var kanaModifierPlacementRawValue: String = KanaModifierPlacementOption.prefix.rawValue

    @AppStorage(
        SettingsKeys.latinLayoutMode,
        store: Self.sharedDefaults
    )
    private var latinLayoutModeRawValue: String = LatinLayoutOption.azerty.rawValue

    @AppStorage(
        SettingsKeys.numberLayoutMode,
        store: Self.sharedDefaults
    )
    private var numberLayoutModeRawValue: String = NumberLayoutOption.calculette.rawValue

    @AppStorage(
        SettingsKeys.accentPalette,
        store: Self.sharedDefaults
    )
    private var accentPaletteRawValue: String = AccentColorOption.emeraude.rawValue

    @AppStorage(
        SettingsKeys.keyboardBackgroundTheme,
        store: Self.sharedDefaults
    )
    private var keyboardBackgroundThemeRawValue: String = KeyboardBackgroundThemeOption.bleu.rawValue

    @AppStorage(
        SettingsKeys.showsFlickGuideCharacters,
        store: Self.sharedDefaults
    )
    private var showsFlickGuideCharacters: Bool = true

    @AppStorage(
        SettingsKeys.keyRepeatInitialDelay,
        store: Self.sharedDefaults
    )
    private var keyRepeatInitialDelay: Double = RepeatSettings.initialDelayDefault

    @AppStorage(
        SettingsKeys.keyRepeatInterval,
        store: Self.sharedDefaults
    )
    private var keyRepeatInterval: Double = RepeatSettings.intervalDefault

    private let setupSteps: [String] = [
        "設定 > 一般 > キーボード > キーボード > 新しいキーボードを追加",
        "作成したキーボードを有効化",
        "入力画面で地球儀キーから切り替え"
    ]

    private func rawValueSelection<Option: RawRepresentable>(
        from rawValue: String,
        default fallback: Option,
        onUpdate: @escaping (String) -> Void
    ) -> Binding<Option> where Option.RawValue == String {
        Binding(
            get: { Option(rawValue: rawValue) ?? fallback },
            set: { onUpdate($0.rawValue) }
        )
    }

    private var directionSelection: Binding<DirectionOption> {
        rawValueSelection(from: directionProfileRawValue, default: .ecritu) {
            directionProfileRawValue = $0
        }
    }

    private var kanaLayoutSelection: Binding<KanaLayoutOption> {
        rawValueSelection(from: kanaLayoutModeRawValue, default: .fiveByTwo) {
            kanaLayoutModeRawValue = $0
        }
    }

    private var kanaModifierPlacementSelection: Binding<KanaModifierPlacementOption> {
        rawValueSelection(from: kanaModifierPlacementRawValue, default: .prefix) {
            kanaModifierPlacementRawValue = $0
        }
    }

    private var latinLayoutSelection: Binding<LatinLayoutOption> {
        rawValueSelection(from: latinLayoutModeRawValue, default: .azerty) {
            latinLayoutModeRawValue = $0
        }
    }

    private var numberLayoutSelection: Binding<NumberLayoutOption> {
        rawValueSelection(from: numberLayoutModeRawValue, default: .calculette) {
            numberLayoutModeRawValue = $0
        }
    }

    private var accentPaletteSelection: Binding<AccentColorOption> {
        rawValueSelection(from: accentPaletteRawValue, default: .emeraude) {
            accentPaletteRawValue = $0
        }
    }

    private var keyboardBackgroundThemeSelection: Binding<KeyboardBackgroundThemeOption> {
        rawValueSelection(from: keyboardBackgroundThemeRawValue, default: .bleu) {
            keyboardBackgroundThemeRawValue = $0
        }
    }

    private func snappedRepeatValue(_ value: Double, to defaultValue: Double) -> Double {
        abs(value - defaultValue) <= RepeatSettings.snapThreshold ? defaultValue : value
    }

    private func isAtRepeatDefault(_ value: Double, default defaultValue: Double) -> Bool {
        abs(value - defaultValue) <= RepeatSettings.snapThreshold
    }

    private var keyRepeatInitialDelayBinding: Binding<Double> {
        Binding(
            get: { keyRepeatInitialDelay },
            set: { keyRepeatInitialDelay = snappedRepeatValue($0, to: RepeatSettings.initialDelayDefault) }
        )
    }

    private var keyRepeatIntervalBinding: Binding<Double> {
        Binding(
            get: { keyRepeatInterval },
            set: { keyRepeatInterval = snappedRepeatValue($0, to: RepeatSettings.intervalDefault) }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer(minLength: 0)

                        Image("AppLogoDisplay")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)

                        Spacer(minLength: 0)
                    }

                    Text("このアプリはカスタムキーボード拡張の設定・管理を行うコンテナー・アプリ (Containing App) です。キーボード本体は拡張ターゲット側で実装されています。")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("フリック方向")
                            .font(.headline)

                        Picker("フリック方向", selection: directionSelection) {
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("かな修飾")
                            .font(.headline)

                        Picker("かな修飾", selection: kanaModifierPlacementSelection) {
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("かな配列")
                            .font(.headline)

                        Picker("かな配列", selection: kanaLayoutSelection) {
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ラテン文字配列")
                            .font(.headline)

                        Picker("ラテン文字配列", selection: latinLayoutSelection) {
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("数字配列")
                            .font(.headline)

                        Picker("数字配列", selection: numberLayoutSelection) {
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("アクセントカラー")
                            .font(.headline)

                        HStack(spacing: 8) {
                            ForEach(AccentColorOption.allCases) { option in
                                let isSelected = accentPaletteSelection.wrappedValue == option

                                Button {
                                    accentPaletteSelection.wrappedValue = option
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("テーマカラー")
                            .font(.headline)

                        VStack(spacing: 8) {
                            ForEach(KeyboardBackgroundThemeOption.allCases) { option in
                                let isSelected = keyboardBackgroundThemeSelection.wrappedValue == option

                                Button {
                                    keyboardBackgroundThemeSelection.wrappedValue = option
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

                                Slider(value: keyRepeatInitialDelayBinding, in: RepeatSettings.initialDelayRange, step: 0.01)
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

                                Slider(value: keyRepeatIntervalBinding, in: RepeatSettings.intervalRange, step: 0.01)
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("有効化手順")
                            .font(.headline)
                        ForEach(Array(setupSteps.enumerated()), id: \.offset) { index, step in
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

                    Text("フリックでひらがなを直接入力します。かな漢字変換は未実装です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("écritu")
                        .font(.custom("SnellRoundhand-Bold", size: 34))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
#endif
        }
    }
}

#Preview {
    ContentView()
}

private extension View {
    func settingsCardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.94))
            )
    }
}
