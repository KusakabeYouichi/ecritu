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

struct IdleCommitSettingsSection: View {
    @Binding var idleCommitEnabled: Bool
    @Binding var idleCommitInterval: Double

    private func isAtDefault(_ value: Double, default defaultValue: Double) -> Bool {
        abs(value - defaultValue) <= 0.001
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自動確定(アイドル)")
                .font(.headline)

            Toggle("入力が止まったら未確定を自動確定", isOn: $idleCommitEnabled)
                .font(.subheadline.weight(.semibold))
                .tint(Color.orange)

            if idleCommitEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("確定までの待ち時間")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        if isAtDefault(idleCommitInterval, default: IdleCommitSettings.intervalDefault) {
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
                        Text("\(idleCommitInterval.formatted(.number.precision(.fractionLength(1)))) 秒")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $idleCommitInterval, in: IdleCommitSettings.intervalRange, step: 0.1)
                        .tint(Color.orange)

                    HStack {
                        Text("デフォルト: \(IdleCommitSettings.intervalDefault.formatted(.number.precision(.fractionLength(1)))) 秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        if !isAtDefault(idleCommitInterval, default: IdleCommitSettings.intervalDefault) {
                            Button("デフォルトに戻す") {
                                idleCommitInterval = IdleCommitSettings.intervalDefault
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }

            Text("先行する確定文字があると、未確定(下線)は送信時に切り捨てられます(iOSの拡張キーボード共通の制約)。入力が上の時間だけ止まると未確定を確定して送信に乗せます。行頭から全部が未確定のときは元々送信に乗るため対象外です。")
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
    let failSafeProfile: String
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
                Text("fail-safe: \(failSafeProfile)")
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

struct KanaPostModifierEmptyTapAssignmentSection: View {
    @Binding var actionSelection: KanaPostModifierEmptyTapActionOption
    @Binding var kaomojiCategoryID: String
    @Binding var emojiCategoryID: String
    @Binding var symbolCategoryID: String

    private var currentCategoryDescriptors: [CategoryChoiceDescriptor] {
        switch actionSelection {
        case .kaomoji: return KaomojiCategoryChoice.all
        case .emoji: return EmojiCategoryChoice.all
        case .symbols: return SymbolCategoryChoice.all
        }
    }

    private var currentCategoryBinding: Binding<String> {
        switch actionSelection {
        case .kaomoji: return $kaomojiCategoryID
        case .emoji: return $emojiCategoryID
        case .symbols: return $symbolCategoryID
        }
    }

    private var currentCategoryFallback: String {
        switch actionSelection {
        case .kaomoji: return KaomojiCategoryChoice.defaultID
        case .emoji: return EmojiCategoryChoice.defaultID
        case .symbols: return SymbolCategoryChoice.defaultID
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                DakutenDuckCompositeIconView()
                    .frame(width: 18, height: 18)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[VerticalAlignment.center] + 6
                    }
                Text("タップ (後置修飾、未確定なし)")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            VStack(spacing: 8) {
                ForEach(KanaPostModifierEmptyTapActionOption.allCases) { option in
                    let isSelected = actionSelection == option

                    Button {
                        actionSelection = option
                    } label: {
                        HStack(spacing: 9) {
                            Text(option.iconLabel)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(width: 38, alignment: .center)

                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
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
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("切替時に開くカテゴリー")
                    .font(.subheadline.weight(.semibold))

                Picker("カテゴリー", selection: currentCategoryBinding) {
                    ForEach(currentCategoryDescriptors) { descriptor in
                        Text("\(descriptor.icon)  \(descriptor.title)").tag(descriptor.id)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    let validIDs = Set(currentCategoryDescriptors.map(\.id))

                    if !validIDs.contains(currentCategoryBinding.wrappedValue) {
                        currentCategoryBinding.wrappedValue = currentCategoryFallback
                    }
                }
                .onChange(of: actionSelection) { _ in
                    let validIDs = Set(currentCategoryDescriptors.map(\.id))

                    if !validIDs.contains(currentCategoryBinding.wrappedValue) {
                        currentCategoryBinding.wrappedValue = currentCategoryFallback
                    }
                }
            }

            Text("後置修飾モードで未確定文字がないときに修飾キーをタップしたとき切り替える入力モードと、初期表示するカテゴリーを指定します。切り替え先で1つ確定すると自動的にかな入力モードへ戻ります。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct KanaPostModifierFlickDakutenSettingsSection: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isEnabled) {
                Text("後置修飾キーのフリックで濁点・半濁点")
                    .font(.headline)
            }

            Text("オンの場合、後置修飾キーを上フリックで濁点(゛)、右フリックで半濁点(゜)を強制します。オフにすると上/右フリックは中央タップと同じ扱いになり、誤って「つ→づ」になるのを抑止できます(2タップで「つ→っ→づ」は引き続き可能)。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct DelimiterAutoCommitCandidateSettingsSection: View {
    @Binding var selection: DelimiterAutoCommitCandidateOption

    var body: some View {
        SegmentedSettingsCard(
            title: "句読点入力時の自動確定候補",
            pickerTitle: "句読点入力時の自動確定候補",
            selection: $selection,
            options: Array(DelimiterAutoCommitCandidateOption.allCases),
            optionTitle: { $0.title },
            footnote: "未確定状態で句読点・記号を入力して自動確定するときに、どの候補を確定するかです。既定は「先頭の変換候補」。「未変換かな」は入力したひらがなをそのまま確定します(確定キーは設定に関わらず常に未変換かなを確定します)。"
        )
    }
}

struct ContactCandidateDisplaySettingsSection: View {
    @Binding var selection: ContactCandidateDisplayModeOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iOSの連絡先の姓、名、会社名")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(ContactCandidateDisplayModeOption.allCases) { option in
                    let isSelected = selection == option

                    Button {
                        selection = option
                    } label: {
                        HStack(alignment: .top, spacing: 9) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
        }
        .settingsCardStyle()
    }
}

struct UserDictionaryCandidateDisplaySettingsSection: View {
    @Binding var selection: UserDictionaryCandidateDisplayModeOption

    var body: some View {
        SegmentedSettingsCard(
            title: "iOSのユーザ辞書の単語",
            pickerTitle: "iOSのユーザ辞書の単語",
            selection: $selection,
            options: Array(UserDictionaryCandidateDisplayModeOption.allCases),
            optionTitle: { $0.title },
            footnote: "iOSの[設定]-[一般]-[キーボード]-[ユーザ辞書]に登録された候補を使うかどうかを切り替えます。"
        )
    }
}

struct EmojiKaomojiCandidateSettingsSection: View {
    @Binding var enablesEmojiCandidates: Bool
    @Binding var enablesKaomojiCandidates: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("emojis & les émoticônes")
                .font(.headline)

            VStack(spacing: 10) {
                Toggle("emoji 😀", isOn: $enablesEmojiCandidates)
                Toggle("émoticône (^_^)", isOn: $enablesKaomojiCandidates)
            }
            .toggleStyle(.switch)

            Text("かな漢字変換の候補に絵文字/顔文字を含めるかを切り替えます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct HistoricalKanaCandidatesSettingsSection: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("旧仮名遣い候補")
                .font(.headline)

            Toggle("旧仮名遣いの候補を含める", isOn: $isEnabled)
                .toggleStyle(.switch)

            Text("「かえる→変へる」「かんがえる→考へる」のような歴史的仮名遣い表記の候補を変換結果に含めるかを切り替えます。既定はオフ(現代仮名遣いのみ)。")
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

    var body: some View {
        SegmentedSettingsCard(
            title: "数字配列",
            pickerTitle: "数字配列",
            selection: $selection,
            options: Array(NumberLayoutOption.allCases),
            optionTitle: { $0.title },
            footnote: "123モードの数字キー配列を切り替えます。téléphone は上段が 1-2-3、calculette は上段が 7-8-9、clavier は AZERTY 風の数字+記号配列(shift で 2 種類の記号セットを切替)です。\nclavier は縦画面のみ対応。横画面では自動的に calculette が使われます。"
        )
    }
}

struct DateFormatStyleSettingsSection: View {
    @Binding var selection: DateFormatStyleOption

    var body: some View {
        SegmentedSettingsCard(
            title: "日付の書式",
            pickerTitle: "日付の書式",
            selection: $selection,
            options: Array(DateFormatStyleOption.allCases),
            optionTitle: { $0.title },
            footnote: "書式化数値モードのカレンダーで挿入する日付の方式です。米国式は 月→日→年(July 4th, 2026)、英国式は 日→月→年(4th July 2026)、フランス式は 日→月→年(1er juillet 2026)。方式に応じてドラムの書式候補と月名・曜日名が変わります。"
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
