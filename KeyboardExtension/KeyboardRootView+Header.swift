import SwiftUI

// 候補バー(ヘッダ)の構築。かな変換候補ヘッダ・ラテン候補ヘッダ・絵文字見出しを
// 入力モードに応じて出し分ける。実体の並び UI は KeyboardRootKanaCandidateHeaderView /
// KeyboardRootLatinSuggestionHeaderView(KeyboardRootViewSupportTypes)に委譲する。
extension KeyboardRootView {
    var topHeaderView: some View {
        Group {
            if inputMode == .emoji,
                emojiInputSubmode == .kanjiRadical,
                selectedRadicalForm != nil {
                // 部首ピッカーの字グリッド中はヘッダー自体を戻るボタンにする
                // (行内にもう1段パンくずを置くと二重になるため。2447)
                Button {
                    selectedRadicalForm = nil
                } label: {
                    Text("◀ \(emojiHeaderTitle)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 2)
                        .padding(.top, emojiHeaderTopPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("部首一覧へ戻る")
            } else if inputMode == .emoji {
                Text(emojiHeaderTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(keyLabelColor.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 2)
                    .padding(.top, emojiHeaderTopPadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else if showsKanaConversionCandidates {
                kanaConversionCandidateHeaderView
            } else if showsLatinSuggestionCandidates {
                latinSuggestionHeaderView
            } else if isSystemDictionaryFallback {
                // 変換辞書(sqlite)が開けない異常時の案内。フォールバックJSONの同梱を
                // やめた(2026-08-31 #4)ため、この状態では変換候補が出ない。劣化運転で
                // 誤魔化さず理由を明示する(アクセント灰色化と併用)
                Text("変換辞書を読み込めません。écritu の再インストールをお試しください")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(keyLabelColor.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 2)
                    .padding(.top, emojiHeaderTopPadding)
                    .allowsHitTesting(false)
            } else {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // 書式化数値モードは候補ヘッダーを使わないので畳み、カレンダー等を上に寄せる。
        .frame(height: inputMode == .formattedNumber ? 0 : candidateHeaderHeight)
    }

    private var kanaConversionCandidateHeaderView: some View {
        KeyboardRootKanaCandidateHeaderView(
            showsParenthesesWrapper: showsParenthesesWrapper,
            composingText: composingText,
            conversionStateLabel: conversionStateLabel,
            conversionStateIconName: conversionStateIconName,
            conversionStateColor: conversionStateColor,
            candidateStateFontSize: candidateStateFontSize,
            candidateTextFontSize: candidateTextFontSize,
            canTapComposingTextToCommit: canTapComposingTextToCommit,
            showsKatakanaCommitFeedback: isShowingKatakanaCommitFeedback(for: composingText),
            accentColor: accentColor,
            keyLabelColor: keyLabelColor,
            conversionCandidates: conversionCandidates,
            selectedConversionCandidateIndex: selectedConversionCandidateIndex,
            kanaCandidateHeaderTopPadding: kanaCandidateHeaderTopPadding,
            onSelectConversionCandidate: onSelectConversionCandidate,
            onComposingTextCommitTap: handleComposingTextCommitTap,
            onComposingTextCommitLongPress: handleComposingTextCommitLongPress
        )
    }

    private var latinSuggestionHeaderView: some View {
        KeyboardRootLatinSuggestionHeaderView(
            latinSuggestions: latinSuggestions,
            candidateTextFontSize: candidateTextFontSize,
            keyLabelColor: keyLabelColor,
            kanaCandidateHeaderTopPadding: kanaCandidateHeaderTopPadding,
            onSelectConversionCandidate: onSelectConversionCandidate
        )
    }
}
