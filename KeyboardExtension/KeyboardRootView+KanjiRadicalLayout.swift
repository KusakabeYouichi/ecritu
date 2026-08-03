import SwiftUI

// 漢字1文字ピッカー: 8カテゴリー(偏/旁/冠/脚/垂/繞/構/独立)→ 部首一覧 → 字グリッド。
// 絵文字・記号モードと同じ「上=内容スクロール / 下=カテゴリーバー」の骨格に合わせる(2444)。
extension KeyboardRootView {
    var kanjiRadicalKeyboardView: some View {
        KeyboardRootKanjiRadicalSectionView(
            selectedCategory: $selectedRadicalCategory,
            selectedForm: $selectedRadicalForm,
            keyboardRowSpacing: keyboardRowSpacing,
            emojiGridSpacing: emojiGridSpacing,
            compactEmojiKeyHeight: compactEmojiKeyHeight,
            mainFlickKeyHeight: mainFlickKeyHeight,
            fourRowAlignedTopContentHeight: fourRowAlignedTopContentHeight,
            fourRowAlignedClusterHeight: fourRowAlignedClusterHeight,
            keyRepeatInitialDelay: keyRepeatInitialDelay,
            keyRepeatInterval: keyRepeatInterval,
            onLookupEntries: onLookupRadicalEntries,
            onCommitCharacter: { character in
                // タップ=確定してかなモードへ戻る
                onTextInput(character)
                switchInputMode(.kana)
            },
            onSwitchToKana: { switchInputMode(.kana) },
            onDeleteBackward: onDeleteBackward
        )
    }
}

// 字キー。ヒラギノ明朝にグリフが無い字(実機では PingFang 等で描かれる)は色を変えて
// 区別する。判定は表示中のセルぶんだけ実行するのでデータに印は持たせない(2445)。
struct KanjiCharacterKeyButton: View {
    let entry: KanjiRadicalFileIndex.Entry
    let height: CGFloat
    let onCommit: (String) -> Void

    private var hasMincho: Bool {
        KanaKanjiStore.hasMinchoGlyph(for: entry.character)
    }

    var body: some View {
        Button {
            onCommit(entry.character)
        } label: {
            Text(entry.character)
                .font(.custom("HiraMinProN-W3", size: 22))
                .foregroundStyle(hasMincho ? Color(.label) : Color(.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.character) \(entry.readings)")
    }
}

// カテゴリータブ。塗りの位置で「漢字の枠のどこを占める部首か」を示す。
struct RadicalCategoryKeyButton: View {
    let category: RadicalPositionCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(.systemBackground) : Color.clear)
                RadicalPositionIcon(category: category)
                    .fill(isSelected ? Color.accentColor : Color(.label))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color(.tertiaryLabel), lineWidth: 1)
                            .padding(3)
                    )
                    .frame(width: 24, height: 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.accessibilityLabel)
    }
}

// 部首キー。字形と読み(さんずい 等)を並べる。
struct RadicalFormKeyButton: View {
    let form: RadicalForm
    let isSelected: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(form.form)
                    .font(.custom("HiraMinProN-W3", size: 22))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(form.name)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.systemBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(form.form) \(form.name)")
    }
}

struct KeyboardRootKanjiRadicalSectionView: View {
    @Binding var selectedCategory: RadicalPositionCategory
    @Binding var selectedForm: RadicalForm?
    let keyboardRowSpacing: CGFloat
    let emojiGridSpacing: CGFloat
    let compactEmojiKeyHeight: CGFloat
    let mainFlickKeyHeight: CGFloat
    let fourRowAlignedTopContentHeight: CGFloat
    let fourRowAlignedClusterHeight: CGFloat
    let keyRepeatInitialDelay: TimeInterval
    let keyRepeatInterval: TimeInterval
    let onLookupEntries: (Int) -> [KanjiRadicalFileIndex.Entry]
    let onCommitCharacter: (String) -> Void
    let onSwitchToKana: () -> Void
    let onDeleteBackward: () -> Void

    private var forms: [RadicalForm] {
        KanjiRadicalCatalog.forms(in: selectedCategory)
    }

    private var radicalColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 7)
    }

    private var characterColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 9)
    }

    private var backRowHeight: CGFloat { 20 }

    var body: some View {
        VStack(spacing: keyboardRowSpacing) {
            if let form = selectedForm {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Button {
                            selectedForm = nil
                        } label: {
                            Text("◀ 部首")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        Text("\(form.form) \(form.name)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .frame(height: backRowHeight)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: characterColumns, spacing: emojiGridSpacing) {
                            ForEach(onLookupEntries(form.radical), id: \.character) { entry in
                                KanjiCharacterKeyButton(
                                    entry: entry,
                                    height: compactEmojiKeyHeight,
                                    onCommit: onCommitCharacter
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(height: fourRowAlignedTopContentHeight)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: radicalColumns, spacing: emojiGridSpacing) {
                        ForEach(forms) { form in
                            RadicalFormKeyButton(
                                form: form,
                                isSelected: false,
                                height: compactEmojiKeyHeight
                            ) {
                                selectedForm = form
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: fourRowAlignedTopContentHeight)
            }

            HStack(spacing: keyboardRowSpacing) {
                ActionKeyButton(
                    title: "あい",
                    fixedWidth: 56,
                    action: onSwitchToKana
                )
                .frame(height: mainFlickKeyHeight)

                ForEach(RadicalPositionCategory.allCases) { category in
                    RadicalCategoryKeyButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                        selectedForm = nil
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: mainFlickKeyHeight)
                }

                ActionKeyButton(
                    title: "⌫",
                    fixedWidth: 56,
                    repeatInitialDelay: keyRepeatInitialDelay,
                    repeatInterval: keyRepeatInterval,
                    action: onDeleteBackward
                )
                .frame(height: mainFlickKeyHeight)
            }
        }
        .frame(height: fourRowAlignedClusterHeight, alignment: .top)
    }
}
