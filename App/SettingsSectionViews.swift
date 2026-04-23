import SwiftUI
import UIKit

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

struct FlickGuideDisplaySettingsSection: View {
    @Binding var kanaSelection: FlickGuideDisplayOption
    @Binding var latinSelection: FlickGuideDisplayOption
    @Binding var numberSelection: FlickGuideDisplayOption

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

                Text("数字入力")
                    .font(.subheadline.weight(.semibold))
                Picker("数字入力", selection: $numberSelection) {
                    ForEach(FlickGuideDisplayOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("入力モードごとにガイド表示を選択します。『下』はメイン文字の下にガイド文字を横並びで表示します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct UserDictionarySettingsSection: View {
    @Binding var entries: [VocabularyEntry]
    @Binding var readingInput: String
    @Binding var candidateInput: String
    @Binding var isRegistrationVisible: Bool
    @Binding var scrollIndexTitle: String
    @Binding var isScrollIndexVisible: Bool

    let canAddEntry: Bool
    let listHeight: CGFloat
    let onAddEntry: () -> Void
    let onDeleteEntry: (VocabularyEntry) -> Void
    let onResetLearning: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("追加語彙")
                    .font(.headline)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegistrationVisible.toggle()
                    }
                } label: {
                    Image(systemName: isRegistrationVisible ? "xmark" : "plus")
                        .font(.headline.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(
                                    isRegistrationVisible
                                        ? Color.red.opacity(0.16)
                                        : Color.accentColor.opacity(0.14)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isRegistrationVisible
                        ? "追加単語の登録欄を閉じる"
                        : "追加単語の登録欄を表示"
                )
            }

            if isRegistrationVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("追加単語の登録")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        TextField("候補", text: $candidateInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                            )

                        TextField("よみ", text: $readingInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                            )

                        Button("登録") {
                            onAddEntry()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegistrationVisible = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAddEntry)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Spacer(minLength: 8)

                Text(scrollIndexTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 26, minHeight: 20)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.82))
                    )
                    .opacity(isScrollIndexVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.28), value: isScrollIndexVisible)
            }

            if entries.isEmpty {
                Text("登録済みの追加単語はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    onDelete: onDeleteEntry,
                    onIndexIndicatorStateChange: { title, isVisible in
                        DispatchQueue.main.async {
                            if !title.isEmpty {
                                scrollIndexTitle = title
                            }

                            withAnimation(.easeOut(duration: 0.28)) {
                                isScrollIndexVisible = isVisible
                            }
                        }
                    }
                )
                .frame(height: listHeight)
            }

            Button("学習履歴をリセット") {
                onResetLearning()
            }
            .buttonStyle(.bordered)

            Text("追加単語はキーボード拡張と共有され、候補の優先順位に反映されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct SuppressionDictionarySettingsSection: View {
    @Binding var entries: [VocabularyEntry]
    @Binding var readingInput: String
    @Binding var candidateInput: String
    @Binding var isRegistrationVisible: Bool
    @Binding var scrollIndexTitle: String
    @Binding var isScrollIndexVisible: Bool

    let canAddEntry: Bool
    let listHeight: CGFloat
    let onAddEntry: () -> Void
    let onDeleteEntry: (VocabularyEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("抑制語彙")
                    .font(.headline)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegistrationVisible.toggle()
                    }
                } label: {
                    Image(systemName: isRegistrationVisible ? "xmark" : "plus")
                        .font(.headline.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(
                                    isRegistrationVisible
                                        ? Color.red.opacity(0.16)
                                        : Color.accentColor.opacity(0.14)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isRegistrationVisible
                        ? "抑制単語の登録欄を閉じる"
                        : "抑制単語の登録欄を表示"
                )
            }

            if isRegistrationVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("抑制単語の登録")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        TextField("単語", text: $candidateInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                            )

                        TextField("よみ", text: $readingInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                            )

                        Button("登録") {
                            onAddEntry()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegistrationVisible = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAddEntry)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Spacer(minLength: 8)

                Text(scrollIndexTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 26, minHeight: 20)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.82))
                    )
                    .opacity(isScrollIndexVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.28), value: isScrollIndexVisible)
            }

            if entries.isEmpty {
                Text("登録済みの抑制単語はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    onDelete: onDeleteEntry,
                    onIndexIndicatorStateChange: { title, isVisible in
                        DispatchQueue.main.async {
                            if !title.isEmpty {
                                scrollIndexTitle = title
                            }

                            withAnimation(.easeOut(duration: 0.28)) {
                                isScrollIndexVisible = isVisible
                            }
                        }
                    }
                )
                .frame(height: listHeight)
            }

            Text("抑制は『読み+単語』の組み合わせで適用され、同じ単語でも別の読み候補には影響しません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct IndexedVocabularyList: UIViewRepresentable {
    let entries: [VocabularyEntry]
    let onDelete: (VocabularyEntry) -> Void
    let onIndexIndicatorStateChange: (String, Bool) -> Void

    private static let kanaIndexTitles: [String] = ["あ", "か", "さ", "た", "な", "は", "ま", "や", "ら", "わ"]
    private static let allIndexTitles: [String] = kanaIndexTitles

    func makeCoordinator() -> Coordinator {
        Coordinator(
            entries: entries,
            onDelete: onDelete,
            onIndexIndicatorStateChange: onIndexIndicatorStateChange
        )
    }

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Coordinator.cellReuseIdentifier)
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.rowHeight = 30
        tableView.separatorStyle = .none
        context.coordinator.attachCustomIndex(to: tableView)
        return tableView
    }

    func updateUIView(_ uiView: UITableView, context: Context) {
        context.coordinator.update(
            entries: entries,
            onDelete: onDelete,
            onIndexIndicatorStateChange: onIndexIndicatorStateChange
        )
        context.coordinator.attachCustomIndex(to: uiView)
        uiView.reloadData()
        uiView.layoutIfNeeded()
        context.coordinator.refreshCustomIndexVisibility()
    }

    private static func indexTitle(for reading: String) -> String {
        let trimmed = reading.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = trimmed.first else {
            return "あ"
        }

        let firstString = String(first)

        let hiragana = firstString.applyingTransform(.hiraganaToKatakana, reverse: true) ?? firstString

        guard let kana = hiragana.first else {
            return "あ"
        }

        switch kana {
        case "ぁ", "あ", "ぃ", "い", "ぅ", "う", "ぇ", "え", "ぉ", "お", "ゔ":
            return "あ"
        case "か", "が", "き", "ぎ", "く", "ぐ", "け", "げ", "こ", "ご":
            return "か"
        case "さ", "ざ", "し", "じ", "す", "ず", "せ", "ぜ", "そ", "ぞ":
            return "さ"
        case "た", "だ", "ち", "ぢ", "っ", "つ", "づ", "て", "で", "と", "ど":
            return "た"
        case "な", "に", "ぬ", "ね", "の":
            return "な"
        case "は", "ば", "ぱ", "ひ", "び", "ぴ", "ふ", "ぶ", "ぷ", "へ", "べ", "ぺ", "ほ", "ぼ", "ぽ":
            return "は"
        case "ま", "み", "む", "め", "も":
            return "ま"
        case "ゃ", "や", "ゅ", "ゆ", "ょ", "よ":
            return "や"
        case "ら", "り", "る", "れ", "ろ":
            return "ら"
        case "ゎ", "わ", "を", "ん":
            return "わ"
        default:
            return "あ"
        }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        static let cellReuseIdentifier = "IndexedVocabularyCell"
        static let candidateLabelTag = 1001
        static let readingLabelTag = 1002

        private var entries: [VocabularyEntry]
        private var onDelete: (VocabularyEntry) -> Void
        private var onIndexIndicatorStateChange: (String, Bool) -> Void
        private var groupedEntries: [String: [VocabularyEntry]] = [:]
        private var visibleSectionTitles: [String] = []
        private var overlayHideWorkItem: DispatchWorkItem?
        private var currentIndexIndicatorTitle = ""
        private weak var tableView: UITableView?
        private let customIndexContainerView = UIView()
        private let customIndexStackView = UIStackView()
        private var customIndexLabels: [UILabel] = []
        private lazy var customIndexTapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleCustomIndexTap(_:))
        )
        private lazy var customIndexPanGesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleCustomIndexPan(_:))
        )

        init(
            entries: [VocabularyEntry],
            onDelete: @escaping (VocabularyEntry) -> Void,
            onIndexIndicatorStateChange: @escaping (String, Bool) -> Void
        ) {
            self.entries = entries
            self.onDelete = onDelete
            self.onIndexIndicatorStateChange = onIndexIndicatorStateChange
            super.init()
            rebuildSections()
        }

        func update(
            entries: [VocabularyEntry],
            onDelete: @escaping (VocabularyEntry) -> Void,
            onIndexIndicatorStateChange: @escaping (String, Bool) -> Void
        ) {
            self.entries = entries
            self.onDelete = onDelete
            self.onIndexIndicatorStateChange = onIndexIndicatorStateChange
            rebuildSections()
        }

        func attachCustomIndex(to tableView: UITableView) {
            self.tableView = tableView

            if customIndexContainerView.superview !== tableView {
                customIndexContainerView.translatesAutoresizingMaskIntoConstraints = false
                customIndexContainerView.backgroundColor = .clear
                customIndexContainerView.isUserInteractionEnabled = true
                customIndexContainerView.layer.zPosition = 10

                customIndexStackView.translatesAutoresizingMaskIntoConstraints = false
                customIndexStackView.axis = .vertical
                customIndexStackView.alignment = .center
                customIndexStackView.distribution = .fillEqually
                customIndexStackView.spacing = 0

                customIndexContainerView.addSubview(customIndexStackView)
                customIndexContainerView.addGestureRecognizer(customIndexTapGesture)
                customIndexContainerView.addGestureRecognizer(customIndexPanGesture)

                tableView.addSubview(customIndexContainerView)

                NSLayoutConstraint.activate([
                    customIndexContainerView.trailingAnchor.constraint(equalTo: tableView.frameLayoutGuide.trailingAnchor, constant: -4),
                    customIndexContainerView.topAnchor.constraint(equalTo: tableView.frameLayoutGuide.topAnchor, constant: 20),
                    customIndexContainerView.bottomAnchor.constraint(equalTo: tableView.frameLayoutGuide.bottomAnchor, constant: -20),
                    customIndexContainerView.widthAnchor.constraint(equalToConstant: 24),

                    customIndexStackView.leadingAnchor.constraint(equalTo: customIndexContainerView.leadingAnchor),
                    customIndexStackView.trailingAnchor.constraint(equalTo: customIndexContainerView.trailingAnchor),
                    customIndexStackView.topAnchor.constraint(equalTo: customIndexContainerView.topAnchor),
                    customIndexStackView.bottomAnchor.constraint(equalTo: customIndexContainerView.bottomAnchor)
                ])

                rebuildCustomIndexLabels()
            }

            if customIndexLabels.isEmpty {
                rebuildCustomIndexLabels()
            }

            tableView.bringSubviewToFront(customIndexContainerView)

            refreshCustomIndexVisibility()

            DispatchQueue.main.async { [weak self] in
                self?.refreshCustomIndexVisibility()
            }
        }

        private func rebuildCustomIndexLabels() {
            for label in customIndexLabels {
                customIndexStackView.removeArrangedSubview(label)
                label.removeFromSuperview()
            }

            customIndexLabels.removeAll()

            for title in IndexedVocabularyList.allIndexTitles {
                let label = UILabel()
                label.translatesAutoresizingMaskIntoConstraints = false
                label.text = title
                label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
                label.textColor = .systemBlue
                label.textAlignment = .center

                NSLayoutConstraint.activate([
                    label.widthAnchor.constraint(equalToConstant: 20)
                ])

                customIndexStackView.addArrangedSubview(label)
                customIndexLabels.append(label)
            }
        }

        func refreshCustomIndexVisibility() {
            let isScrollable = isTableViewScrollable()
            let shouldShowIndex = !customIndexLabels.isEmpty && isScrollable

            customIndexContainerView.isHidden = !shouldShowIndex
            customIndexContainerView.isUserInteractionEnabled = shouldShowIndex

            if !shouldShowIndex {
                hideScrollingIndexOverlayImmediately()
            }
        }

        private func isTableViewScrollable() -> Bool {
            guard let tableView else {
                return false
            }

            tableView.layoutIfNeeded()
            let visibleHeight = tableView.bounds.height
            guard visibleHeight > 1 else {
                return false
            }

            let contentHeight = tableView.contentSize.height

            return contentHeight > visibleHeight + 1
        }

        private func nearestIndexPosition(for point: CGPoint) -> Int? {
            guard !customIndexLabels.isEmpty else {
                return nil
            }

            customIndexStackView.layoutIfNeeded()

            var nearestIndex = 0
            var nearestDistance = CGFloat.greatestFiniteMagnitude

            for (index, label) in customIndexLabels.enumerated() {
                let distance = abs(point.y - label.frame.midY)

                if distance < nearestDistance {
                    nearestDistance = distance
                    nearestIndex = index
                }
            }

            return nearestIndex
        }

        private func resolveSection(for title: String, at index: Int) -> Int {
            guard !visibleSectionTitles.isEmpty else {
                return 0
            }

            if let exactIndex = visibleSectionTitles.firstIndex(of: title) {
                return exactIndex
            }

            for next in index..<IndexedVocabularyList.allIndexTitles.count {
                let candidate = IndexedVocabularyList.allIndexTitles[next]
                if let resolvedIndex = visibleSectionTitles.firstIndex(of: candidate) {
                    return resolvedIndex
                }
            }

            for previous in stride(from: index, through: 0, by: -1) {
                let candidate = IndexedVocabularyList.allIndexTitles[previous]
                if let resolvedIndex = visibleSectionTitles.firstIndex(of: candidate) {
                    return resolvedIndex
                }
            }

            return 0
        }

        private func navigateToSection(at index: Int) {
            guard let tableView,
                    !IndexedVocabularyList.allIndexTitles.isEmpty,
                    !visibleSectionTitles.isEmpty else {
                return
            }

            let boundedIndex = min(max(index, 0), IndexedVocabularyList.allIndexTitles.count - 1)
            let title = IndexedVocabularyList.allIndexTitles[boundedIndex]
            showScrollingIndexOverlay(title: title)

            let section = resolveSection(for: title, at: boundedIndex)
            let rowCount = tableView.numberOfRows(inSection: section)

            guard rowCount > 0 else {
                return
            }

            tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: false)
        }

        @objc
        private func handleCustomIndexTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: customIndexStackView)

            guard let index = nearestIndexPosition(for: point) else {
                return
            }

            navigateToSection(at: index)
            scheduleHideScrollingIndexOverlay()
        }

        @objc
        private func handleCustomIndexPan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: customIndexStackView)

            switch gesture.state {
            case .began, .changed:
                if let index = nearestIndexPosition(for: point) {
                    navigateToSection(at: index)
                }
            case .ended, .cancelled, .failed:
                scheduleHideScrollingIndexOverlay()
            default:
                break
            }
        }

        private func rebuildSections() {
            var grouped: [String: [VocabularyEntry]] = [:]

            for indexTitle in IndexedVocabularyList.allIndexTitles {
                grouped[indexTitle] = []
            }

            for entry in entries {
                let indexTitle = IndexedVocabularyList.indexTitle(for: entry.reading)
                grouped[indexTitle, default: []].append(entry)
            }

            groupedEntries = grouped
            visibleSectionTitles = IndexedVocabularyList.allIndexTitles.filter {
                !(groupedEntries[$0]?.isEmpty ?? true)
            }

            refreshCustomIndexVisibility()

            if visibleSectionTitles.isEmpty {
                hideScrollingIndexOverlayImmediately()
            }
        }

        private func currentVisibleSectionTitle(in tableView: UITableView) -> String? {
            let topY = tableView.contentOffset.y + tableView.adjustedContentInset.top + 1
            let probePoint = CGPoint(x: 8, y: max(topY, 1))

            if let indexPath = tableView.indexPathForRow(at: probePoint),
                indexPath.section < visibleSectionTitles.count {
                return visibleSectionTitles[indexPath.section]
            }

            guard let firstVisible = tableView.indexPathsForVisibleRows?.sorted(by: {
                if $0.section == $1.section {
                    return $0.row < $1.row
                }
                return $0.section < $1.section
            }).first,
            firstVisible.section < visibleSectionTitles.count else {
                return nil
            }

            return visibleSectionTitles[firstVisible.section]
        }

        private func showScrollingIndexOverlay(title: String?) {
            guard isTableViewScrollable() else {
                hideScrollingIndexOverlayImmediately()
                return
            }

            guard let title, !title.isEmpty else {
                return
            }

            overlayHideWorkItem?.cancel()
            currentIndexIndicatorTitle = title
            onIndexIndicatorStateChange(title, true)
        }

        private func scheduleHideScrollingIndexOverlay() {
            overlayHideWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else {
                    return
                }

                self.onIndexIndicatorStateChange(self.currentIndexIndicatorTitle, false)
            }

            overlayHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        private func hideScrollingIndexOverlayImmediately() {
            overlayHideWorkItem?.cancel()
            onIndexIndicatorStateChange(currentIndexIndicatorTitle, false)
        }

        private func entry(at indexPath: IndexPath) -> VocabularyEntry {
            let sectionTitle = visibleSectionTitles[indexPath.section]
            return groupedEntries[sectionTitle]![indexPath.row]
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            visibleSectionTitles.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            let sectionTitle = visibleSectionTitles[section]
            return groupedEntries[sectionTitle]?.count ?? 0
        }

        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            nil
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            CGFloat.leastNonzeroMagnitude
        }

        func sectionIndexTitles(for tableView: UITableView) -> [String]? {
            nil
        }

        func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
            resolveSection(for: title, at: index)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? UITableView else {
                return
            }

            showScrollingIndexOverlay(title: currentVisibleSectionTitle(in: tableView))
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? UITableView else {
                return
            }

            let isUserInteracting = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            guard isUserInteracting else {
                return
            }

            showScrollingIndexOverlay(title: currentVisibleSectionTitle(in: tableView))
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                scheduleHideScrollingIndexOverlay()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            scheduleHideScrollingIndexOverlay()
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)
            let entry = entry(at: indexPath)

            let candidateLabel: UILabel
            let readingLabel: UILabel

            if let existingCandidateLabel = cell.contentView.viewWithTag(Self.candidateLabelTag) as? UILabel,
                let existingReadingLabel = cell.contentView.viewWithTag(Self.readingLabelTag) as? UILabel {
                candidateLabel = existingCandidateLabel
                readingLabel = existingReadingLabel
            } else {
                candidateLabel = UILabel()
                candidateLabel.tag = Self.candidateLabelTag
                candidateLabel.translatesAutoresizingMaskIntoConstraints = false
                candidateLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
                candidateLabel.textColor = .label
                candidateLabel.textAlignment = .left
                candidateLabel.lineBreakMode = .byTruncatingTail

                readingLabel = UILabel()
                readingLabel.tag = Self.readingLabelTag
                readingLabel.translatesAutoresizingMaskIntoConstraints = false
                readingLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                readingLabel.textColor = .secondaryLabel
                readingLabel.textAlignment = .left
                readingLabel.lineBreakMode = .byTruncatingTail

                cell.contentView.addSubview(candidateLabel)
                cell.contentView.addSubview(readingLabel)

                NSLayoutConstraint.activate([
                    candidateLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 10),
                    candidateLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.centerXAnchor, constant: -10),
                    candidateLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),

                    readingLabel.leadingAnchor.constraint(equalTo: cell.contentView.centerXAnchor, constant: -2),
                    readingLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -10),
                    readingLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
                ])
            }

            candidateLabel.text = entry.candidate
            readingLabel.text = entry.reading

            cell.textLabel?.text = nil
            cell.backgroundColor = UIColor.white.withAlphaComponent(0.72)
            cell.selectionStyle = .none

            return cell
        }

        func tableView(
            _ tableView: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            let target = entry(at: indexPath)

            let delete = UIContextualAction(style: .destructive, title: "削除") { [weak self] _, _, completion in
                self?.onDelete(target)
                completion(true)
            }

            return UISwipeActionsConfiguration(actions: [delete])
        }
    }
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
