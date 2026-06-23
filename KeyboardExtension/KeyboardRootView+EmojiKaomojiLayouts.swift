import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension KeyboardRootView {
    var emojiGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 9)
    }

    var symbolGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 8)
    }

    var kaomojiSearchReadingColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: keyboardRowSpacing), count: 3)
    }

    var kaomojiCategories: [KaomojiCategory] {
        let preferredImportedCategoryOrder: [String] = [
            "笑",
            "かわいい",
            "照れ",
            "焦り",
            "しょぼん",
            "悲",
            "怒",
            "驚き",
            "くそねみ",
            "挨拶",
            "ラブ",
            "激しい",
            "うごき",
            "キモい",
            "キャラ",
            "特殊",
            "ライン"
        ]

        let importedCategorySet = Set(KaomojiCatalog.importedCategoryOrder)
        let orderedImportedCategories = preferredImportedCategoryOrder
            .filter { importedCategorySet.contains($0) }
        let remainingImportedCategories = KaomojiCatalog.importedCategoryOrder
            .filter { !orderedImportedCategories.contains($0) }

        var categories: [KaomojiCategory] = [
            KaomojiCategory(kind: .shortcut),
            KaomojiCategory(kind: .existing),
            KaomojiCategory(kind: .search)
        ]

        categories.append(contentsOf: orderedImportedCategories.map { name in
            KaomojiCategory(kind: .imported(name))
        })
        categories.append(contentsOf: remainingImportedCategories.map { name in
            KaomojiCategory(kind: .imported(name))
        })
        return categories
    }

    var selectedKaomojiCategory: KaomojiCategory {
        kaomojiCategories.first(where: { $0.id == selectedKaomojiCategoryID })
            ?? KaomojiCategory(kind: .existing)
    }

    var isKaomojiSearchCategorySelected: Bool {
        if case .search = selectedKaomojiCategory.kind {
            return true
        }

        return false
    }

    var selectedKaomojiCategoryEntries: [String] {
        switch selectedKaomojiCategory.kind {
        case .shortcut:
            return shortcutVocabularyEntries
        case .existing:
            return KaomojiCatalog.existingEntries
        case .imported(let name):
            return KaomojiCatalog.entries(forImportedCategory: name)
        case .search:
            return []
        }
    }

    var kaomojiSearchReadings: [String] {
        return Array(
            KaomojiCatalog.readings(prefix: selectedKaomojiReadingPrefix)
                .prefix(kaomojiSearchReadingDisplayLimit)
        )
    }

    var selectedKaomojiSearchResults: [String] {
        guard let selectedKaomojiReading,
            !selectedKaomojiReading.isEmpty else {
            return []
        }

        return KaomojiCatalog.entries(forReading: selectedKaomojiReading)
    }

    func selectKaomojiCategory(_ category: KaomojiCategory) {
        selectedKaomojiCategoryID = category.id

        if case .search = category.kind {
            return
        }

        selectedKaomojiReadingPrefix = nil
        selectedKaomojiReading = nil
    }

    func selectKaomojiReadingPrefix(_ prefix: String?) {
        selectedKaomojiReadingPrefix = prefix
        selectedKaomojiReading = nil
    }

    func measuredKaomojiWidth(_ kaomoji: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: kaomojiFontSize, weight: .semibold)
        ]
        let textWidth = ceil((kaomoji as NSString).size(withAttributes: attributes).width)
        return max(kaomojiMinKeyWidth, textWidth + kaomojiHorizontalPadding * 2)
    }

    func kaomojiRows(
        for availableWidth: CGFloat,
        entries: [String]
    ) -> [KaomojiRowLayout] {
        let minSpacing = keyboardRowSpacing * kaomojiMinInterItemSpacingMultiplier

        guard !entries.isEmpty else {
            return []
        }

        guard availableWidth > 0 else {
            return [KaomojiRowLayout(items: entries, spacing: minSpacing)]
        }

        var rows: [KaomojiRowLayout] = []
        var currentRow: [String] = []
        var currentRowItemsWidth: CGFloat = 0

        func appendCurrentRow() {
            guard !currentRow.isEmpty else {
                return
            }

            let resolvedSpacing: CGFloat
            if currentRow.count > 1 {
                let distributed = (availableWidth - currentRowItemsWidth)
                    / CGFloat(currentRow.count - 1)
                resolvedSpacing = max(minSpacing, distributed)
            } else {
                resolvedSpacing = minSpacing
            }

            rows.append(KaomojiRowLayout(items: currentRow, spacing: resolvedSpacing))
            currentRow.removeAll(keepingCapacity: true)
            currentRowItemsWidth = 0
        }

        for kaomoji in entries {
            let keyWidth = min(measuredKaomojiWidth(kaomoji), availableWidth)

            if currentRow.isEmpty {
                currentRow = [kaomoji]
                currentRowItemsWidth = keyWidth
                continue
            }

            let nextItemCount = currentRow.count + 1
            let nextItemsWidth = currentRowItemsWidth + keyWidth
            let nextRequiredWidth = nextItemsWidth + minSpacing * CGFloat(nextItemCount - 1)
            let canAppendByWidth = nextRequiredWidth <= availableWidth
            let canAppendByCount = nextItemCount <= kaomojiMaxColumns

            if canAppendByWidth && canAppendByCount {
                currentRow.append(kaomoji)
                currentRowItemsWidth = nextItemsWidth
            } else {
                appendCurrentRow()
                currentRow = [kaomoji]
                currentRowItemsWidth = keyWidth
            }
        }

        appendCurrentRow()

        return rows
    }

    @ViewBuilder
    func kaomojiRowLayoutsView(
        _ rows: [KaomojiRowLayout],
        availableWidth: CGFloat,
        sectionID: String
    ) -> some View {
        let indexedRows = Array(rows.enumerated()).map { index, row in
            (id: "\(sectionID)-row-\(index)", row: row)
        }

        ForEach(indexedRows, id: \.id) { rowEntry in
            let row = rowEntry.row
            HStack(spacing: row.spacing) {
                ForEach(Array(row.items.enumerated()), id: \.offset) { _, kaomoji in
                    KaomojiKeyButton(kaomoji: kaomoji) {
                        commitEmojiKaomojiSymbolText(kaomoji)
                    }
                    .frame(
                        width: min(measuredKaomojiWidth(kaomoji), availableWidth),
                        height: compactKaomojiKeyHeight
                    )
                }

                if row.items.count == 1 {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var emojiKeyboardView: some View {
        KeyboardRootEmojiKeyboardSectionView(
            selectedEmojiCategory: $selectedEmojiCategory,
            keyboardRowSpacing: keyboardRowSpacing,
            emojiGridColumns: emojiGridColumns,
            emojiGridSpacing: emojiGridSpacing,
            compactEmojiKeyHeight: compactEmojiKeyHeight,
            mainFlickKeyHeight: mainFlickKeyHeight,
            fourRowAlignedTopContentHeight: fourRowAlignedTopContentHeight,
            fourRowAlignedClusterHeight: fourRowAlignedClusterHeight,
            keyRepeatInitialDelay: keyRepeatInitialDelay,
            keyRepeatInterval: keyRepeatInterval,
            onTextInput: commitEmojiKaomojiSymbolText,
            onSwitchToKana: { switchInputMode(.kana) },
            onDeleteBackward: onDeleteBackward
        )
    }

    var symbolKeyboardView: some View {
        KeyboardRootSymbolKeyboardSectionView(
            selectedSymbolCategory: $selectedSymbolCategory,
            basicSymbolOrder: basicSymbolOrder,
            temperatureUnit: temperatureUnit,
            keyboardRowSpacing: keyboardRowSpacing,
            symbolGridColumns: symbolGridColumns,
            emojiGridSpacing: emojiGridSpacing,
            compactEmojiKeyHeight: compactEmojiKeyHeight,
            mainFlickKeyHeight: mainFlickKeyHeight,
            fourRowAlignedTopContentHeight: fourRowAlignedTopContentHeight,
            fourRowAlignedClusterHeight: fourRowAlignedClusterHeight,
            keyRepeatInitialDelay: keyRepeatInitialDelay,
            keyRepeatInterval: keyRepeatInterval,
            onTextInput: commitEmojiKaomojiSymbolText,
            onSwitchToKana: { switchInputMode(.kana) },
            onDeleteBackward: onDeleteBackward
        )
    }

    func kaomojiSearchPrefixButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(
                    isSelected
                        ? KeyboardThemePalette.keyLabel
                        : KeyboardThemePalette.keyLabelSecondary
                )
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? KeyboardThemePalette.categoryButtonBackgroundSelected
                                : KeyboardThemePalette.categoryButtonBackground
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected
                                ? KeyboardThemePalette.keyBorderEmphasis
                                : KeyboardThemePalette.keyBorder,
                            lineWidth: isSelected ? 1.2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    func kaomojiSearchReadingButton(
        reading: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(reading)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(
                    isSelected
                        ? KeyboardThemePalette.keyLabel
                        : KeyboardThemePalette.keyLabelSecondary
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isSelected
                                ? KeyboardThemePalette.categoryButtonBackgroundSelected
                                : KeyboardThemePalette.categoryButtonBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected
                                ? KeyboardThemePalette.keyBorderEmphasis
                                : KeyboardThemePalette.keyBorder,
                            lineWidth: isSelected ? 1.2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    var kaomojiKeyboardView: some View {
        GeometryReader { geometry in
            let categoryRows = kaomojiRows(
                for: geometry.size.width,
                entries: selectedKaomojiCategoryEntries
            )
            let searchResultRows = kaomojiRows(
                for: geometry.size.width,
                entries: selectedKaomojiSearchResults
            )

            VStack(spacing: keyboardRowSpacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    if isKaomojiSearchCategorySelected {
                        VStack(alignment: .leading, spacing: keyboardRowSpacing) {
                            Text("1) 上の文字を選ぶ  2) 読みを選ぶ  3) 下の顔文字をタップ")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    kaomojiSearchPrefixButton(
                                        title: "全",
                                        isSelected: selectedKaomojiReadingPrefix == nil,
                                        action: { selectKaomojiReadingPrefix(nil) }
                                    )

                                    ForEach(KaomojiCatalog.readingIndexHeadings, id: \.self) { heading in
                                        kaomojiSearchPrefixButton(
                                            title: heading,
                                            isSelected: selectedKaomojiReadingPrefix == heading,
                                            action: { selectKaomojiReadingPrefix(heading) }
                                        )
                                    }
                                }
                            }

                            if let selectedKaomojiReading,
                                !selectedKaomojiReading.isEmpty {
                                HStack(spacing: 8) {
                                    Text("よみ: \(selectedKaomojiReading)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)

                                    Spacer(minLength: 0)

                                    Button(action: { self.selectedKaomojiReading = nil }) {
                                        Text("読みを選び直す")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(KeyboardThemePalette.categoryButtonBackground)
                                            )
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }

                                Rectangle()
                                    .fill(KeyboardThemePalette.thinDivider)
                                    .frame(height: 1)
                                    .padding(.vertical, 4)

                                if searchResultRows.isEmpty {
                                    Text("該当する顔文字がありません")
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)
                                } else {
                                    Text("候補をタップして入力")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)

                                    kaomojiRowLayoutsView(
                                        searchResultRows,
                                        availableWidth: geometry.size.width,
                                        sectionID: "kaomoji-search-results"
                                    )
                                }
                            } else {
                                LazyVGrid(columns: kaomojiSearchReadingColumns, spacing: keyboardRowSpacing) {
                                    ForEach(kaomojiSearchReadings, id: \.self) { reading in
                                        kaomojiSearchReadingButton(
                                            reading: reading,
                                            isSelected: selectedKaomojiReading == reading,
                                            action: { selectedKaomojiReading = reading }
                                        )
                                    }
                                }

                                if kaomojiSearchReadings.isEmpty {
                                    Text("該当する読みがありません")
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(KeyboardThemePalette.keyLabelSecondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    } else {
                        LazyVStack(alignment: .leading, spacing: keyboardRowSpacing) {
                            kaomojiRowLayoutsView(
                                categoryRows,
                                availableWidth: geometry.size.width,
                                sectionID: "kaomoji-category-\(selectedKaomojiCategoryID)"
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
                .frame(height: fourRowAlignedTopContentHeight)

                HStack(spacing: keyboardRowSpacing) {
                    ActionKeyButton(
                        title: "あい",
                        fixedWidth: 56,
                        action: { switchInputMode(.kana) }
                    )
                        .frame(height: mainFlickKeyHeight)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: keyboardRowSpacing) {
                            ForEach(kaomojiCategories) { category in
                                KaomojiCategoryKeyButton(
                                    icon: category.icon,
                                    accessibilityLabel: category.title,
                                    isSelected: selectedKaomojiCategoryID == category.id,
                                    action: { selectKaomojiCategory(category) }
                                )
                                .frame(width: kaomojiCategoryButtonWidth)
                                .frame(height: mainFlickKeyHeight)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    ActionKeyButton(
                        title: "⌫",
                        accessibilityLabel: "削除",
                        fontSize: 26,
                        fixedWidth: 56,
                        repeatsWhileHolding: true,
                        repeatInitialDelay: keyRepeatInitialDelay,
                        repeatInterval: keyRepeatInterval,
                        action: onDeleteBackward
                    )
                        .frame(height: mainFlickKeyHeight)
                }
                .frame(height: mainFlickKeyHeight)
            }
            .frame(height: fourRowAlignedClusterHeight, alignment: .top)
        }
        .frame(height: fourRowAlignedClusterHeight, alignment: .top)
    }

    var emojiHeaderTitle: String {
        switch emojiInputSubmode {
        case .emoji:
            return selectedEmojiCategory.frenchName
        case .kaomoji:
            return selectedKaomojiCategory.title
        case .symbols:
            return selectedSymbolCategory.frenchName
        }
    }
}
