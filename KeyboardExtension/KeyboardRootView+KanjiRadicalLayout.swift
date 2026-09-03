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
            strokeChoices: radicalStrokeChoices,
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

// 字グリッド(2783): SwiftUI の LazyVGrid から UICollectionView+UILabel(セル再利用)へ。
// 実機実測(2782)で部首1つの一覧を約30秒スクロールすると used +16.6MB、退出後も +9.7MB が残った。
// 内訳は明朝グリフキャッシュ約5MB(上限付きで頭打ち)+ SwiftUI 側約10MB(LazyVGrid が生成した
// セル/AttributeGraph を閉じるまで保持)。絵文字パネル(EmojiGridCollectionView 2633)と同じ処方で
// 同時生存のセルを画面分に固定する。描画倍率は落とさない(ぼやける。ユーザ指定)。
// タップ=確定、0.35秒の長押し=字典風の吹き出し(読み/U+XXXX/区点)。長押し成立後は離しても確定しない。
struct KanjiCharacterGridCollectionView: UIViewRepresentable {
    typealias Item = (id: String, kind: KeyboardRootKanjiRadicalSectionView.CharacterListItem)

    let items: [Item]
    let columnCount: Int
    let itemSpacing: CGFloat
    let itemHeight: CGFloat
    /// 部首の切替検知(変わったら先頭へスクロール)
    let formKey: String
    let onCommit: (String) -> Void

    // 別フォントで描かれる字の色。薄いブルー系。ライト/ダークで明度を入れ替えて、
    // どちらの背景でも読める濃さにする(2485)
    static let fallbackGlyphColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.58, green: 0.76, blue: 1.0, alpha: 1.0)
            : UIColor(red: 0.32, green: 0.52, blue: 0.88, alpha: 1.0)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = itemSpacing
        layout.sectionInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = true
        view.delaysContentTouches = false
        view.register(KanjiCharacterGridCell.self, forCellWithReuseIdentifier: KanjiCharacterGridCell.reuseIdentifier)
        view.register(KanjiTotalStrokeMarkerGridCell.self, forCellWithReuseIdentifier: KanjiTotalStrokeMarkerGridCell.reuseIdentifier)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.parent = self
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let formChanged = coordinator.parent.formKey != formKey
        let itemsChanged = coordinator.parent.items.count != items.count || formChanged
        coordinator.parent = self
        if let layout = uiView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.minimumInteritemSpacing = itemSpacing
            layout.minimumLineSpacing = itemSpacing
        }
        if itemsChanged {
            coordinator.hideBubble()
            uiView.reloadData()
            if formChanged {
                uiView.setContentOffset(.zero, animated: false)
            }
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        var parent: KanjiCharacterGridCollectionView
        private weak var bubble: UIView?
        // 長押しが成立したタッチでは離しても確定しない(旧 didTriggerLongPress)
        private var didTriggerLongPress = false

        init(parent: KanjiCharacterGridCollectionView) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            switch parent.items[indexPath.item].kind {
            case .totalStrokeMarker(let strokes):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: KanjiTotalStrokeMarkerGridCell.reuseIdentifier, for: indexPath
                )
                (cell as? KanjiTotalStrokeMarkerGridCell)?.configure(strokes: strokes)
                return cell
            case .character(let entry):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: KanjiCharacterGridCell.reuseIdentifier, for: indexPath
                )
                (cell as? KanjiCharacterGridCell)?.configure(entry: entry)
                return cell
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let columns = max(1, parent.columnCount)
            let available = collectionView.bounds.width - parent.itemSpacing * CGFloat(columns - 1)
            let width = floor(max(1, available / CGFloat(columns)))
            return CGSize(width: width, height: parent.itemHeight)
        }

        func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
            if case .character = parent.items[indexPath.item].kind {
                return true
            }
            return false
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            if didTriggerLongPress {
                didTriggerLongPress = false
                return
            }
            if case .character(let entry) = parent.items[indexPath.item].kind {
                parent.onCommit(entry.character)
            }
        }

        func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
            // 指が離れた/スクロールで押下が取り消された
            hideBubble()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            hideBubble()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let collectionView = recognizer.view as? UICollectionView else { return }
            switch recognizer.state {
            case .began:
                let point = recognizer.location(in: collectionView)
                guard let indexPath = collectionView.indexPathForItem(at: point),
                    case .character(let entry) = parent.items[indexPath.item].kind,
                    let cell = collectionView.cellForItem(at: indexPath) else {
                    return
                }
                didTriggerLongPress = true
                showBubble(for: entry, above: cell, in: collectionView)
            case .ended, .cancelled, .failed:
                hideBubble()
                // 長押し中に離した場合、didSelect は来ないことがあるのでフラグは次のタップ開始で戻す
                DispatchQueue.main.async { [weak self] in self?.didTriggerLongPress = false }
            default:
                break
            }
        }

        // 字典風の吹き出し(旧 KanjiInspectBubble と同じ寸法・配置規則)。可視領域の座標で置く
        private func showBubble(for entry: KanjiRadicalFileIndex.Entry, above cell: UIView, in host: UICollectionView) {
            hideBubble()
            let visibleSize = host.bounds.size
            let cellFrameInContent = cell.convert(cell.bounds, to: host)
            let keyFrameVisible = cellFrameInContent.offsetBy(dx: -host.contentOffset.x, dy: -host.contentOffset.y)
            let origin = KanjiInspectBubble.placement(forKey: keyFrameVisible, in: visibleSize)

            let container = UIView(frame: CGRect(
                x: origin.x + host.contentOffset.x,
                y: origin.y + host.contentOffset.y,
                width: KanjiInspectBubble.bubbleWidth,
                height: KanjiInspectBubble.bubbleHeight
            ))
            container.backgroundColor = UIColor.black.withAlphaComponent(0.86)
            container.layer.cornerRadius = 8
            container.layer.cornerCurve = .continuous
            container.layer.shadowColor = UIColor.black.cgColor
            container.layer.shadowOpacity = 0.25
            container.layer.shadowRadius = 6
            container.layer.shadowOffset = CGSize(width: 0, height: 2)
            container.isUserInteractionEnabled = false

            let readings = UILabel()
            readings.text = KanjiInspectBubble.readingsDisplayText(for: entry.readings)
            readings.font = Self.roundedFont(size: 12, weight: .bold)
            readings.textColor = .white
            readings.textAlignment = .center
            readings.numberOfLines = 2
            readings.adjustsFontSizeToFitWidth = true
            readings.minimumScaleFactor = 0.7
            let code = UILabel()
            let codePoint = entry.character.unicodeScalars.first.map { String(format: "U+%04X", $0.value) } ?? "—"
            code.text = "\(codePoint)  区点 \(entry.kuten)"
            code.font = Self.roundedFont(size: 10.5, weight: .medium)
            code.textColor = UIColor.white.withAlphaComponent(0.82)
            code.textAlignment = .center
            code.adjustsFontSizeToFitWidth = true
            code.minimumScaleFactor = 0.8
            let inner = KanjiInspectBubble.bubbleWidth - 20
            readings.frame = CGRect(x: 10, y: 5, width: inner, height: 22)
            code.frame = CGRect(x: 10, y: 28, width: inner, height: 13)
            container.addSubview(readings)
            container.addSubview(code)
            host.addSubview(container)
            bubble = container
        }

        private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            if let descriptor = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        }

        func hideBubble() {
            bubble?.removeFromSuperview()
            bubble = nil
        }
    }
}

