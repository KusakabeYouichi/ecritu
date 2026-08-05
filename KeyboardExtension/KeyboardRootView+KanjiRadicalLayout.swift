import SwiftUI
import UIKit

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
            strokeCountStyle: radicalStrokeCountStyle,
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
    // 別フォントで描かれる字の色。薄いブルー系。ライト/ダークで明度を入れ替えて、
    // どちらの背景でも読める濃さにする(2485)
    static let fallbackGlyphColor = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.58, green: 0.76, blue: 1.0, alpha: 1.0)
                : UIColor(red: 0.32, green: 0.52, blue: 0.88, alpha: 1.0)
        }
    )

    let entry: KanjiRadicalFileIndex.Entry
    let height: CGFloat
    let onCommit: (String) -> Void
    // ロングタップの吹き出しはセクション側のオーバーレイが描く(キー内に描くと隣のキーが
    // 上に載って潜り、スクロール領域の端で見切れる。2481)。キーの矩形を渡して位置を決める。
    let onInspect: (KanjiRadicalFileIndex.Entry?, CGRect) -> Void

    // ロングタップ中だけ字典風のポップアップを出す。押し込みで確定してしまわないよう、
    // シフトキーと同じ didTriggerLongPress ガードでタップ動作を抑止する(モードも維持)。
    @State private var didTriggerLongPress = false
    @State private var isInspecting = false

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
                .foregroundStyle(hasMincho ? Color(.label) : Self.fallbackGlyphColor)
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
        // キーの矩形は長押しが成立した瞬間にだけ読む。DragGesture の onChanged で接触点を
        // 追跡すると ScrollView のスクロールを奪ってしまう(2490の退行)。
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: isInspecting) { inspecting in
                        onInspect(
                            inspecting ? entry : nil,
                            inspecting
                                ? proxy.frame(in: .named(KanjiInspectBubble.coordinateSpaceName))
                                : .zero
                        )
                    }
            }
        )
        // 指を離した(またはキー外へ動かした)時点でポップアップを消す。onEnded だけなので
        // スクロールは妨げない
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    isInspecting = false
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    didTriggerLongPress = true
                    isInspecting = true
                }
        )
        .accessibilityLabel("\(entry.character) \(entry.readings)")
    }
}

// 字のロングタップで出す字典風ポップアップ(読み / U+XXXX / JIS X 0208区点)。
// セクション側のオーバーレイが描く(キー内に描くと隣のキーの下に潜る)。位置はキーの矩形から
// 決め、上に出す余地が無い最上段では指に隠れないよう横へ逃がす。左右上下ともスクロール領域内に
// クランプするので見切れない(2481、2490でキー矩形基準に変更)。
struct KanjiInspectBubble: View {
    static let coordinateSpaceName = "kanjiCharacterGrid"

    static let bubbleWidth: CGFloat = 176
    // 2行(読み+コード)+上下パディングの見込み。配置計算にだけ使う
    static let bubbleHeight: CGFloat = 46
    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 4

    let entry: KanjiRadicalFileIndex.Entry

    // 音読み(カタカナ)と訓読み(ひらがな)の境目に / を入れる。索引は音→訓の順で並ぶ。
    // 片方しか無い字(コウ だけ/さんずい だけ)はスラッシュを付けない(2491)。
    static func readingsDisplayText(for readings: String) -> String {
        var onReadings: [String] = []
        var kunReadings: [String] = []
        for token in readings.split(separator: " ").map(String.init) {
            let isKatakana = token.unicodeScalars.allSatisfy {
                (0x30A1...0x30F6).contains($0.value) || $0.value == 0x30FC
            }
            if isKatakana {
                onReadings.append(token)
            } else {
                kunReadings.append(token)
            }
        }
        guard !onReadings.isEmpty, !kunReadings.isEmpty else {
            return readings
        }
        return onReadings.joined(separator: " ") + " / " + kunReadings.joined(separator: " ")
    }

    private var codePointText: String {
        guard let scalar = entry.character.unicodeScalars.first else {
            return "—"
        }
        return String(format: "U+%04X", scalar.value)
    }

