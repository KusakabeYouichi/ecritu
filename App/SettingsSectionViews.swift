import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

struct KeyboardDiagnosticsSection: View {
    let isSessionActive: Bool
    let lastHeartbeatText: String
    let lastEvent: String
    let lastSessionID: String
    let installMarker: String
    let logLines: [String]
    let onReload: () -> Void
    let onCopy: () -> Void
    let onClear: () -> Void

    @State private var isClearConfirmationPresented = false
    @State private var isCopiedBadgeVisible = false

    private var logText: String {
        logLines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("キーボード診断ログ")
                    .font(.headline)

                Text("\(logLines.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(isSessionActive ? "稼働中" : "停止")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSessionActive ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill((isSessionActive ? Color.green : Color.secondary).opacity(0.12))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("最終ハートビート: \(lastHeartbeatText)")
                Text("最終セッションID: \(lastSessionID.isEmpty ? "なし" : lastSessionID)")
                Text("最終イベント: \(lastEvent.isEmpty ? "なし" : lastEvent)")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("更新") {
                    onReload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("コピー") {
                    onCopy()
                    withAnimation(.easeOut(duration: 0.16)) {
                        isCopiedBadgeVisible = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isCopiedBadgeVisible = false
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    isClearConfirmationPresented = true
                } label: {
                    Text("ログクリア")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .confirmationDialog(
                    "診断ログを削除しますか?",
                    isPresented: $isClearConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("削除", role: .destructive) {
                        onClear()
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("保存済みの診断ログが削除されます。")
                }

                if isCopiedBadgeVisible {
                    Text("コピーしました")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if logLines.isEmpty {
                Text("診断ログはまだありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(logText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.controlBackground)
                )
            }

            Text("インストール識別子: \(installMarker.isEmpty ? "未設定" : installMarker)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

private struct SegmentedSettingsCard<Option: Hashable>: View {
    let title: String
    let pickerTitle: String
    @Binding var selection: Option
    let options: [Option]
    let optionTitle: (Option) -> String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Picker(pickerTitle, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

private enum KanaPaneArrangementItem: String, CaseIterable, Identifiable {
    case kana
    case candidate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kana:
            return "かな"
        case .candidate:
            return "候補"
        }
    }
}

private enum NumberPaneArrangementItem: String, CaseIterable, Identifiable {
    case number
    case symbols

    var id: String { rawValue }

    var title: String {
        switch self {
        case .number:
            return "数字"
        case .symbols:
            return "記号"
        }
    }
}

private struct PanePairSwapDropDelegate<Item: Equatable>: DropDelegate {
    let targetItem: Item
    let orderedItems: [Item]
    @Binding var draggingItem: Item?
    let onReorder: ([Item]) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggingItem,
            draggingItem != targetItem,
            let sourceIndex = orderedItems.firstIndex(of: draggingItem),
            let targetIndex = orderedItems.firstIndex(of: targetItem) else {
            return
        }

        var nextOrder = orderedItems
        nextOrder.swapAt(sourceIndex, targetIndex)
        onReorder(nextOrder)
        self.draggingItem = targetItem
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}

private struct DraggablePanePairRow<Item: Identifiable & Equatable>: View where Item.ID == String {
    let items: [Item]
    let title: (Item) -> String
    let onReorder: ([Item]) -> Void

    @State private var draggingItem: Item?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 7) {
                    Image(systemName: "line.3.horizontal")
                        .rotationEffect(.degrees(90))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(title(item))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.controlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            draggingItem == item
                                ? Color.accentColor.opacity(0.55)
                                : AppTheme.subtleBorder,
                            lineWidth: draggingItem == item ? 1.4 : 1
                        )
                )
                .onDrag {
                    draggingItem = item
                    return NSItemProvider(object: NSString(string: item.id))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: PanePairSwapDropDelegate(
                        targetItem: item,
                        orderedItems: items,
                        draggingItem: $draggingItem,
                        onReorder: onReorder
                    )
                )
            }
        }
    }
}

private struct ScrollIndexBadgeView: View {
    let title: String
    let isVisible: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Spacer(minLength: 8)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(minWidth: 26, minHeight: 20)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.indexBadgeBackground)
                )
                .opacity(isVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.28), value: isVisible)
        }
    }
}

private func applyScrollIndexIndicatorState(
    title: String,
    isVisible: Bool,
    scrollIndexTitle: Binding<String>,
    isScrollIndexVisible: Binding<Bool>
) {
    DispatchQueue.main.async {
        if !title.isEmpty, scrollIndexTitle.wrappedValue != title {
            scrollIndexTitle.wrappedValue = title
        }

        if isScrollIndexVisible.wrappedValue != isVisible {
            withAnimation(.easeOut(duration: 0.28)) {
                isScrollIndexVisible.wrappedValue = isVisible
            }
        }
    }
}