final class KanjiCharacterGridCell: UICollectionViewCell {
    static let reuseIdentifier = "KanjiCharacterGridCell"
    private let label = UILabel()
    private static let minchoFont = UIFont(name: "HiraMinProN-W3", size: 22) ?? UIFont.systemFont(ofSize: 22)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 6
        contentView.layer.cornerCurve = .continuous
        label.font = Self.minchoFont
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.isAccessibilityElement = false
        contentView.addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }

    // ヒラギノ明朝にグリフが無い字(実機では PingFang 等で描かれる)は色を変えて区別する。
    // 判定は表示中のセルぶんだけ実行するのでデータに印は持たせない(2445)
    func configure(entry: KanjiRadicalFileIndex.Entry) {
        label.text = entry.character
        label.textColor = KanaKanjiStore.hasMinchoGlyph(for: entry.character)
            ? .label
            : KanjiCharacterGridCollectionView.fallbackGlyphColor
        accessibilityLabel = "\(entry.character) \(entry.readings)"
    }

    override var isHighlighted: Bool {
        didSet {
            let pressed = isHighlighted
            UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.contentView.transform = pressed ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.transform = .identity
    }
}

// 総画数の区切り(タップできない)。カプセル+輪郭線+「総N画」(2483/2488)
final class KanjiTotalStrokeMarkerGridCell: UICollectionViewCell {
    static let reuseIdentifier = "KanjiTotalStrokeMarkerGridCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .tertiarySystemFill
        contentView.layer.borderColor = UIColor.separator.cgColor
        contentView.layer.borderWidth = 1
        let base = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 12) } ?? base
        label.textColor = UIColor.label.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        contentView.addSubview(label)
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds.insetBy(dx: 2, dy: 0)
        contentView.layer.cornerRadius = contentView.bounds.height / 2
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        contentView.layer.borderColor = UIColor.separator.cgColor
    }

    func configure(strokes: Int) {
        label.text = "総\(strokes)画"
        accessibilityLabel = "総画数\(strokes)画"
    }
}

// 字のロングタップで出す字典風ポップアップ(読み / U+XXXX / JIS X 0208区点)の寸法・配置規則。
// 描画は KanjiCharacterGridCollectionView の Coordinator(UIKit)が行う(2783)。位置はキーの矩形から
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
    // 設定で選んだ字形(艸 等)。選択肢を持たない部首は plist の字形そのまま(2503)
    let displayForm: String
    let isSelected: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(displayForm)
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
        .accessibilityLabel("\(displayForm) \(form.name)")
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
    let strokeChoices: RadicalStrokeChoices
    let onLookupEntries: (Int) -> [KanjiRadicalFileIndex.Entry]
    let onCommitCharacter: (String) -> Void
    let onSwitchToKana: () -> Void
    let onDeleteBackward: () -> Void

    private var forms: [RadicalForm] {
        KanjiRadicalCatalog.forms(in: selectedCategory, choices: strokeChoices)
    }

    private var radicalColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: emojiGridSpacing), count: 7)
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
            let strokes = form.strokes(choices: strokeChoices)
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
                // 戻るはヘッダー(◀ 偏 › 氵(さんずい))が担う。行内にパンくずは置かない。
                // 字グリッドは UICollectionView(セル再利用。吹き出しもその中で描く。2783)
                KanjiCharacterGridCollectionView(
                    items: characterListItems(for: form),
                    columnCount: 9,
                    itemSpacing: emojiGridSpacing,
                    itemHeight: compactEmojiKeyHeight,
                    formKey: form.id,
                    onCommit: onCommitCharacter
                )
                .frame(height: fourRowAlignedTopContentHeight)
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
                                    displayForm: form.displayForm(choices: strokeChoices),
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
