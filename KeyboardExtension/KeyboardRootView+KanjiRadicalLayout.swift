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

    // ロングタップ中だけ字典風のポップアップを出す。押し込みで確定してしまわないよう、
    // シフトキーと同じ didTriggerLongPress ガードでタップ動作を抑止する(モードも維持)。
    @State private var didTriggerLongPress = false
    @State private var isShowingInfo = false

    private var hasMincho: Bool {
        KanaKanjiStore.hasMinchoGlyph(for: entry.character)
    }

    var body: some View {
        Button {
            if didTriggerLongPress {
                didTriggerLongPress = false
                return
            }
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    didTriggerLongPress = true
                    isShowingInfo = true
                }
        )
        // 指を離した(またはキー外へ動かした)時点でポップアップを消す
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    isShowingInfo = false
                }
        )
        .overlay {
            if isShowingInfo {
                KanjiInspectBubble(entry: entry)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .zIndex(isShowingInfo ? 1 : 0)
        .animation(.easeOut(duration: 0.08), value: isShowingInfo)
        .accessibilityLabel("\(entry.character) \(entry.readings)")
    }
}

// 字のロングタップで出す字典風ポップアップ(読み / U+XXXX / JIS X 0208区点)。
// 記号モードの長押し吹き出しと同じ見え方に揃え、画面端では内側へずらす。
struct KanjiInspectBubble: View {
    let entry: KanjiRadicalFileIndex.Entry

    private let bubbleWidth: CGFloat = 176
    private let screenMargin: CGFloat = 6
    private let verticalOffset: CGFloat = -46

    private var codePointText: String {
        guard let scalar = entry.character.unicodeScalars.first else {
            return "—"
        }
        return String(format: "U+%04X", scalar.value)
    }

    var body: some View {
        GeometryReader { proxy in
            let keyFrame = proxy.frame(in: .global)
            let screenWidth = UIScreen.main.bounds.width
            let half = bubbleWidth / 2
            let clampedCenterX = min(
                max(keyFrame.midX, screenMargin + half),
                max(screenMargin + half, screenWidth - screenMargin - half)
            )
            let dx = clampedCenterX - keyFrame.midX

            VStack(spacing: 2) {
                Text(entry.readings)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("\(codePointText)  区点 \(entry.kuten)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: bubbleWidth)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.86))
            )
            .frame(width: proxy.size.width, alignment: .center)
            .offset(x: dx, y: verticalOffset)
        }
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

// 画数の区切り(タップできない)。「3画」のように示す。
struct RadicalStrokeMarkerCell: View {
    let strokes: Int
    let height: CGFloat

    var body: some View {
        Text("\(strokes)画")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(.secondaryLabel))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
            .accessibilityLabel("\(strokes)画の部首")
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

    // 部首一覧に画数の区切り(タップ不可)を挟む。部首を探す手掛かりは画数のため(2447)
    enum RadicalListItem {
        case strokeMarker(Int)
        case form(RadicalForm)
    }

    private var radicalListItems: [(id: String, kind: RadicalListItem)] {
        var items: [(id: String, kind: RadicalListItem)] = []
        var lastStrokes = -1
        for form in forms {
            if form.strokes != lastStrokes {
                items.append((id: "marker-\(form.strokes)", kind: .strokeMarker(form.strokes)))
                lastStrokes = form.strokes
            }
            items.append((id: form.id, kind: .form(form)))
        }
        return items
    }

    var body: some View {
        VStack(spacing: keyboardRowSpacing) {
            if let form = selectedForm {
                // 戻るはヘッダー(◀ 偏 › 氵(さんずい))が担う。行内にパンくずは置かない
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
                .frame(height: fourRowAlignedTopContentHeight)
                // ロングタップの吹き出しが最上段で見切れないようクリップを解除(iOS17+)
                .modifier(KanjiRadicalScrollClipDisabledModifier())
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: radicalColumns, spacing: emojiGridSpacing) {
                        ForEach(radicalListItems, id: \.id) { item in
                            switch item.kind {
                            case .strokeMarker(let strokes):
                                RadicalStrokeMarkerCell(
                                    strokes: strokes,
                                    height: compactEmojiKeyHeight
                                )
                            case .form(let form):
                                RadicalFormKeyButton(
                                    form: form,
                                    isSelected: false,
                                    height: compactEmojiKeyHeight
                                ) {
                                    selectedForm = form
                                }
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

struct KanjiRadicalScrollClipDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}