    // 吹き出し左上の位置(セクション座標)。キーの上に出せなければ横、はみ出しはクランプ。
    static func placement(forKey keyFrame: CGRect, in size: CGSize) -> CGPoint {
        func clampedX(_ x: CGFloat) -> CGFloat {
            min(max(x, margin), max(margin, size.width - bubbleWidth - margin))
        }
        func clampedY(_ y: CGFloat) -> CGFloat {
            min(max(y, margin), max(margin, size.height - bubbleHeight - margin))
        }
        let above = keyFrame.minY - gap - bubbleHeight
        if above >= margin {
            return CGPoint(x: clampedX(keyFrame.midX - bubbleWidth / 2), y: above)
        }
        // 最上段: 指はキーの上にあるので、広い側(キーが左半分なら右、右半分なら左)へ逃がす
        let sideX = keyFrame.midX <= size.width / 2
            ? keyFrame.maxX + gap
            : keyFrame.minX - gap - bubbleWidth
        return CGPoint(x: clampedX(sideX), y: clampedY(keyFrame.minY))
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(Self.readingsDisplayText(for: entry.readings))
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
        .frame(width: Self.bubbleWidth)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
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

// 字グリッドの総画数の区切り(タップできない)。部首一覧の区切り(塗りの角丸)とは形で
// 区別し、カプセル+輪郭線+「総N画」にする(部首の画数と総画数の混同を防ぐ。2483)。
// 枠だけ+淡色だと読みづらかったので、枠の中に塗りを入れ、文字も少し大きく濃くした(2488)。
struct KanjiTotalStrokeMarkerCell: View {
    let strokes: Int
    let height: CGFloat

    var body: some View {
        Text("総\(strokes)画")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(.label).opacity(0.7))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 1)
                    )
            )
            .accessibilityLabel("総画数\(strokes)画")
    }
}

// 画数の区切り(タップできない)。「3画」のように示す。
struct RadicalStrokeMarkerCell: View {
    let strokes: Int
    let height: CGFloat

    var body: some View {
        Text("\(strokes)画")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(.label).opacity(0.75))
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
    let strokeCountStyle: RadicalStrokeCountStyle
    let onLookupEntries: (Int) -> [KanjiRadicalFileIndex.Entry]
    let onCommitCharacter: (String) -> Void
    let onSwitchToKana: () -> Void
    let onDeleteBackward: () -> Void

    // ロングタップ中の字と接触点(セクション座標)。オーバーレイはキーより後に描かれるので
    // 隣のキーの下に潜らない(2481)
    @State private var inspectedEntry: KanjiRadicalFileIndex.Entry?
    @State private var inspectedKeyFrame: CGRect = .zero

    private var forms: [RadicalForm] {
        KanjiRadicalCatalog.forms(in: selectedCategory, style: strokeCountStyle)
    }

    private var radicalColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 7)
    }

    private var characterColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 9)
    }

    // 字グリッドに総画数の区切り(タップ不可)を挟む。索引は総画数順に並んでいるので
    // 値が変わった位置に入れるだけでよい(2483)
    enum CharacterListItem {
        case totalStrokeMarker(Int)
        case character(KanjiRadicalFileIndex.Entry)
    }

    // 総画数は Unicode(Unihan kTotalStrokes)の値をそのまま使う。部首の数え方の設定ぶんを
    // 足し引きする方式(2483)は、字ごとにどの字形を使うか索引に無いため一律加算になり不正確
    // だった。数え方が分かれる字形はヘッダーに「N画に数えてください」と添えて読み替えを促す(2492)。
    private func characterListItems(for form: RadicalForm) -> [(id: String, kind: CharacterListItem)] {
        var items: [(id: String, kind: CharacterListItem)] = []
        var lastTotal = -1
        for entry in onLookupEntries(form.radical) {
            let total = entry.totalStrokes
            if total > 0, total != lastTotal {
                items.append((id: "total-\(total)", kind: .totalStrokeMarker(total)))
                lastTotal = total
            }
            items.append((id: "char-\(entry.character)", kind: .character(entry)))
        }
        return items
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
            let strokes = form.strokes(style: strokeCountStyle)
            if strokes != lastStrokes {
                items.append((id: "marker-\(strokes)", kind: .strokeMarker(strokes)))
                lastStrokes = strokes
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
                        ForEach(characterListItems(for: form), id: \.id) { item in
                            switch item.kind {
                            case .totalStrokeMarker(let strokes):
                                KanjiTotalStrokeMarkerCell(
                                    strokes: strokes,
                                    height: compactEmojiKeyHeight
                                )
                            case .character(let entry):
                                KanjiCharacterKeyButton(
                                    entry: entry,
                                    height: compactEmojiKeyHeight,
                                    onCommit: onCommitCharacter,
                                    onInspect: { inspected, keyFrame in
                                        inspectedEntry = inspected
                                        inspectedKeyFrame = keyFrame
                                    }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: fourRowAlignedTopContentHeight)
                // 接触点とクランプ範囲の基準(この矩形の中に吹き出しを収める)
                .coordinateSpace(name: KanjiInspectBubble.coordinateSpaceName)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        if let inspectedEntry {
                            let origin = KanjiInspectBubble.placement(
                                forKey: inspectedKeyFrame,
                                in: proxy.size
                            )
                            KanjiInspectBubble(entry: inspectedEntry)
                                .offset(x: origin.x, y: origin.y)
                        }
                    }
                    .allowsHitTesting(false)
                }
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
