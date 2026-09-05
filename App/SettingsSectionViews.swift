import SwiftUI
import UIKit
import UniformTypeIdentifiers

// 設定カード内の小見出し付き項目(複数セクションで共用)
@ViewBuilder
func settingsSubItem<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.subheadline.weight(.semibold))
        content()
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
                            Text("初期設定")
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
                        Text("初期設定: \(RepeatSettings.initialDelayDefault.formatted(.number.precision(.fractionLength(2)))) 秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        if !isAtRepeatDefault(
                            keyRepeatInitialDelay,
                            default: RepeatSettings.initialDelayDefault
                        ) {
                            Button("初期設定に戻す") {
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
                            Text("初期設定")
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
                        Text("初期設定: \(RepeatSettings.intervalDefault.formatted(.number.precision(.fractionLength(2)))) 秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        if !isAtRepeatDefault(
                            keyRepeatInterval,
                            default: RepeatSettings.intervalDefault
                        ) {
                            Button("初期設定に戻す") {
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
                            Text("初期設定")
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
                        Text("初期設定: \(IdleCommitSettings.intervalDefault.formatted(.number.precision(.fractionLength(1)))) 秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        if !isAtDefault(idleCommitInterval, default: IdleCommitSettings.intervalDefault) {
                            Button("初期設定に戻す") {
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
    // 先頭に出ているときだけ「手順を隠す」を見せる(押すと末尾のアプリ情報へ移る)
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("有効化手順")
                    .font(.headline)
                Spacer()
                if let onDismiss {
                    Button("手順を隠す", action: onDismiss)
                        .font(.footnote)
                }
            }

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(step)
                        .font(.subheadline)
                }
            }

            Text(
                "[フルアクセスを許可]がOFFでも文字入力と変換は使えますが、一部の機能が働きません: "
                    + "学習語彙・学習スコアの保存、追加語彙・抑制語彙のキーボードへの反映、"
                    + "このアプリで変えた設定の反映。ONにしてお使いになることをおすすめします。"
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

// 変換キャッシュのクリア。キーボード拡張はプロセス内に読みごとの候補キャッシュ(96件)を持ち、
// quick postfix 経路がそれを語幹の候補列として読むため内容が並びに影響する。設定変更の世代
// カウンタを +1 すると、キーボード側が次の表示または Darwin 通知で clearSharedDataCaches() を
// 呼んで候補キャッシュ・学習/追加語彙キャッシュを破棄する(語彙自体は消えない。2510)
struct ConversionCacheSettingsSection: View {
    @Binding var suspendMemorySlimmingEnabled: Bool
    @State private var isClearedBadgeVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("変換キャッシュ")
                .font(.headline)

            Toggle("キーボードが閉じたときにメモリを整理", isOn: $suspendMemorySlimmingEnabled)
                .toggleStyle(.switch)

            Text("キーボードが画面から消えるたびに、変換キャッシュの破棄と使い終わったメモリのシステムへの返却を行います。長時間使い続けたときにキーボードがシステムに強制終了されて標準キーボードに切り替わってしまう問題を抑えます。次回表示時のキャッシュ再構築ぶんだけ、最初の変換がわずかに遅くなることがあります。初期設定はオンです。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            Text("キーボードが持っている変換結果のキャッシュを破棄します。学習語彙や追加語彙は消えません。誤変換を直したのに『前の並びが残っている』ときに使ってください(キーボードを閉じて開き直すか、他のアプリに切り替えても破棄されます)。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("変換キャッシュをクリア") {
                    SettingsSyncNotification.postSettingsDidChange()
                    isClearedBadgeVisible = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        isClearedBadgeVisible = false
                    }
                }
                .buttonStyle(.bordered)

                if isClearedBadgeVisible {
                    Text("クリアしました")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsCardStyle()
    }
}

// キーボード/コンテナー診断の表示・コピー UI。開発ビルド専用(Release には型ごと存在しない。2785)
#if DEBUG
struct KeyboardDiagnosticsSection: View {
    let isSessionActive: Bool
    let failSafeProfile: String
    let lastHeartbeatText: String
    let lastEvent: String
    let lastSessionID: String
    let installMarker: String
    let logLines: [String]
    let launchCount: Int
    let attachFailureCount: Int
    let attachLateRecoveryCount: Int
    let onReload: () -> Void
    let onCopy: () -> Void
    let onCopyDetail: () -> Void
    let onClear: () -> Void

    // 診断ログは開発ビルド専用(#if !DEBUG で早期 return)。ログが空のときに構成の
    // 違いなのか異常なのかを画面で切り分けられるようにする(2564)
    private var buildConfigurationLabel: String {
        #if DEBUG
        return "Debug(診断ログ有効)"
        #else
        return "Release(診断ログ無効)"
        #endif
    }

    @State private var isClearConfirmationPresented = false
    @State private var isCopiedBadgeVisible = false
    // 更新の成否可視化: 内容が変わらない(たまたま最新だった)場合でも取得完了が
    // わかるよう、取得時刻付きのバッジを一時表示する
    @State private var reloadedBadgeText: String?

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
                // 診断ログは Debug 専用。ログが空のときに構成の違いか異常かを切り分ける
                Text("ビルド: \(buildConfigurationLabel)")
                Text("fail-safe: \(failSafeProfile)")
                // attach失敗頻度の観察用(コピーせず画面で読み取れるように常時表示)
                Text("起動\(launchCount)回 / 表示未到達\(attachFailureCount)回 / 遅延復帰\(attachLateRecoveryCount)回")
                Text("最終ハートビート: \(lastHeartbeatText)")
                Text("最終セッションID: \(lastSessionID.isEmpty ? "なし" : lastSessionID)")
                Text("最終イベント: \(lastEvent.isEmpty ? "なし" : lastEvent)")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("更新") {
                    onReload()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm:ss"
                    let timeText = formatter.string(from: Date())
                    withAnimation(.easeOut(duration: 0.16)) {
                        reloadedBadgeText = "更新しました(\(timeText)時点)"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            reloadedBadgeText = nil
                        }
                    }
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

                // 定型行を省かない全文コピー(コンパクト版で欠けた文脈が要るとき用)
                Button("詳細コピー") {
                    onCopyDetail()
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

                if let reloadedBadgeText {
                    Text(reloadedBadgeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isCopiedBadgeVisible {
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

#endif

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