struct KanaModeSwitcherAssignmentSection: View {
    @Binding var tapSelection: KanaModeSwitcherActionOption
    @Binding var rightFlickSelection: KanaModeSwitcherActionOption
    @Binding var upFlickSelection: KanaModeSwitcherActionOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("かな左下キー割り当て")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("タップ")
                    .font(.subheadline.weight(.semibold))
                Picker("タップ", selection: $tapSelection) {
                    ForEach(KanaModeSwitcherActionOption.allCases) { option in
                        Text("\(option.title) (\(option.keyLabel))").tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("右フリック")
                    .font(.subheadline.weight(.semibold))
                Picker("右フリック", selection: $rightFlickSelection) {
                    ForEach(KanaModeSwitcherActionOption.allCases) { option in
                        Text("\(option.title) (\(option.keyLabel))").tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text("上フリック")
                    .font(.subheadline.weight(.semibold))
                Picker("上フリック", selection: $upFlickSelection) {
                    ForEach(KanaModeSwitcherActionOption.allCases) { option in
                        Text("\(option.title) (\(option.keyLabel))").tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text("かな入力モード左下キーのタップ・右フリック・上フリックの動作を設定します。同じ機能を複数方向に割り当てることもできます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct DirectionSettingsSection: View {
    @Binding var selection: DirectionOption

    var body: some View {
        SegmentedSettingsCard(
            title: "フリック方向",
            pickerTitle: "フリック方向",
            selection: $selection,
            options: Array(DirectionOption.allCases),
            optionTitle: { $0.title },
            footnote: "Apple / écritu の切り替えは次回のキーボード表示時に反映されます。"
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
            footnote: "かなモードで使う配列を切り替えます。標準は 5x2、3x3+わ は Apple標準の日本語配列に合わせて各段5ボタン(3かな + 機能2)で表示します。"
        )
    }
}

struct LandscapeCandidateSideSettingsSection: View {
    @Binding var selection: LandscapeCandidateSideOption

    private var paneOrder: [KanaPaneArrangementItem] {
        selection == .left ? [.candidate, .kana] : [.kana, .candidate]
    }

    private func updateSelection(from order: [KanaPaneArrangementItem]) {
        guard let first = order.first else {
            return
        }

        selection = first == .candidate ? .left : .right
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("かなペイン配列 (horizontal)")
                .font(.headline)

            DraggablePanePairRow(
                items: paneOrder,
                title: { $0.title },
                onReorder: updateSelection
            )

            Text("『かな』『候補』をドラグして並び順を入れ替えます。横向きのかな入力時に反映され、縦向きには影響しません。")
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

    var body: some View {
        SegmentedSettingsCard(
            title: "数字配列",
            pickerTitle: "数字配列",
            selection: $selection,
            options: Array(NumberLayoutOption.allCases),
            optionTitle: { $0.title },
            footnote: "123モードの数字キー配列を切り替えます。téléphone は上段が 1-2-3、calculette は上段が 7-8-9 です。"
        )
    }
}

struct BasicSymbolOrderSettingsSection: View {
    @Binding var selection: BasicSymbolOrderOption

    var body: some View {
        SegmentedSettingsCard(
            title: "基本記号の並び順",
            pickerTitle: "基本記号の並び順",
            selection: $selection,
            options: Array(BasicSymbolOrderOption.allCases),
            optionTitle: { $0.title },
            footnote: "記号モードの『基本記号』カテゴリの並び順を切り替えます。既定は ASCII 順です。"
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
            }

            Text("入力モードごとにガイド表示を選択します。『下』はメイン文字の下にガイド文字を横並びで表示します。")
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

private struct DictionaryRegistrationHeaderView: View {
    let title: String
    let count: Int
    let isRegistrationVisible: Bool
    let showAccessibilityLabel: String
    let hideAccessibilityLabel: String
    let onToggleRegistration: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)

            Text("\(count)件")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(action: onToggleRegistration) {
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
                    ? hideAccessibilityLabel
                    : showAccessibilityLabel
            )
        }
    }
}

private struct DictionaryInputField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.controlBackground)
            )
            .frame(maxWidth: .infinity)
    }
}

private struct DictionaryRegistrationActionRow: View {
    let isEditing: Bool
    let canSubmit: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(isEditing ? "保存" : "登録") {
                onSubmit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .font(.footnote.weight(.semibold))
            .disabled(!canSubmit)

            if isEditing {
                Button("キャンセル") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.subheadline)
            }
        }
    }
}

private struct DictionaryRegistrationForm<Fields: View>: View {
    let title: String
    let isEditing: Bool
    let canSubmit: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let fields: Fields

