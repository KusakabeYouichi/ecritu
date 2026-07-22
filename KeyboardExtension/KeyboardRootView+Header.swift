import SwiftUI

// 候補バー(ヘッダ)の構築。かな変換候補ヘッダ・ラテン候補ヘッダ・絵文字見出しを
// 入力モードに応じて出し分ける。実体の並び UI は KeyboardRootKanaCandidateHeaderView /
// KeyboardRootLatinSuggestionHeaderView(KeyboardRootViewSupportTypes)に委譲する。
extension KeyboardRootView {
    var topHeaderView: some View {
        Group {
            if inputMode == .emoji {
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
            } else {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: candidateHeaderHeight)
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
