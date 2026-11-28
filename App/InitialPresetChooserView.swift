import SwiftUI

// 初めて開いたときに、3 つの初期設定から 1 つ選ぶ画面(ユーザ指定 3926)。表示だけを持ち、選んだ結果は onChoose で返す。
// 色は 3 つのテーマカラー(bleu / sakura / chartreuse)のパステルで、カードの面はその初期設定のテーマカラー、
// アイコンと枠は初期設定ごとの印の色(SettingsBasePreset.markColor)。ダークモードでも同じ見た目にする(呼び出し側でライトに固定)
struct InitialPresetChooserView: View {
    // カードの並び。マニュアルの[どれを選ぶか]が勧める順(多くの人は現代的か保守的)
    static let presetOrder: [SettingsBasePreset] = [.contemporary, .conservative, .strategic]

    // 起動処理が終わるまで false(始めるボタンを押せない)
    var isStartEnabled = true
    // 何も変えずに閉じる(デバッグ版の「選ぶ画面を出す」から出したときだけ渡す。初めてのインストールでは nil=必ず選ぶ)
    var onCancel: (() -> Void)? = nil
    let onChoose: (SettingsBasePreset) -> Void
    // 最初に選ばれているのは現代的初期設定(選ぶ前に当たっている設定と同じ)
    @State private var selection: SettingsBasePreset = .contemporary

    private static let inkColor = Color(red: 0.16, green: 0.18, blue: 0.25)
    private static let secondaryInkColor = Color(red: 0.16, green: 0.18, blue: 0.25).opacity(0.72)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(Self.presetOrder, id: \.self) { preset in
                    InitialPresetCard(
                        preset: preset,
                        isSelected: preset == selection,
                        inkColor: Self.inkColor,
                        secondaryInkColor: Self.secondaryInkColor
                    ) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selection = preset
                        }
                    }
                }
                laterNote
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            startButton
        }
        .background(InitialPresetChooserBackground().ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("初期設定を選んでください")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Self.inkColor)
                .fixedSize(horizontal: false, vertical: true)
            // 後から変えられることは、スクロールしなくても見える見出しの下に書く(ユーザ指定)。変え方は下の laterNote
            Text("écritu は、配列や表記の好みを最初に決めておくキーボードです。どれを選んでも、あとから変えられます。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Self.secondaryInkColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // 後から変える方法(ユーザ指定)。変える場所は アイコンのメニュー(初期設定の選び直し)と 設定の一覧(個々の項目)
    private var laterNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("あとから変えるには")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Self.inkColor)
            Text("設定の画面の上にある四角いアイコンに触れると、初期設定を選び直すメニューが出ます。個々の設定も、1つずつ自由に変えられます。")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Self.secondaryInkColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
        .accessibilityElement(children: .combine)
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            Button {
                onChoose(selection)
            } label: {
                Text(isStartEnabled ? "この設定で始める" : "準備しています…")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: 524)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selection.markColor.opacity(isStartEnabled ? 1 : 0.45))
                    )
                    .shadow(color: selection.markColor.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!isStartEnabled)
            .accessibilityLabel(isStartEnabled ? "\(selection.title)で始める" : "準備しています")
            if let onCancel {
                Button("やめる(今の設定のまま戻る)", action: onCancel)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Self.inkColor)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

// 初期設定 1 つぶんのカード。面はその初期設定のテーマカラー。選ばれているカードは印の色の枠とチェック
private struct InitialPresetCard: View {
    let preset: SettingsBasePreset
    let isSelected: Bool
    let inkColor: Color
    let secondaryInkColor: Color
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    iconBadge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.title)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(inkColor)
                        Text(preset.chooserAudience)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(secondaryInkColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    selectionMark
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(preset.chooserPoints, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle()
                                .fill(preset.markColor)
                                .frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                            Text(point)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(inkColor.opacity(0.86))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: ContentView.themeColorOption(for: preset).gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? preset.markColor : Color.white.opacity(0.9), lineWidth: isSelected ? 3 : 1.5)
            )
            .shadow(color: preset.markColor.opacity(isSelected ? 0.28 : 0.10), radius: isSelected ? 12 : 6, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 44, height: 44)
            if let icon = preset.menuAction.presetIcon {
                LogoMenuPresetIconView(icon: icon, size: 26)
                    .foregroundStyle(preset.markColor)
            }
        }
        .accessibilityHidden(true)
    }

    private var selectionMark: some View {
        ZStack {
            Circle()
                .fill(isSelected ? preset.markColor : Color.white.opacity(0.7))
                .frame(width: 28, height: 28)
            Circle()
                .stroke(isSelected ? preset.markColor : inkColor.opacity(0.25), lineWidth: 1.5)
                .frame(width: 28, height: 28)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .accessibilityHidden(true)
    }
}

