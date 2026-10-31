import SwiftUI
import UIKit
import CoreFoundation
import Darwin

extension KeyboardRootView {
    var usesLandscapeKanaCandidateSidebar: Bool {
        isLandscapeLayout && inputMode == .kana
    }

    var usesLandscapeLatinSuggestionSidebar: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && landscapeLatinSuggestionMode == .sidebar
    }

    // 広い横画面(iPhone Duo の内画面)の候補欄: 幅をキー側と半々にし、7 つ以上で 2 列(3570)
    var usesWideLandscapeSidebar: Bool {
        usesWideLandscapeLayout && isLandscapeLayout
    }

    var usesLandscapeLatinTypewriterLayout: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty)
    }

    var landscapeLatinInlineReturnRowIndex: Int {
        // Keep return key directly under delete: right of L (QWERTY) / m (AZERTY).
        1
    }

    var landscapeLatinInlinePunctuationKeys: [FlickKanaSet] {
        let marks: [String] = latinLayoutMode == .qwerty
            ? [",", "/"]
            : [",", "/", "'"]

        return marks.map { mark in
            // AZERTY の「'」は縦向きと同じ定義(中心 '、左フリック ’。3515)。QWERTY は中段右端に別に置く
            if mark == "'" {
                return Self.latinApostropheKey
            }
            return FlickKanaSet(
                label: mark,
                center: mark,
                up: "",
                right: "",
                down: "",
                left: ""
            )
        }
    }

    var landscapeNumberSymbolPanelRows: [[String]] {
        // Custom landscape number-side companion symbols (4 rows x 6 columns).
        let rows = [
            ["+", "€", "℃", "mm", "mg", "ml"],
            ["-", "$", "℉", "cm", "cg", "cl"],
            ["±", "¥", "°", "m", "g", "l"],
            ["(", ")", "/", "km", "kg", "kl"]
        ]
        guard usesWideLandscapeSidebar else {
            return rows
        }
        // 広い横画面は + の列と € の列の間に 2 列足す(ユーザー指定 3570)
        let wideExtraColumns = [["×", "%"], ["÷", "#"], ["=", "〜"], [",", ":"]]
        return zip(rows, wideExtraColumns).map { row, extra in
            [row[0]] + extra + row.dropFirst()
        }
    }

    // 横画面の数字の面の、面切替の列を除いた固定の列(数字 3・機能 1)。記号の列(6、広い横画面は 8)はこの後ろに並ぶ
    static let landscapeNumberFixedKeyColumnCount = 4

    func isLandscapeLatinRightShiftKey(_ kana: FlickKanaSet) -> Bool {
        kana.label == "__latin_shift_right__"
    }

    var landscapeLatinRightShiftKey: FlickKanaSet {
        FlickKanaSet(
            label: "__latin_shift_right__",
            center: FlickKanaLayout.latinShiftKeyToken,
            up: "",
            right: "",
            down: "",
            left: ""
        )
    }

    func landscapeBottomRowWithInlinePunctuation(_ row: [FlickKanaSet]) -> [FlickKanaSet] {
        var augmentedRow = row

        // QWERTY rows don't include a right-shift token in source rows; add it back in landscape.
        if latinLayoutMode == .qwerty,
            !augmentedRow.contains(where: isLandscapeLatinRightShiftKey) {
            augmentedRow.append(landscapeLatinRightShiftKey)
        }

        guard let rightShiftIndex = augmentedRow.firstIndex(where: isLandscapeLatinRightShiftKey) else {
            return augmentedRow
        }

        augmentedRow.insert(contentsOf: landscapeLatinInlinePunctuationKeys, at: rightShiftIndex)
        return augmentedRow
    }

    var landscapeKanaCandidateSide: LandscapeCandidateSide {
        LandscapeCandidateSide(rawValue: landscapeCandidateSideRawValue) ?? .left
    }

    var landscapeNumberPaneSide: LandscapeCandidateSide {
        LandscapeCandidateSide(rawValue: landscapeNumberPaneSideRawValue) ?? .left
    }

    var landscapeLatinSuggestionMode: LandscapeLatinSuggestionMode {
        LandscapeLatinSuggestionMode(rawValue: landscapeLatinSuggestionModeRawValue) ?? .sidebar
    }

    var usesLandscapeCompactNumberLayout: Bool {
        isLandscapeLayout
            && inputMode == .number
            && usesThreeByThreeGridForNumberOrLatin
    }

    var isLandscapeLatinThreeByThreeMode: Bool {
        isLandscapeLayout
            && inputMode == .latin
            && usesThreeByThreeGridForNumberOrLatin
    }

    var landscapeNumberNarrowGrid: some View {
        let rowHeight = mainFlickKeyHeight
        let rowSpacing: CGFloat = keyboardRowSpacing
        // Keep number-mode keys the same width as mode-switch keys.
        // ただし窓に収まらないときは縮める。Duo の内画面(13 列を 801pt)と外画面の横(11 列を約 530pt。左端の
        // 面切替の列が窓の外に出て切り替えられなかった)で起きた(3570)。面切替の列は 58pt のまま
        // 縮めるのは Duo だけ(普通の iPhone は従来どおり 58pt)
        var keyWidth = leftModeSwitchButtonWidth
        if usesWideLandscapeSidebar || isFoldablePhone, keyboardContainerWidth > 0 {
            let keyColumns = CGFloat(Self.landscapeNumberFixedKeyColumnCount + (landscapeNumberSymbolPanelRows.first?.count ?? 0))
            let available = keyboardContainerWidth - keyboardHorizontalPadding * 2
                - leftModeSwitchButtonWidth - rowSpacing * keyColumns
            keyWidth = min(keyWidth, floor(available / keyColumns))
        }
        let numberClusterOnLeft = landscapeNumberPaneSide == .left

        return HStack(spacing: 0) {
            landscapeNumberCompactColumns(
                rowHeight: rowHeight,
                rowSpacing: rowSpacing,
                keyWidth: keyWidth,
                numberClusterOnLeft: numberClusterOnLeft
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func landscapeNumberCompactColumns(
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keyWidth: CGFloat,
        numberClusterOnLeft: Bool
    ) -> some View {
        HStack(spacing: rowSpacing) {
            if numberClusterOnLeft {
                landscapeNumberModeSwitchColumn(rowHeight: rowHeight, rowSpacing: rowSpacing)
                landscapeNumberMainKeyCluster(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
                landscapeNumberUtilityColumn(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
                landscapeNumberSymbolPanel(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
            } else {
                landscapeNumberModeSwitchColumn(rowHeight: rowHeight, rowSpacing: rowSpacing)
                landscapeNumberSymbolPanel(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
                landscapeNumberMainKeyCluster(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
                landscapeNumberUtilityColumn(
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keyWidth: keyWidth
                )
            }
        }
    }

    func landscapeNumberModeSwitchColumn(
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(0..<4, id: \.self) { rowIndex in
                threeByThreeLeftColumnButton(rowIndex: rowIndex, rowHeight: rowHeight)
            }
        }
    }

    func landscapeNumberMainKeyCluster(
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keyWidth: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: rowSpacing) {
                    ForEach(row) { kana in
                        threeByThreeMainKey(kana, rowIndex: rowIndex)
                            .frame(width: keyWidth, height: rowHeight)
                    }
                }
                .zIndex(zIndex(for: rowIndex))
            }
        }
    }

    func landscapeNumberUtilityColumn(
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keyWidth: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            deleteActionKey()
                .frame(width: keyWidth, height: rowHeight)

            spaceActionKeyButton(title: "")
                .frame(width: keyWidth, height: rowHeight)

            ZStack(alignment: .top) {
                Color.clear

                returnActionKey()
                    .frame(maxWidth: .infinity)
                    .frame(height: threeByThreeReturnKeyHeight(rowHeight: rowHeight, rowSpacing: rowSpacing))
            }
            .frame(width: keyWidth, height: rowHeight, alignment: .top)
            .zIndex(KeyboardLayerZIndex.rightEdgeUtilityColumn)

            threeByThreeFourthRowUtilitySlot(width: keyWidth, rowHeight: rowHeight)
        }
    }

    func landscapeNumberSymbolPanel(
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keyWidth: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(landscapeNumberSymbolPanelRows.enumerated()), id: \.offset) { _, symbols in
                HStack(spacing: rowSpacing) {
                    ForEach(symbols, id: \.self) { symbol in
                        ActionKeyButton(
                            title: symbol,
                            fontSize: 20,
                            action: { commitText(symbol) }
                        )
                            .frame(width: keyWidth, height: rowHeight)
                    }
                }
            }
        }
    }

    func landscapeCandidateSidebarWidth() -> CGFloat {
        // 広い横画面はキー側と半々(上限 320 は外す。3570)
        if usesWideLandscapeSidebar {
            return WideLandscapeCandidateLayout.sidebarWidth(
                containerWidth: keyboardContainerWidth,
                horizontalPadding: keyboardHorizontalPadding,
                spacing: keyboardRowSpacing
            )
        }
        let screenWidth = keyboardContainerWidth
        let ratio: CGFloat = isKanaFiveByTwoMode ? 0.34 : 0.4
        let desired = screenWidth * ratio
        return min(max(desired, 180), 320)
    }

    // 横画面の状態カプセル(鉛筆=未確定/循環矢印=変換中)は第 1 候補の左に置き、第 2 候補以降は同じ幅だけ左を空けて揃える
    // (3266、ユーザ指定。横画面は横幅に余裕がある)。tokushima は未確定の行にカプセルがあるので出さない(幅だけ揃える)
    static let landscapeStateCapsuleSlotWidth: CGFloat = 34
    static let landscapeStateCapsuleSpacing: CGFloat = 4

    @ViewBuilder func landscapeStateCapsuleSlot(showsCapsule: Bool) -> some View {
        if showsCapsule, internalCompositionPreviewText.isEmpty, !composingText.isEmpty {
            Image(systemName: conversionStateIconName)
                .font(.system(size: candidateStateFontSize, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(conversionStateColor.opacity(0.95))
                )
                .accessibilityLabel(conversionStateLabel)
                .frame(width: Self.landscapeStateCapsuleSlotWidth, alignment: .leading)
                .allowsHitTesting(false)
        } else {
            Color.clear
                .frame(width: Self.landscapeStateCapsuleSlotWidth, height: 1)
        }
    }

    // 横画面の候補列の末尾に置くかなチップ(3266)。縦画面と同じく、変換候補に同じかなが無いときだけ出す。
    // 以前(7 月〜)は候補列の上に状態カプセル(鉛筆)と読みの行を常に出していて、かんじ のように候補にかながあっても
    // 読みの行が重複していた
    // 末尾のかなチップを出すか。広い横画面の 2 列の項目数にも数えるので 1 か所にまとめる(3570)
    var showsLandscapeTrailingKanaChip: Bool {
        let showsWrapperOnly = showsParenthesesWrapper && composingText.isEmpty
        return !showsWrapperOnly && !composingText.isEmpty && canTapComposingTextToCommit
            && !conversionCandidates.contains(composingText)
    }

    @ViewBuilder var landscapeTrailingKanaChip: some View {
        if showsLandscapeTrailingKanaChip {
            let showsKatakanaCommitFeedback = isShowingKatakanaCommitFeedback(for: composingText)

            Button {
                handleComposingTextCommitTap()
            } label: {
                if showsParenthesesWrapper {
                    HStack(spacing: 0) {
                        Text("(")
                            .foregroundStyle(
                                showsKatakanaCommitFeedback
                                    ? Color.white
                                    : accentColor
                            )
                        Text(composingText)
                            .foregroundStyle(
                                showsKatakanaCommitFeedback
                                    ? Color.white
                                    : keyLabelColor.opacity(0.9)
                            )
                        Text(")")
                            .foregroundStyle(
                                showsKatakanaCommitFeedback
                                    ? Color.white
                                    : accentColor
                            )
                    }
                    .font(.system(size: candidateTextFontSize, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                showsKatakanaCommitFeedback
                                    ? accentColor.opacity(0.95)
                                    : KeyboardThemePalette.candidateHeaderChipBackground
                            )
                    )
                } else {
                    Text(composingText)
                        .font(.system(size: candidateTextFontSize, weight: .semibold))
                        .foregroundStyle(
                            showsKatakanaCommitFeedback
                                ? Color.white
                                : keyLabelColor.opacity(0.9)
                        )
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    showsKatakanaCommitFeedback
                                        ? accentColor.opacity(0.95)
                                        : KeyboardThemePalette.candidateHeaderChipBackground
                                )
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("通常タップで変換せずに確定。ロングタップでカタカナ確定")
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        handleComposingTextCommitLongPress()
                    }
            )
        }
    }

    var landscapeKanaCandidateSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            let showsWrapperOnly = showsParenthesesWrapper && composingText.isEmpty

            // tokushima(3211): 候補列の一番上を 1 行使って未確定を下線付きで出す(ScrollView 側が 1 行ぶん縮む)。
            // 状態カプセル(鉛筆/循環矢印)も同じ行の左に置き、消費する行を 1 つで済ませる(3212、ユーザ指定)
            if !internalCompositionPreviewText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: conversionStateIconName)
                        .font(.system(size: candidateStateFontSize, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(conversionStateColor.opacity(0.95))
                        )
                        .accessibilityLabel(conversionStateLabel)
                    Text(internalCompositionPreviewText)
                        .font(.system(size: candidateTextFontSize - 2, weight: .semibold, design: .rounded))
                        .underline()
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(keyLabelColor.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("未確定 \(internalCompositionPreviewText)")
                }
                .padding(.horizontal, 4)
                .frame(height: 24)
                .allowsHitTesting(false)
            }

            if conversionCandidates.isEmpty {
                // 縦画面と同じく、候補が無いときもかなチップを出す(3266)。左の空きは候補の行と揃える
                HStack(spacing: Self.landscapeStateCapsuleSpacing) {
                    landscapeStateCapsuleSlot(showsCapsule: false)
                    landscapeTrailingKanaChip
                }
                if showsFullAccessNotice, composingText.isEmpty, !showsParenthesesWrapper {
                    fullAccessNoticeSidebarView
                } else if !(showsParenthesesWrapper && composingText.isEmpty) {
                    ForEach(0..<landscapeEmptyCandidatePlaceholderCount, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 24)
                    }
                }
            } else if usesWideLandscapeSidebar,
                landscapeKanaSidebarItemCount >= WideLandscapeCandidateLayout.minimumCountForTwoColumns {
                landscapeKanaCandidateTwoColumnList
            } else {
                // 縦画面と同じく、変換キー連打での選択送りに追従させる(2605)。
                ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(conversionCandidates.enumerated()), id: \.offset) { index, candidate in
                            HStack(spacing: Self.landscapeStateCapsuleSpacing) {
                            landscapeStateCapsuleSlot(showsCapsule: index == 0)
                            landscapeKanaCandidateButton(index: index, candidate: candidate)
                            }
                            .id(index)
                        }
                        // かなが候補に無いときだけ、候補の列の末尾にかなチップ(縦画面の末尾チップと同じ。3266)
                        HStack(spacing: Self.landscapeStateCapsuleSpacing) {
                            landscapeStateCapsuleSlot(showsCapsule: false)
                            landscapeTrailingKanaChip
                        }
                    }
                    .padding(.vertical, 0)
                }
                .onChange(of: selectedConversionCandidateIndex) { _, index in
                    guard let index else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
                }
            }
        }
        .modifier(LandscapeSidebarContainer())
    }

    // 横画面の候補 1 つ(1 列・2 列で共用)
    func landscapeKanaCandidateButton(index: Int, candidate: String) -> some View {
        let isSelected = selectedConversionCandidateIndex == index

        return Button {
            onSelectConversionCandidate(index)
        } label: {
            if showsParenthesesWrapper {
                HStack(spacing: 0) {
                    Text("(")
                        .foregroundStyle(isSelected ? Color.white : accentColor)
                    CandidateGlyphText(candidate, fontSize: candidateTextFontSize, color: isSelected ? Color.white : keyLabelColor)
                    Text(")")
                        .foregroundStyle(isSelected ? Color.white : accentColor)
                }
                .font(.system(size: candidateTextFontSize, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isSelected
                                ? accentColor.opacity(0.9)
                                : KeyboardThemePalette.candidateHeaderChipBackground
                        )
                )
            } else {
                CandidateGlyphText(candidate, fontSize: candidateTextFontSize, color: isSelected ? Color.white : keyLabelColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                isSelected
                                    ? accentColor.opacity(0.9)
                                    : KeyboardThemePalette.candidateHeaderChipBackground
                            )
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // 広い横画面の候補欄の項目数(候補+末尾のかなチップ。3570)
    var landscapeKanaSidebarItemCount: Int {
        conversionCandidates.count + (showsLandscapeTrailingKanaChip ? 1 : 0)
    }

    // 広い横画面の候補欄の 2 列(3570)。左列を上から下へ、続きを右列へ。行ごとに 1 つの ScrollView に入れて
    // 2 列まとめて縦にスクロールする。両列とも左に状態カプセルの枠(34+4pt)を空けて列幅をそろえ、
    // カプセル自体は左列の先頭(第 1 候補)だけに出す
    var landscapeKanaCandidateTwoColumnList: some View {
        let itemCount = landscapeKanaSidebarItemCount
        let rows = WideLandscapeCandidateLayout.arrange(count: itemCount)

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: Self.landscapeStateCapsuleSpacing) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, index in
                                HStack(spacing: Self.landscapeStateCapsuleSpacing) {
                                    landscapeStateCapsuleSlot(showsCapsule: index == 0)
                                    if let index, index < conversionCandidates.count {
                                        landscapeKanaCandidateButton(index: index, candidate: conversionCandidates[index])
                                    } else if index != nil {
                                        landscapeTrailingKanaChip
                                    } else {
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .id(rowIndex)
                    }
                }
                .padding(.vertical, 0)
            }
            .onChange(of: selectedConversionCandidateIndex) { _, index in
                guard let index else {
                    return
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(
                        WideLandscapeCandidateLayout.rowIndex(forItemAt: index, count: itemCount),
                        anchor: .center
                    )
                }
            }
        }
    }

    var landscapeLatinSuggestionSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if latinSuggestionQuery.isEmpty {
                ForEach(0..<landscapeEmptyCandidatePlaceholderCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 24)
                }
            } else if latinSuggestions.isEmpty {
                // かな側と同じ空集合アイコン(候補なし)。
                Image(systemName: "circle.slash")
                    .font(.system(size: candidateTextFontSize, weight: .regular))
                    .foregroundStyle(keyLabelColor.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KeyboardThemePalette.candidateHeaderPlaceholderBackground)
                    )
                    .accessibilityLabel("候補なし")
            } else if usesWideLandscapeSidebar,
                latinSuggestions.count >= WideLandscapeCandidateLayout.minimumCountForTwoColumns {
                // 広い横画面は かな と同じく 7 つ以上で 2 列(左列を上から下へ、続きを右列へ。3570)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(WideLandscapeCandidateLayout.arrange(count: latinSuggestions.count).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 4) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, index in
                                    if let index {
                                        landscapeLatinSuggestionButton(index: index, candidate: latinSuggestions[index])
                                    } else {
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 1)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 0)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(latinSuggestions.enumerated()), id: \.offset) { index, candidate in
                            landscapeLatinSuggestionButton(index: index, candidate: candidate)
                        }
                    }
                    .padding(.vertical, 0)
                }
            }
        }
        .modifier(LandscapeSidebarContainer())
    }

    // 横画面の欧文サジェスト 1 つ(1 列・2 列で共用)
    func landscapeLatinSuggestionButton(index: Int, candidate: String) -> some View {
        Button {
            onSelectConversionCandidate(index)
        } label: {
            Text(candidate)
                .font(.system(size: candidateTextFontSize, weight: .semibold))
                .foregroundStyle(keyLabelColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(KeyboardThemePalette.candidateHeaderChipBackground)
                )
        }
        .buttonStyle(.plain)
    }

    var landscapeLatinReferenceClusterHeight: CGFloat {
        // ラテン横画面の主要クラスターは4段固定。
        mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
    }

    @ViewBuilder
    var landscapeLatinSwappableMainCluster: some View {
        if usesLandscapeLatinTypewriterLayout {
            landscapeLatinTypewriterMainCluster
        } else if usesThreeByThreeGridForNumberOrLatin {
            landscapeLatinThreeByThreeMainCluster
        } else {
            keyboardMainContent
        }
    }

    var landscapeLatinThreeByThreeMainCluster: some View {
        let rowHeight = mainFlickKeyHeight
        let rowSpacing: CGFloat = keyboardRowSpacing

        return VStack(spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: rowSpacing) {
                    ForEach(row) { kana in
                        threeByThreeMainKey(kana, rowIndex: rowIndex)
                    }

                    threeByThreeRightColumnButton(
                        rowIndex: rowIndex,
                        rowHeight: rowHeight,
                        rowSpacing: rowSpacing
                    )
                }
                .zIndex(zIndex(for: rowIndex))
            }
        }
    }

    var landscapeKanaFiveByTwoLeftColumn: some View {
        let modeSwitchHeight: CGFloat = mainFlickKeyHeight

        return VStack(spacing: keyboardRowSpacing) {
            compactLeftModeSwitchButton(slot: 0, height: modeSwitchHeight)

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, _ in
                compactLeftModeSwitchButton(slot: rowIndex + 1, height: modeSwitchHeight)
            }

            if rows.count < 3 {
                compactLeftModeSwitchButton(slot: rows.count + 1, height: modeSwitchHeight)
            }
        }
    }

    var landscapeKanaFiveByTwoMainCluster: some View {
        VStack(spacing: keyboardRowSpacing) {
            HStack(spacing: keyboardRowSpacing) {
                ForEach(kanaFiveByTwoTopNumberKeys, id: \.self) { key in
                    ActionKeyButton(
                        title: key,
                        fontSize: 18,
                        action: { commitText(key) }
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: mainFlickKeyHeight)
                }
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: keyboardRowSpacing) {
                    ForEach(row) { kana in
                        if isLatinShiftKey(kana) {
                            LatinShiftKeyButton(
                                isOn: latinShiftState != .off,
                                isLocked: latinShiftState == .locked,
                                onTap: handleLatinShiftTap,
                                onLongPress: handleLatinShiftLongPress
                            )
                                .frame(maxWidth: .infinity)
                                .frame(height: mainFlickKeyHeight)
                        } else {
                            let renderedKana = displayedKana(for: kana)

                            FlickKeyView(
                                kana: renderedKana,
                                onCommit: commitText,
                                showsDirectionalHints: showsFlickGuideCharacters,
                                idleReplacement: rowKeyIdleReplacement(for: renderedKana),
                                longPressCandidates: longPressCandidates(for: kana),
                                longPressCandidatePanelPlacement: longPressCandidatePanelPlacement(forRowIndex: rowIndex),
                                allowsDirectionalFlick: allowsDirectionalFlick(for: kana),
                                downDirectionalHintFontScale: inputMode == .number
                                    ? numberDownDirectionalHintScale
                                    : 1,
                                downDirectionalHintVerticalOffsetAdjustment: inputMode == .number
                                    ? numberDownDirectionalHintVerticalOffsetAdjustment
                                    : 0,
                                onTouchStateChanged: { isTouching in
                                    updateActiveLayer(isTouching, layerIndex: rowIndex)
                                }
                            )
                                .frame(maxWidth: .infinity)
                                .frame(height: mainFlickKeyHeight)
                        }
                    }
                }
                .padding(horizontalInsetsForMainRow(rowIndex))
                .zIndex(zIndex(for: rowIndex))
            }

            HStack(spacing: keyboardRowSpacing) {
                if showsNextKeyboardKey {
                    ActionKeyButton(title: "🌐", fixedWidth: 54, action: onAdvanceKeyboard)
                        .frame(height: mainFlickKeyHeight)
                }

                deleteActionKey(fixedWidth: 64)
                    .frame(height: mainFlickKeyHeight)

                spaceKeyButton(fixedWidth: nil, keyHeight: mainFlickKeyHeight)

                FlickKeyView(
                    kana: modifierSelectorKey,
                    onCommit: selectModifierMode,
                    onCommitWithDirection: selectModifierMode,
                    mainLabelFontSize: modifierMainLabelFontSize,
                    flickGuideDisplayModeOverride: modifierFlickGuideDisplayMode,
                    showsDirectionalHints: showsModifierFlickGuideCharacters,
                    idleReplacement: modifierIdleReplacement,
                    onLongPress: onToggleParenthesesWrapper,
                    directionalFlickThreshold: modifierDirectionalFlickThreshold,
                    directionalCommitThreshold: modifierDirectionalCommitThreshold,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: rows.count)
                    }
                )
                    .frame(width: kanaFiveByTwoTrailingKeyWidth, height: selectorKeySize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isPrefixModifierActive
                                    ? accentColor.opacity(0.95)
                                    : Color.clear,
                                lineWidth: 2
                            )
                    )

                FlickKeyView(
                    kana: punctuationKana,
                    onCommit: commitText,
                    showsDirectionalHints: showsFlickGuideCharacters,
                    idleReplacement: punctuationIdleReplacement,
                    onTouchStateChanged: { isTouching in
                        updateActiveLayer(isTouching, layerIndex: rows.count)
                    }
                )
                    .frame(width: kanaFiveByTwoTrailingKeyWidth, height: selectorKeySize)

                returnActionKey(fixedWidth: 72)
                    .frame(height: mainFlickKeyHeight)
            }
            .zIndex(zIndex(for: rows.count))
        }
    }

    var landscapeLatinModeSwitchColumn: some View {
        VStack(spacing: keyboardRowSpacing) {
            leftModeSwitchNumberButton(height: mainFlickKeyHeight)
            leftModeSwitchLatinButton(height: mainFlickKeyHeight)
            leftModeSwitchKanaButton(
                height: mainFlickKeyHeight,
                fontSize: compactKanaModeSwitchButtonFontSize
            )
            modeSwitcherPaletteKey(height: mainFlickKeyHeight, touchForensicsLabel: "左下キー(横 ラテン文字)")
        }
    }

    func landscapeLatinTypewriterLetterAnchorOffsetFactor(_ rowIndex: Int) -> CGFloat {
        switch rowIndex {
        case 1:
            return landscapeLatinTypewriterMiddleRowOffsetFactor
        case 2:
            return landscapeLatinTypewriterMiddleRowOffsetFactor
                + landscapeLatinTypewriterBottomRowOffsetFromMiddleFactor
        default:
            return 0
        }
    }

    func landscapeLatinTypewriterLeadingControlPitchCount(_ row: [FlickKanaSet]) -> CGFloat {
        CGFloat(row.prefix { isLatinShiftKey($0) }.count)
    }

    func landscapeLatinTypewriterRowInsets(
        leadingOffsetFactor: CGFloat,
        keyPitch: CGFloat
    ) -> EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: leadingOffsetFactor * keyPitch,
            bottom: 0,
            trailing: 0
        )
    }

    func landscapeLatinTypewriterRowInsets(_ rowIndex: Int, keyPitch: CGFloat) -> EdgeInsets {
        landscapeLatinTypewriterRowInsets(
            leadingOffsetFactor: landscapeLatinTypewriterLetterAnchorOffsetFactor(rowIndex),
            keyPitch: keyPitch
        )
    }

    func landscapeLatinTypewriterRowInsets(_ rowIndex: Int) -> EdgeInsets {
        guard usesLandscapeLatinTypewriterLayout else {
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }

        let fallbackKeyPitch = mainFlickKeyHeight + keyboardRowSpacing
        return landscapeLatinTypewriterRowInsets(rowIndex, keyPitch: fallbackKeyPitch)
    }

    @ViewBuilder
    func landscapeLatinTypewriterKey(
        _ kana: FlickKanaSet,
        rowIndex: Int,
        fixedWidth: CGFloat? = nil,
        shiftFixedWidth: CGFloat? = nil
    ) -> some View {
        if isLatinShiftKey(kana) {
            let shiftKey = LatinShiftKeyButton(
                isOn: latinShiftState != .off,
                isLocked: latinShiftState == .locked,
                onTap: handleLatinShiftTap,
                onLongPress: handleLatinShiftLongPress
            )
            let resolvedShiftWidth = shiftFixedWidth ?? fixedWidth

            if let resolvedShiftWidth {
                shiftKey
                    .frame(width: resolvedShiftWidth, height: mainFlickKeyHeight)
            } else {
                shiftKey
                    .frame(maxWidth: .infinity)
                    .frame(height: mainFlickKeyHeight)
            }
        } else {
            let renderedKana = displayedKana(for: kana)
            let letterKey = FlickKeyView(
                kana: renderedKana,
                onCommit: commitText,
                mainLabelFontSize: 25,
                mainLabelFontWeight: rowKeyMainLabelFontWeight,
                showsDirectionalHints: showsFlickGuideCharacters,
                idleReplacement: rowKeyIdleReplacement(for: renderedKana),
                longPressCandidates: longPressCandidates(for: kana),
                longPressCandidatePanelPlacement: longPressCandidatePanelPlacement(forRowIndex: rowIndex),
                allowsDirectionalFlick: allowsDirectionalFlick(for: kana),
                onTouchStateChanged: { isTouching in
                    updateActiveLayer(isTouching, layerIndex: rowIndex)
                }
            )

            if let fixedWidth {
                letterKey
                    .frame(width: fixedWidth, height: mainFlickKeyHeight)
            } else {
                letterKey
                    .frame(maxWidth: .infinity)
                    .frame(height: mainFlickKeyHeight)
            }
        }
    }

    func landscapeLatinInlineDeleteKey(fixedWidth: CGFloat) -> some View {
        deleteActionKey()
            .frame(width: fixedWidth, height: mainFlickKeyHeight)
    }

    func landscapeLatinInlineReturnKey(fixedWidth: CGFloat) -> some View {
        returnActionKey()
            .frame(width: fixedWidth, height: mainFlickKeyHeight)
    }

    // 横向きタイプライター配列(QWERTY)の中段右端のアポストロフィー。縦向きの下段右端(3512)と同じ
    // FlickKanaSet(中心 '、左フリック ’)にして、押しボタンからフリックキーへ(3513)
    func landscapeLatinInlineApostropheKey(fixedWidth: CGFloat) -> some View {
        FlickKeyView(
            kana: Self.latinApostropheKey,
            onCommit: commitText,
            mainLabelFontSize: 25,
            mainLabelFontWeight: rowKeyMainLabelFontWeight,
            showsDirectionalHints: showsFlickGuideCharacters,
            allowsDirectionalFlick: true,
            onTouchStateChanged: { isTouching in
                updateActiveLayer(isTouching, layerIndex: 1)
            }
        )
            .frame(width: fixedWidth, height: mainFlickKeyHeight)
    }

    var landscapeLatinInlineActionTypewriterMainCluster: some View {
        GeometryReader { geometry in
            let topRow = rows.indices.contains(0) ? rows[0] : []
            let middleRow = rows.indices.contains(1) ? rows[1] : []
            let bottomRow = rows.indices.contains(2)
                ? landscapeBottomRowWithInlinePunctuation(rows[2])
                : []
            let inlineReturnRowIndex = landscapeLatinInlineReturnRowIndex

            let topRawLeadingOffsetFactor = landscapeLatinTypewriterLetterAnchorOffsetFactor(0)
                - landscapeLatinTypewriterLeadingControlPitchCount(topRow)
            let middleRawLeadingOffsetFactor = landscapeLatinTypewriterLetterAnchorOffsetFactor(1)
                - landscapeLatinTypewriterLeadingControlPitchCount(middleRow)
            let bottomRawLeadingOffsetFactor = landscapeLatinTypewriterLetterAnchorOffsetFactor(2)
                - landscapeLatinTypewriterLeadingControlPitchCount(bottomRow)

            let minimumRawLeadingOffsetFactor = min(
                topRawLeadingOffsetFactor,
                middleRawLeadingOffsetFactor,
                bottomRawLeadingOffsetFactor
            )

            let topLeadingOffsetFactor = topRawLeadingOffsetFactor - minimumRawLeadingOffsetFactor
            let middleLeadingOffsetFactor = middleRawLeadingOffsetFactor - minimumRawLeadingOffsetFactor
            let bottomLeadingOffsetFactor = bottomRawLeadingOffsetFactor - minimumRawLeadingOffsetFactor

            let rowSpecs: [(keyPitchCount: CGFloat, offsetFactor: CGFloat)] = [
                (CGFloat(topRow.count + 1), topLeadingOffsetFactor),
                (
                    CGFloat(
                        middleRow.count
                            + (inlineReturnRowIndex == 1 ? 1 : 0)
                            + (needsQwertyMiddleRowApostrophe ? 1 : 0)
                    ),
                    middleLeadingOffsetFactor
                ),
                (
                    CGFloat(bottomRow.count + (inlineReturnRowIndex == 2 ? 1 : 0)) + 1,
                    bottomLeadingOffsetFactor
                )
            ].filter { $0.keyPitchCount > 0 }

            let resolvedKeyWidth = max(
                1,
                rowSpecs
                    .map { spec in
                        let denominator = spec.keyPitchCount + spec.offsetFactor

                        guard denominator > 0 else {
                            return 1
                        }

                        let numerator = geometry.size.width
                            - keyboardRowSpacing
                            * (max(spec.keyPitchCount - 1, 0) + spec.offsetFactor)

                        return numerator / denominator
                    }
                    .min() ?? 1
            )
            let keyPitch = resolvedKeyWidth + keyboardRowSpacing
            let topInsets = landscapeLatinTypewriterRowInsets(
                leadingOffsetFactor: topLeadingOffsetFactor,
                keyPitch: keyPitch
            )
            let middleInsets = landscapeLatinTypewriterRowInsets(
                leadingOffsetFactor: middleLeadingOffsetFactor,
                keyPitch: keyPitch
            )
            let bottomInsets = landscapeLatinTypewriterRowInsets(
                leadingOffsetFactor: bottomLeadingOffsetFactor,
                keyPitch: keyPitch
            )
            let shiftKeyExtraWidth = max(0, (resolvedKeyWidth + keyboardRowSpacing) / 2)
            let widenedShiftKeyWidth = resolvedKeyWidth + shiftKeyExtraWidth
            let rightShiftIndexInBottomRow = bottomRow.firstIndex(where: isLandscapeLatinRightShiftKey)
                ?? max(bottomRow.count - 1, 0)
            let referenceRightEdgeX = bottomInsets.leading
                + CGFloat(rightShiftIndexInBottomRow + 1) * resolvedKeyWidth
                + CGFloat(rightShiftIndexInBottomRow) * keyboardRowSpacing
                + shiftKeyExtraWidth * 2
            let topRowLeadingKeyCount = topRow.count
            let topDeleteKeyWidth = max(
                resolvedKeyWidth,
                referenceRightEdgeX
                    - topInsets.leading
                    - CGFloat(topRowLeadingKeyCount) * resolvedKeyWidth
                    - CGFloat(topRowLeadingKeyCount) * keyboardRowSpacing
            )
            let middleRowLeadingKeyCount = middleRow.count
                + (needsQwertyMiddleRowApostrophe ? 1 : 0)
            let middleReturnKeyWidth = max(
                resolvedKeyWidth,
                referenceRightEdgeX
                    - middleInsets.leading
                    - CGFloat(middleRowLeadingKeyCount) * resolvedKeyWidth
                    - CGFloat(middleRowLeadingKeyCount) * keyboardRowSpacing
            )
            VStack(alignment: .leading, spacing: keyboardRowSpacing) {
                HStack(spacing: keyboardRowSpacing) {
                    ForEach(Array(topRow.enumerated()), id: \.offset) { _, kana in
                        landscapeLatinTypewriterKey(kana, rowIndex: 0, fixedWidth: resolvedKeyWidth)
                    }

                    landscapeLatinInlineDeleteKey(fixedWidth: topDeleteKeyWidth)
                }
                .padding(topInsets)
                .zIndex(zIndex(for: 0))

                HStack(spacing: keyboardRowSpacing) {
                    ForEach(Array(middleRow.enumerated()), id: \.offset) { _, kana in
                        landscapeLatinTypewriterKey(kana, rowIndex: 1, fixedWidth: resolvedKeyWidth)
                    }

                    if needsQwertyMiddleRowApostrophe {
                        landscapeLatinInlineApostropheKey(fixedWidth: resolvedKeyWidth)
                    }

                    if inlineReturnRowIndex == 1 {
                        landscapeLatinInlineReturnKey(fixedWidth: middleReturnKeyWidth)
                    }
                }
                .padding(middleInsets)
                .zIndex(zIndex(for: 1))

                HStack(spacing: keyboardRowSpacing) {
                    ForEach(Array(bottomRow.enumerated()), id: \.offset) { _, kana in
                        landscapeLatinTypewriterKey(
                            kana,
                            rowIndex: 2,
                            fixedWidth: resolvedKeyWidth,
                            shiftFixedWidth: widenedShiftKeyWidth
                        )
                    }

                    if inlineReturnRowIndex == 2 {
                        landscapeLatinInlineReturnKey(fixedWidth: resolvedKeyWidth)
                    }
                }
                .padding(bottomInsets)
                .zIndex(zIndex(for: 2))

                HStack(spacing: keyboardRowSpacing) {
                    if showsNextKeyboardKey {
                        ActionKeyButton(title: "🌐", fixedWidth: 54, action: onAdvanceKeyboard)
                            .frame(height: mainFlickKeyHeight)
                    }

                    latinSpaceLeftActionButtons(fixedWidth: 44, keyHeight: mainFlickKeyHeight)

                    spaceKeyButton(fixedWidth: nil, keyHeight: mainFlickKeyHeight)

                    latinSpaceRightActionButtons(fixedWidth: 44, keyHeight: mainFlickKeyHeight)
                }
                .zIndex(zIndex(for: rows.count))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var landscapeLatinTypewriterMainCluster: some View {
        Group {
            if usesLandscapeLatinTypewriterLayout {
                landscapeLatinInlineActionTypewriterMainCluster
            } else {
                VStack(spacing: keyboardRowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: keyboardRowSpacing) {
                            ForEach(row) { kana in
                                landscapeLatinTypewriterKey(kana, rowIndex: rowIndex)
                            }
                        }
                        .padding(landscapeLatinTypewriterRowInsets(rowIndex))
                        .zIndex(zIndex(for: rowIndex))
                    }

                    HStack(spacing: keyboardRowSpacing) {
                        if showsNextKeyboardKey {
                            ActionKeyButton(title: "🌐", fixedWidth: 54, action: onAdvanceKeyboard)
                                .frame(height: compactActionKeyHeight)
                        }

                        deleteActionKey()
                            .frame(maxWidth: .infinity)
                            .frame(height: compactActionKeyHeight)

                        spaceKeyButton(fixedWidth: nil)

                        returnActionKey()
                            .frame(maxWidth: .infinity)
                            .frame(height: compactActionKeyHeight)
                    }
                    .padding(.top, actionRowTopSpacing)
                    .zIndex(zIndex(for: rows.count))
                }
            }
        }
    }

    @ViewBuilder
    var landscapeKanaFixedModeSwitchColumn: some View {
        if isKanaThreeByThreeMode {
            threeByThreeKanaLeftColumn
        } else if isKanaFiveByTwoMode {
            landscapeKanaFiveByTwoLeftColumn
        } else {
            Color.clear
                .allowsHitTesting(false)
                .frame(width: leftModeSwitchButtonWidth)
        }
    }

    @ViewBuilder
    var landscapeKanaSwappableMainCluster: some View {
        if isKanaThreeByThreeMode {
            threeByThreeKanaMainCluster(
                kanaRows: threeByThreeKanaRows,
                rowHeight: mainFlickKeyHeight,
                rowSpacing: keyboardRowSpacing
            )
        } else if isKanaFiveByTwoMode {
            landscapeKanaFiveByTwoMainCluster
        } else {
            keyboardMainContent
        }
    }

    var landscapeKanaReferenceClusterHeight: CGFloat {
        if isKanaThreeByThreeMode {
            // 3x3+わのかな塊は4段固定。
            return mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
        }

        if isKanaFiveByTwoMode {
            // 5x2は上段数字 + かな段 + 下段アクションを含める。
            let topAndKanaRowCount = CGFloat(rows.count + 1)
            let verticalGapCount = CGFloat(rows.count + 1)
            return topAndKanaRowCount * mainFlickKeyHeight
                + mainFlickKeyHeight
                + verticalGapCount * keyboardRowSpacing
        }

        return 0
    }
}

// 横向きのサイドバー(かな候補/欧文サジェスト)の外枠。2 か所で同じ装飾チェーンを書いていたのを集約(2805)
private struct LandscapeSidebarContainer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KeyboardThemePalette.candidateHeaderSubtleBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(KeyboardThemePalette.candidateHeaderBorder, lineWidth: 1)
            )
    }
}
