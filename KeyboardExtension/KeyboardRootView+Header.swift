import SwiftUI

// 候補バー(ヘッダ)の構築。かな変換候補ヘッダ・ラテン候補ヘッダ・絵文字見出しを
// 入力モードに応じて出し分ける。実体の並び UI は KeyboardRootKanaCandidateHeaderView /
// KeyboardRootLatinSuggestionHeaderView(KeyboardRootViewSupportTypes)に委譲する。
extension KeyboardRootView {
    var topHeaderView: some View {
        Group {
            if inputMode == .emoji,
                emojiInputSubmode == .kanjiRadical,
                radicalPickerState.selectedForm != nil {
                // 部首ピッカーの字グリッド中はヘッダー自体を戻るボタンにする
                // (行内にもう1段パンくずを置くと二重になるため。2447)
                Button {
                    radicalPickerState.clearForm()
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
            } else if candidateHeaderHeight == 0 {
                // 横画面の数字の面は候補欄の高さが 0。案内の文字だけが枠の上へはみ出し、背景とずれて見えた(3570)。
                // 横画面のかな・ラテン文字の面も案内を出していないのでそろえる
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
            } else if showsFullAccessNotice, inputMode != .number, inputMode != .formattedNumber {
                // 数字・書式化数値の面には出さない(ユーザー指定 3570。案内はかなの面で足りる)。
                // 書式化数値は候補欄の高さを 0 に畳むので、出すと案内がテンキーに重なる
                fullAccessNoticeHeaderView
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
            internalCompositionPreviewText: internalCompositionPreviewText,
            conversionStateLabel: conversionStateLabel,
            conversionStateIconName: conversionStateIconName,
            conversionStateColor: conversionStateColor,
            candidateStateFontSize: candidateStateFontSize,
            candidateTextFontSize: candidateTextFontSize,
            candidateTextFontWeight: candidateTextFontWeight,
            reservesCompositionRow: reservesCandidateCompositionRow,
            canTapComposingTextToCommit: canTapComposingTextToCommit,
            showsKatakanaCommitFeedback: isShowingKatakanaCommitFeedback(for: composingText),
            accentColor: accentColor,
            keyLabelColor: keyLabelColor,
            conversionCandidates: conversionCandidates,
            selectedConversionCandidateIndex: selectedConversionCandidateIndex,
            kanaCandidateHeaderTopPadding: kanaCandidateHeaderTopPadding,
            tapExtension: candidateChipTapExtension,
            onSelectConversionCandidate: onSelectConversionCandidate,
            onComposingTextCommitTap: handleComposingTextCommitTap,
            onComposingTextCommitLongPress: handleComposingTextCommitLongPress
        )
    }

    private var latinSuggestionHeaderView: some View {
        KeyboardRootLatinSuggestionHeaderView(
            latinSuggestions: latinSuggestions,
            candidateTextFontSize: candidateTextFontSize,
            candidateTextFontWeight: candidateTextFontWeight,
            reservesCompositionRow: reservesCandidateCompositionRow,
            keyLabelColor: keyLabelColor,
            kanaCandidateHeaderTopPadding: kanaCandidateHeaderTopPadding,
            tapExtension: candidateChipTapExtension,
            onSelectConversionCandidate: onSelectConversionCandidate
        )
    }

    // 候補チップの当たり判定を見た目の下へ広げる幅(ユーザ指定 3818)。縦画面で未確定の行を取る(チップが上寄せ)ときだけ。
    // チップの真下にだけ透明の当たり判定を置き、候補欄ごとキーより手前に出す(本体の zIndex)。候補欄の枠(横スクロール)を
    // 延ばすとチップの無い所でもキーの上端を奪うので延ばさない。候補の無い面(絵文字・数字)や横画面は今までどおり
    // 値は 候補欄の枠の下端から: 枠とキーの間の隙間(段の間隔)+キーの上端に食い込む幅(6pt)。チップの下端から枠の下端までの
    // 余白はチップ側(CandidateChipTapExtensionStrip)で足す
    static let candidateChipTapIntoKeyHeight: CGFloat = 6
    var candidateChipTapExtension: CGFloat {
        guard !isLandscapeLayout, reservesCandidateCompositionRow,
            showsKanaConversionCandidates || showsLatinSuggestionCandidates else {
            return 0
        }
        return keyboardRowSpacing + Self.candidateChipTapIntoKeyHeight
    }

    // 候補欄の重なり順。チップの当たり判定をキーに重ねているとき(candidateChipTapExtension > 0)だけキーより手前に出し、
    // キーを押しているあいだはキーを手前に戻す(3819)。当たり判定を重ねていない面(絵文字・顔文字・記号・単漢字・
    // 書式化数値・数字、横画面)では手前に出さない: 3818 からこれらの面でも手前に出ていて、[あい]の長押しの盤が
    // 題字(分類名)の下に隠れていた(ユーザ報告 3838)
    var topHeaderZIndex: Double {
        candidateChipTapExtension > 0 && activeLayerIndex == nil && !isTouchingLeftModeSwitchColumn ? 1 : 0
    }
}