// 背景: 3 つのテーマカラーを斜めに流し、ぼかした丸を重ねる
private struct InitialPresetChooserBackground: View {
    var body: some View {
        let bleu = KeyboardBackgroundThemeOption.bleu.gradientColors
        let sakura = KeyboardBackgroundThemeOption.sakura.gradientColors
        let chartreuse = KeyboardBackgroundThemeOption.chartreuse.gradientColors
        ZStack {
            LinearGradient(
                colors: [sakura[1], bleu[1], chartreuse[1]],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GeometryReader { proxy in
                let side = max(proxy.size.width, proxy.size.height)
                Circle()
                    .fill(sakura[0])
                    .frame(width: side * 0.75, height: side * 0.75)
                    .blur(radius: 60)
                    .offset(x: -side * 0.30, y: -side * 0.22)
                Circle()
                    .fill(bleu[0])
                    .frame(width: side * 0.70, height: side * 0.70)
                    .blur(radius: 60)
                    .offset(x: proxy.size.width - side * 0.42, y: proxy.size.height * 0.30)
                Circle()
                    .fill(chartreuse[0])
                    .frame(width: side * 0.70, height: side * 0.70)
                    .blur(radius: 60)
                    .offset(x: -side * 0.18, y: proxy.size.height - side * 0.40)
            }
        }
    }
}

#if DEBUG
// デバッグ版専用: 選ぶ画面をもう一度出す行(3926)。選ぶ画面は初めてのインストールにしか出ないので、既存の端末で確かめる手段
struct InitialPresetChooserDebugRow: View {
    let onShow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("初期設定を選ぶ画面(デバッグ版専用)")
                .font(.headline)
            Text("初めて開いたときの画面をもう一度出します。[この設定で始める]を押すと、今の設定はすべてその初期設定に置き換わります(連絡先の候補は[使わない]になります)。[やめる]を押せば、何も変えずに戻ります。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("選ぶ画面を出す", action: onShow)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif

// 選ぶ画面のカードの文。事実は確認ダイアログの文(logoMenuConfirmationMessage)とマニュアルの[初期設定]の章に合わせる。
// 初期設定の値を変えたら、ここも合わせること
extension SettingsBasePreset {
    // どんな人に向くか(1 行)
    var chooserAudience: String {
        switch self {
        case .contemporary: return "若い人や、効率よく入力したい人に"
        case .conservative: return "Apple 純正に慣れている人に"
        case .strategic: return "新しい配列に慣れる時間がある人に"
        }
    }

    // ほかの 2 つとの違いが分かる 3 点(かなの配列、ラテン文字と数字、表記)
    var chooserPoints: [String] {
        switch self {
        case .contemporary:
            return [
                "かなは 3×3+わ(今までのフリック入力のまま)",
                "ラテン文字は AZERTY、数字は clavier",
                "所謂・即ち・事 などはかなで書く。書きかえは本来の漢字が先"
            ]
        case .conservative:
            return [
                "かなは 3×3+わ、ラテン文字も 3×3、数字は téléphone",
                "所謂・即ち・下さい などの漢字の候補も残す",
                "書きかえは常用漢字が先"
            ]
        case .strategic:
            return [
                "かなは 5×2。いちばん上の段に数字1〜0が並ぶ",
                "小文字・濁点のキーは、かなを打つ前に押す",
                "ラテン文字は AZERTY、数字は calculette"
            ]
        }
    }
}