    init(
        title: String,
        isEditing: Bool,
        canSubmit: Bool,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder fields: () -> Fields
    ) {
        self.title = title
        self.isEditing = isEditing
        self.canSubmit = canSubmit
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.fields = fields()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                fields

                DictionaryRegistrationActionRow(
                    isEditing: isEditing,
                    canSubmit: canSubmit,
                    onSubmit: onSubmit,
                    onCancel: onCancel
                )
            }
        }
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
    let onUpdateEntry: (VocabularyEntry) -> Void
    let onDeleteEntry: (VocabularyEntry) -> Void
    let onDeleteAll: () -> Void
    let onReimportInitialEntries: () -> Void

    @State private var isDeleteAllConfirmationPresented = false
    @State private var isReimportConfirmationPresented = false
    @State private var editingEntry: VocabularyEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DictionaryRegistrationHeaderView(
                title: "追加語彙",
                count: entries.count,
                isRegistrationVisible: isRegistrationVisible,
                showAccessibilityLabel: "追加単語の登録欄を表示",
                hideAccessibilityLabel: "追加単語の登録欄を閉じる",
                onToggleRegistration: {
                    if isRegistrationVisible {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                        return
                    }

                    editingEntry = nil
                    readingInput = ""
                    candidateInput = ""

                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegistrationVisible = true
                    }
                }
            )

            if isRegistrationVisible {
                DictionaryRegistrationForm(
                    title: editingEntry == nil ? "追加単語の登録" : "追加単語の編集",
                    isEditing: editingEntry != nil,
                    canSubmit: canAddEntry,
                    onSubmit: {
                        if let editingEntry {
                            onUpdateEntry(editingEntry)
                        } else {
                            onAddEntry()
                        }
                        editingEntry = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                    },
                    onCancel: {
                        editingEntry = nil
                        readingInput = ""
                        candidateInput = ""
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                    }
                ) {
                    DictionaryInputField(placeholder: "候補", text: $candidateInput)
                    DictionaryInputField(placeholder: "よみ", text: $readingInput)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollIndexBadgeView(
                title: scrollIndexTitle,
                isVisible: isScrollIndexVisible
            )

            if entries.isEmpty {
                Text("登録済みの追加単語はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    listHeight: listHeight,
                    selectedEntryID: editingEntry?.id,
                    onDelete: { entry in
                        if editingEntry?.id == entry.id {
                            editingEntry = nil
                            readingInput = ""
                            candidateInput = ""
                        }
                        onDeleteEntry(entry)
                    },
                    onSelect: { entry in
                        editingEntry = entry
                        readingInput = entry.reading
                        candidateInput = entry.candidate

                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = true
                        }
                    },
                    onIndexIndicatorStateChange: { title, isVisible in
                        applyScrollIndexIndicatorState(
                            title: title,
                            isVisible: isVisible,
                            scrollIndexTitle: $scrollIndexTitle,
                            isScrollIndexVisible: $isScrollIndexVisible
                        )
                    }
                )
                .frame(height: listHeight)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        isReimportConfirmationPresented = true
                    } label: {
                        Text("初期語彙再投入")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .confirmationDialog(
                        "初期追加語彙を再投入しますか?",
                        isPresented: $isReimportConfirmationPresented,
                        titleVisibility: .visible
                    ) {
                        Button("再投入する") {
                            onReimportInitialEntries()
                        }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("現在の追加語彙を残したまま、初期追加語彙を再投入します。")
                    }

                    if !entries.isEmpty {
                        Button(role: .destructive) {
                            isDeleteAllConfirmationPresented = true
                        } label: {
                            Text("全削除")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .confirmationDialog(
                            "追加語彙をすべて削除しますか?",
                            isPresented: $isDeleteAllConfirmationPresented,
                            titleVisibility: .visible
                        ) {
                            Button("すべて削除", role: .destructive) {
                                onDeleteAll()
                            }
                            Button("キャンセル", role: .cancel) {}
                        } message: {
                            Text("この操作は元に戻せません。")
                        }
                    }
                }
            }

            Text("追加単語はキーボード拡張と共有され、候補の優先順位に反映されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct LearnedDictionarySettingsSection: View {
    @Binding var entries: [VocabularyEntry]
    @Binding var scrollIndexTitle: String
    @Binding var isScrollIndexVisible: Bool

    let listHeight: CGFloat
    let onDeleteEntry: (VocabularyEntry) -> Void
    let onDeleteAll: () -> Void
    let onResetLearning: () -> Void

    @State private var isDeleteAllConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("学習語彙")
                    .font(.headline)

                Text("\(entries.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
            }

            ScrollIndexBadgeView(
                title: scrollIndexTitle,
                isVisible: isScrollIndexVisible
            )

            if entries.isEmpty {
                Text("学習で蓄積された語彙はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    listHeight: listHeight,
                    selectedEntryID: nil,
                    onDelete: onDeleteEntry,
                    onSelect: nil,
                    onIndexIndicatorStateChange: { title, isVisible in
                        applyScrollIndexIndicatorState(
                            title: title,
                            isVisible: isVisible,
                            scrollIndexTitle: $scrollIndexTitle,
                            isScrollIndexVisible: $isScrollIndexVisible
                        )
                    }
                )
                .frame(height: listHeight)
            }

            HStack(spacing: 12) {
                Button {
                    onResetLearning()
                } label: {
                    Text("学習リセット")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !entries.isEmpty {
                    Button(role: .destructive) {
                        isDeleteAllConfirmationPresented = true
                    } label: {
                        Text("学習語彙全削除")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .confirmationDialog(
                        "学習語彙をすべて削除しますか?",
                        isPresented: $isDeleteAllConfirmationPresented,
                        titleVisibility: .visible
                    ) {
                        Button("すべて削除", role: .destructive) {
                            onDeleteAll()
                        }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("この操作は元に戻せません。")
                    }
                }
            }

            Text(
                "学習語彙は確定操作から自動登録された候補です。手動で登録する追加語彙とは別に管理されます。\n"
                    + "学習語彙全削除: 語彙リストは消えるが、学習スコア由来の癖は残る\n"
                    + "学習リセット: 語彙リストも学習スコアも消える(より完全な初期化)"
            )
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
    let onUpdateEntry: (VocabularyEntry) -> Void
    let onDeleteEntry: (VocabularyEntry) -> Void

    @State private var editingEntry: VocabularyEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DictionaryRegistrationHeaderView(
                title: "抑制語彙",
                count: entries.count,
                isRegistrationVisible: isRegistrationVisible,
                showAccessibilityLabel: "抑制単語の登録欄を表示",
                hideAccessibilityLabel: "抑制単語の登録欄を閉じる",
                onToggleRegistration: {
                    if isRegistrationVisible {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                        return
                    }

                    editingEntry = nil
                    readingInput = ""
                    candidateInput = ""

                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegistrationVisible = true
                    }
                }
            )

            if isRegistrationVisible {
                DictionaryRegistrationForm(
                    title: editingEntry == nil ? "抑制単語の登録" : "抑制単語の編集",
                    isEditing: editingEntry != nil,
                    canSubmit: canAddEntry,
                    onSubmit: {
                        if let editingEntry {
                            onUpdateEntry(editingEntry)
                        } else {
                            onAddEntry()
                        }
                        editingEntry = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                    },
                    onCancel: {
                        editingEntry = nil
                        readingInput = ""
                        candidateInput = ""
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                    }
                ) {
                    DictionaryInputField(placeholder: "単語", text: $candidateInput)
                    DictionaryInputField(placeholder: "よみ", text: $readingInput)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollIndexBadgeView(
                title: scrollIndexTitle,
                isVisible: isScrollIndexVisible
            )

            if entries.isEmpty {
                Text("登録済みの抑制単語はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    listHeight: listHeight,
                    selectedEntryID: editingEntry?.id,
                    onDelete: { entry in
                        if editingEntry?.id == entry.id {
                            editingEntry = nil
                            readingInput = ""
                            candidateInput = ""
                        }
                        onDeleteEntry(entry)
                    },
                    onSelect: { entry in
                        editingEntry = entry
                        readingInput = entry.reading
                        candidateInput = entry.candidate

                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = true
                        }
                    },
                    onIndexIndicatorStateChange: { title, isVisible in
                        applyScrollIndexIndicatorState(
                            title: title,
                            isVisible: isVisible,
                            scrollIndexTitle: $scrollIndexTitle,
                            isScrollIndexVisible: $isScrollIndexVisible
                        )
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

struct ShortcutDictionarySettingsSection: View {
    @Binding var entries: [VocabularyEntry]
    @Binding var candidateInput: String
    @Binding var isRegistrationVisible: Bool

    @State private var pendingDeletionEntry: VocabularyEntry?
    @State private var editingEntry: VocabularyEntry?

    let canAddEntry: Bool
    let listHeight: CGFloat
    let onAddEntry: () -> Void
    let onUpdateEntry: (VocabularyEntry) -> Void
    let onDeleteEntry: (VocabularyEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DictionaryRegistrationHeaderView(
                title: "ショートカット語彙",
                count: entries.count,
                isRegistrationVisible: isRegistrationVisible,
                showAccessibilityLabel: "ショートカット語彙の登録欄を表示",
                hideAccessibilityLabel: "ショートカット語彙の登録欄を閉じる",
                onToggleRegistration: {
                    if isRegistrationVisible {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                        return
                    }

                    editingEntry = nil
                    candidateInput = ""

                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegistrationVisible = true
                    }
                }
            )

            if isRegistrationVisible {
                VStack(alignment: .leading, spacing: 8) {
                    DictionaryRegistrationForm(
                        title: editingEntry == nil ? "ショートカット語彙の登録" : "ショートカット語彙の編集",
                        isEditing: editingEntry != nil,
                        canSubmit: canAddEntry,
                        onSubmit: {
                            if let editingEntry {
                                onUpdateEntry(editingEntry)
                            } else {
                                onAddEntry()
                            }
                            editingEntry = nil
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegistrationVisible = false
                            }
                        },
                        onCancel: {
                            editingEntry = nil
                            candidateInput = ""
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegistrationVisible = false
                            }
                        }
                    ) {
                        DictionaryInputField(placeholder: "候補", text: $candidateInput)

                        HStack(spacing: 6) {
                            Text("よみ")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text("☻（固定）")
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.controlBackground)
                        )
                    }

                    Text("読みは ☻ で固定されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if entries.isEmpty {
                Text("登録済みのショートカット語彙はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Text(entry.candidate)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    editingEntry?.id == entry.id
                                        ? Color.accentColor.opacity(0.22)
                                        : AppTheme.listRowBackground
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            editingEntry?.id == entry.id
                                                ? Color.accentColor.opacity(0.6)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingEntry = entry
                            candidateInput = entry.candidate
                            pendingDeletionEntry = nil

                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegistrationVisible = true
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if editingEntry?.id == entry.id {
                                    editingEntry = nil
                                    candidateInput = ""
                                }
                                pendingDeletionEntry = entry
                            } label: {
                                Text("削除")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 30)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(height: listHeight)
            }

            Text("ショートカット語彙は顔文字入力の先頭側に表示され、固定顔文字とは区切り線で分離されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
        .alert(
            "ショートカット語彙を削除しますか？",
            isPresented: Binding(
                get: { pendingDeletionEntry != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionEntry = nil
                    }
                }
            ),
            presenting: pendingDeletionEntry
        ) { entry in
            Button("キャンセル", role: .cancel) {
                pendingDeletionEntry = nil
            }

            Button("削除", role: .destructive) {
                onDeleteEntry(entry)
                pendingDeletionEntry = nil
            }
        } message: { entry in
            Text("「\(entry.candidate)」を削除します。")
        }
    }
}

struct ReadOnlyDictionarySettingsSection: View {
    let title: String
    let entries: [VocabularyEntry]
    @Binding var scrollIndexTitle: String
    @Binding var isScrollIndexVisible: Bool
    let listHeight: CGFloat
    let emptyMessage: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)

                Text("\(entries.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
            }

            ScrollIndexBadgeView(
                title: scrollIndexTitle,
                isVisible: isScrollIndexVisible
            )

            if entries.isEmpty {
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    listHeight: listHeight,
                    selectedEntryID: nil,
                    onDelete: nil,
                    onSelect: nil,
                    onIndexIndicatorStateChange: { title, isVisible in
                        applyScrollIndexIndicatorState(
                            title: title,
                            isVisible: isVisible,
                            scrollIndexTitle: $scrollIndexTitle,
                            isScrollIndexVisible: $isScrollIndexVisible
                        )
                    }
                )
                .frame(height: listHeight)
            }

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct IndexedVocabularyList: UIViewRepresentable {
    let entries: [VocabularyEntry]
    let listHeight: CGFloat
    let selectedEntryID: String?
    let onDelete: ((VocabularyEntry) -> Void)?
    let onSelect: ((VocabularyEntry) -> Void)?
    let onIndexIndicatorStateChange: (String, Bool) -> Void

    private static let kanaIndexTitles: [String] = ["あ", "か", "さ", "た", "な", "は", "ま", "や", "ら", "わ"]
    private static let allIndexTitles: [String] = kanaIndexTitles
    private static let customIndexWidth: CGFloat = 28
    private static let customIndexVerticalInset: CGFloat = 4
    private static let customIndexFontSize: CGFloat = 12

    func makeCoordinator() -> Coordinator {
        Coordinator(
            entries: entries,
            listHeight: listHeight,
            selectedEntryID: selectedEntryID,
            onDelete: onDelete,
            onSelect: onSelect,
            onIndexIndicatorStateChange: onIndexIndicatorStateChange
        )
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView(frame: .zero)
        containerView.backgroundColor = .clear

        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Coordinator.cellReuseIdentifier)
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.rowHeight = 30
        tableView.separatorStyle = .none
        tableView.sectionIndexColor = .clear
        tableView.sectionIndexBackgroundColor = .clear
        tableView.sectionIndexTrackingBackgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let indexContainerView = UIView(frame: .zero)
        indexContainerView.backgroundColor = .clear
        indexContainerView.translatesAutoresizingMaskIntoConstraints = false
        indexContainerView.isUserInteractionEnabled = true

        let indexStackView = UIStackView(frame: .zero)
        indexStackView.axis = .vertical
        indexStackView.alignment = .fill
        indexStackView.distribution = .fillEqually
        indexStackView.spacing = 0
        indexStackView.translatesAutoresizingMaskIntoConstraints = false

        indexContainerView.addSubview(indexStackView)
        containerView.addSubview(tableView)
        containerView.addSubview(indexContainerView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: containerView.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            indexContainerView.topAnchor.constraint(
                equalTo: tableView.topAnchor,
                constant: Self.customIndexVerticalInset
            ),
            indexContainerView.bottomAnchor.constraint(
                equalTo: tableView.bottomAnchor,
                constant: -Self.customIndexVerticalInset
            ),
            indexContainerView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor, constant: -2),
            indexContainerView.widthAnchor.constraint(equalToConstant: Self.customIndexWidth),

            indexStackView.topAnchor.constraint(equalTo: indexContainerView.topAnchor),
            indexStackView.bottomAnchor.constraint(equalTo: indexContainerView.bottomAnchor),
            indexStackView.leadingAnchor.constraint(equalTo: indexContainerView.leadingAnchor),
            indexStackView.trailingAnchor.constraint(equalTo: indexContainerView.trailingAnchor)
        ])

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCustomIndexTap(_:))
        )
        indexContainerView.addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCustomIndexPan(_:))
        )
        panGesture.maximumNumberOfTouches = 1
        indexContainerView.addGestureRecognizer(panGesture)

        context.coordinator.attach(
            tableView: tableView,
            indexContainerView: indexContainerView,
            indexStackView: indexStackView
        )

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let needsReload = context.coordinator.update(
            entries: entries,
            listHeight: listHeight,
            selectedEntryID: selectedEntryID,
            onDelete: onDelete,
            onSelect: onSelect,
            onIndexIndicatorStateChange: onIndexIndicatorStateChange
        )

        if needsReload {
            context.coordinator.reloadData()
        } else {
            context.coordinator.refreshCustomIndexPresentation()
        }
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
        private var listHeight: CGFloat
        private var selectedEntryID: String?
        private var onDelete: ((VocabularyEntry) -> Void)?
        private var onSelect: ((VocabularyEntry) -> Void)?
        private var onIndexIndicatorStateChange: (String, Bool) -> Void
        private var groupedEntries: [String: [VocabularyEntry]] = [:]
        private var visibleSectionTitles: [String] = []
        private var overlayHideWorkItem: DispatchWorkItem?
        private var currentIndexIndicatorTitle = ""
        private weak var tableView: UITableView?
        private weak var indexContainerView: UIView?
        private weak var indexStackView: UIStackView?
        private var displayedIndexTitles: [String] = []
        private var isRowSwipeActionVisible = false
        private var entriesStorageIdentity: UInt

        init(
            entries: [VocabularyEntry],
            listHeight: CGFloat,
            selectedEntryID: String?,
            onDelete: ((VocabularyEntry) -> Void)?,
            onSelect: ((VocabularyEntry) -> Void)?,
            onIndexIndicatorStateChange: @escaping (String, Bool) -> Void
        ) {
            self.entries = entries
            self.listHeight = listHeight
            self.selectedEntryID = selectedEntryID
            self.onDelete = onDelete
            self.onSelect = onSelect
            self.onIndexIndicatorStateChange = onIndexIndicatorStateChange

            if onDelete == nil {
                isRowSwipeActionVisible = false
            }
            self.entriesStorageIdentity = Self.storageIdentity(for: entries)
            super.init()
            rebuildSections()
        }

        private static func storageIdentity(for entries: [VocabularyEntry]) -> UInt {
            let baseAddress: UInt = entries.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else {
                    return 0
                }
                return UInt(bitPattern: base)
            }

            return baseAddress ^ UInt(entries.count)
        }

        private static func hasDifferentEntryIDs(
            _ lhs: [VocabularyEntry],
            _ rhs: [VocabularyEntry]
        ) -> Bool {
            guard lhs.count == rhs.count else {
                return true
            }

            for index in lhs.indices {
                if lhs[index].id != rhs[index].id {
                    return true
                }
            }

            return false
        }

        func attach(tableView: UITableView, indexContainerView: UIView, indexStackView: UIStackView) {
            self.tableView = tableView
            self.indexContainerView = indexContainerView
            self.indexStackView = indexStackView
            tableView.reloadData()
            tableView.layoutIfNeeded()
            refreshCustomIndexPresentation()
            schedulePostLayoutCustomIndexRefresh()
        }

        func reloadData() {
            tableView?.reloadData()
            tableView?.layoutIfNeeded()
            refreshCustomIndexPresentation()
            schedulePostLayoutCustomIndexRefresh()
        }

        func refreshCustomIndexPresentation() {
            refreshCustomIndexTitles()
            refreshCustomIndexVisibility()
        }

        private var isCustomIndexInteractionEnabled: Bool {
            guard onDelete != nil else {
                return true
            }

            return !isRowSwipeActionVisible
        }

        private var customIndexLabelColor: UIColor {
            if isCustomIndexInteractionEnabled {
                return .systemBlue
            }

            return UIColor.systemBlue.withAlphaComponent(0.58)
        }

        private func refreshCustomIndexInteractionState() {
            indexContainerView?.isUserInteractionEnabled = isCustomIndexInteractionEnabled
            updateCustomIndexLabelAppearance()
        }

        private func updateCustomIndexLabelAppearance() {
            guard let indexStackView else {
                return
            }

            let color = customIndexLabelColor

            for arrangedSubview in indexStackView.arrangedSubviews {
                guard let label = arrangedSubview as? UILabel else {
                    continue
                }

                if label.textColor != color {
                    label.textColor = color
                }
            }
        }

        private func schedulePostLayoutCustomIndexRefresh() {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.refreshCustomIndexTitles()
                self.refreshCustomIndexVisibility()
            }
        }

        @discardableResult
        func update(
            entries: [VocabularyEntry],
            listHeight: CGFloat,
            selectedEntryID: String?,
            onDelete: ((VocabularyEntry) -> Void)?,
            onSelect: ((VocabularyEntry) -> Void)?,
            onIndexIndicatorStateChange: @escaping (String, Bool) -> Void
        ) -> Bool {
            let nextEntriesStorageIdentity = Self.storageIdentity(for: entries)
            let entriesChanged: Bool

            if entriesStorageIdentity == nextEntriesStorageIdentity {
                entriesChanged = false
            } else {
                entriesChanged = Self.hasDifferentEntryIDs(self.entries, entries)
                entriesStorageIdentity = nextEntriesStorageIdentity
            }

            let deleteAvailabilityChanged = (self.onDelete != nil) != (onDelete != nil)
            let selectAvailabilityChanged = (self.onSelect != nil) != (onSelect != nil)
            let selectedEntryChanged = self.selectedEntryID != selectedEntryID
            let listHeightChanged = abs(self.listHeight - listHeight) > 0.5

            self.entries = entries
            self.listHeight = listHeight
            self.selectedEntryID = selectedEntryID
            self.onDelete = onDelete
            self.onSelect = onSelect
            self.onIndexIndicatorStateChange = onIndexIndicatorStateChange

            if entriesChanged {
                rebuildSections()
            }

            return entriesChanged
                || deleteAvailabilityChanged
                || selectAvailabilityChanged
                || selectedEntryChanged
                || listHeightChanged
        }

        func refreshCustomIndexVisibility() {
            if visibleSectionTitles.isEmpty {
                hideScrollingIndexOverlayImmediately()
            }

            indexContainerView?.isHidden = displayedIndexTitles.isEmpty || !canScrollInTableView()
            refreshCustomIndexInteractionState()
        }

        private func refreshCustomIndexTitles() {
            guard let indexStackView else {
                return
            }

            let nextTitles: [String] = visibleSectionTitles.count > 1 && canScrollInTableView()
                ? visibleSectionTitles
                : []

            if displayedIndexTitles == nextTitles {
                indexContainerView?.isHidden = nextTitles.isEmpty
                refreshCustomIndexInteractionState()
                return
            }

            displayedIndexTitles = nextTitles

            for arrangedSubview in indexStackView.arrangedSubviews {
                indexStackView.removeArrangedSubview(arrangedSubview)
                arrangedSubview.removeFromSuperview()
            }

            for title in nextTitles {
                let label = UILabel()
                label.text = title
                label.font = UIFont.systemFont(ofSize: IndexedVocabularyList.customIndexFontSize, weight: .semibold)
                label.textColor = customIndexLabelColor
                label.textAlignment = .center
                label.isUserInteractionEnabled = false
                indexStackView.addArrangedSubview(label)
            }

            indexContainerView?.isHidden = nextTitles.isEmpty
            refreshCustomIndexInteractionState()
        }

        private func canScrollInTableView() -> Bool {
            guard listHeight > 1 else {
                return false
            }

            let totalRows = visibleSectionTitles.reduce(0) { partialResult, title in
                partialResult + (groupedEntries[title]?.count ?? 0)
            }
            let rowHeight = tableView?.rowHeight ?? 30
            let resolvedRowHeight = rowHeight > 0 ? rowHeight : 30
            let contentHeight = CGFloat(totalRows) * resolvedRowHeight

            return contentHeight > listHeight + 1
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

        private func sectionIndexTitlesForCustomIndex() -> [String] {
            displayedIndexTitles
        }

        private func dismissVisibleSwipeActionImmediately() {
            guard isRowSwipeActionVisible,
                let tableView else {
                return
            }

            tableView.setEditing(false, animated: false)
            isRowSwipeActionVisible = false
            refreshCustomIndexInteractionState()
        }

        private func customIndexTitle(for locationY: CGFloat, in indexView: UIView) -> String? {
            let titles = sectionIndexTitlesForCustomIndex()

            guard !titles.isEmpty, indexView.bounds.height > 0 else {
                return nil
            }

            let clampedY = min(max(locationY, 0), max(0, indexView.bounds.height - 0.5))
            let slotHeight = indexView.bounds.height / CGFloat(titles.count)

            guard slotHeight > 0 else {
                return nil
            }

            let slot = min(titles.count - 1, max(0, Int(clampedY / slotHeight)))
            return titles[slot]
        }

        private func scrollToCustomIndexTitle(_ title: String, animated: Bool) {
            guard let tableView else {
                return
            }

            let titleIndex = IndexedVocabularyList.allIndexTitles.firstIndex(of: title) ?? 0
            let section = resolveSection(for: title, at: titleIndex)

            guard section < visibleSectionTitles.count else {
                return
            }

            let rowCount = tableView.numberOfRows(inSection: section)
            guard rowCount > 0 else {
                return
            }

            tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: animated)
        }

        @objc func handleCustomIndexTap(_ gesture: UITapGestureRecognizer) {
            guard isCustomIndexInteractionEnabled else {
                dismissVisibleSwipeActionImmediately()
                return
            }

            guard gesture.state == .ended,
                let indexView = gesture.view,
                let title = customIndexTitle(for: gesture.location(in: indexView).y, in: indexView) else {
                return
            }

            scrollToCustomIndexTitle(title, animated: true)
            showScrollingIndexOverlay(title: title)
            scheduleHideScrollingIndexOverlay()
        }

        @objc func handleCustomIndexPan(_ gesture: UIPanGestureRecognizer) {
            guard isCustomIndexInteractionEnabled else {
                dismissVisibleSwipeActionImmediately()
                if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                    scheduleHideScrollingIndexOverlay()
                }
                return
            }

            guard let indexView = gesture.view else {
                return
            }

            switch gesture.state {
            case .began, .changed:
                guard let title = customIndexTitle(for: gesture.location(in: indexView).y, in: indexView) else {
                    return
                }

                scrollToCustomIndexTitle(title, animated: false)
                showScrollingIndexOverlay(title: title)
            case .ended, .cancelled, .failed:
                scheduleHideScrollingIndexOverlay()
            default:
                break
            }
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
            showScrollingIndexOverlay(title: title)
            scheduleHideScrollingIndexOverlay()
            return resolveSection(for: title, at: index)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? UITableView else {
                return
            }

            dismissVisibleSwipeActionImmediately()

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

            let isSelected = entry.id == selectedEntryID

            cell.textLabel?.text = nil
            cell.backgroundColor = isSelected
                ? UIColor.systemBlue.withAlphaComponent(0.18)
                : UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.95)
            cell.selectionStyle = .none

            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            let selectedEntry = entry(at: indexPath)
            onSelect?(selectedEntry)
            tableView.deselectRow(at: indexPath, animated: true)
        }

        func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
            guard onDelete != nil else {
                return
            }

            isRowSwipeActionVisible = true
            refreshCustomIndexInteractionState()
        }

        func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
            guard onDelete != nil else {
                return
            }

            isRowSwipeActionVisible = false
            refreshCustomIndexInteractionState()
        }

        func tableView(
            _ tableView: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard let onDelete else {
                return nil
            }

            let target = entry(at: indexPath)

            let delete = UIContextualAction(style: .destructive, title: "削除") { _, _, completion in
                onDelete(target)
                completion(true)
            }

            return UISwipeActionsConfiguration(actions: [delete])
        }
    }
}
