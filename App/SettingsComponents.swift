import SwiftUI
import UIKit
import UniformTypeIdentifiers

// 各項目が基準の初期設定(最後に当てた初期設定)から変わっているかの印(3432)。設定の値が変わるたびに描き直すため、
// UserDefaults の変更通知を数えるだけの観測対象を持つ
final class SettingsChangeTracker: ObservableObject {
    static let shared = SettingsChangeTracker()
    @Published private(set) var revision = 0
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.revision += 1
        }
    }
}

// 項目番号(X.9 等)→ その項目が表示・編集する設定キー(3432。ContentView のカード群と照合済み)
enum SettingsCardKeys {
    static let keysByCardID: [String: [String]] = [
        "E.1": [SettingsKeys.directionProfile],
        "E.2": [SettingsKeys.keyRepeatInitialDelay, SettingsKeys.keyRepeatInterval],
        "E.3": [SettingsKeys.idleCommitEnabled, SettingsKeys.idleCommitInterval],
        "E.4": [SettingsKeys.composingTextStyle],
        "E.5": [SettingsKeys.kanaModeSwitcherTapAction, SettingsKeys.kanaModeSwitcherRightFlickAction, SettingsKeys.kanaModeSwitcherUpFlickAction],
        "E.6": [SettingsKeys.kanaPostModifierEmptyTapAction, SettingsKeys.kanaPostModifierEmptyTapKaomojiCategory,
                SettingsKeys.kanaPostModifierEmptyTapEmojiCategory, SettingsKeys.kanaPostModifierEmptyTapSymbolCategory],
        "E.7": [SettingsKeys.kanaPostModifierFlickDakutenEnabled],
        "E.8": [SettingsKeys.latinLexiconEnglishEnabled, SettingsKeys.latinLexiconFrenchEnabled,
                SettingsKeys.latinLexiconGermanEnabled, SettingsKeys.latinLexiconItalianEnabled],
        "F.1": [SettingsKeys.numberThousandsSeparator, SettingsKeys.numberGroupFourDigits, SettingsKeys.numberDecimalSeparator,
                SettingsKeys.numberUnitProductSeparator, SettingsKeys.numberLitreSymbol],
        "F.2": [SettingsKeys.degreeSymbol],
        "F.3": [SettingsKeys.calendarWeekStart, SettingsKeys.calendarWeekdayLanguage, SettingsKeys.calendarSundayColor,
                SettingsKeys.calendarFridayColor, SettingsKeys.calendarSaturdayColor, SettingsKeys.dateFormatStyle],
        "G.1": [SettingsKeys.kanaFlickGuideDisplayMode, SettingsKeys.latinFlickGuideDisplayMode,
                SettingsKeys.numberFlickGuideDisplayMode, SettingsKeys.modifierFlickGuideDisplayMode],
        "L.1": [SettingsKeys.kanaLayoutMode],
        "L.2": [SettingsKeys.latinLayoutMode],
        "L.3": [SettingsKeys.numberLayoutMode, SettingsKeys.formattedNumberKeypadLayout],
        "L.4": [SettingsKeys.basicSymbolOrder],
        "L.5": [SettingsKeys.kanaModifierPlacement],
        "V.1": [SettingsKeys.landscapeCandidateSide, SettingsKeys.landscapeLatinSuggestionMode],
        "V.2": [SettingsKeys.landscapeNumberPaneSide],
        "V.3": [SettingsKeys.accentPalette],
        "V.4": [SettingsKeys.keyboardBackgroundTheme],
        "X.1": [SettingsKeys.delimiterAutoCommitCandidate],
        "X.2": [SettingsKeys.kanaKanjiCandidateSourceMode],
        "X.3": [SettingsKeys.historicalKanaCandidatesEnabled],
        "X.4": [SettingsKeys.iterationMarkCandidatesEnabled],
        "X.5": [SettingsKeys.katakanaEmphasisCandidateMode],
        "X.6": [SettingsKeys.mazegakiCandidateMode],
        "X.7": [SettingsKeys.scriptVariantSuppressKyujitai, SettingsKeys.scriptVariantSuppressItaiji, SettingsKeys.scriptVariantSuppressRyakuji,
                SettingsKeys.scriptVariantSuppressConfusable, SettingsKeys.scriptVariantSuppressLookalike, SettingsKeys.scriptVariantSuppressPersonNameVariant],
        "X.8": [SettingsKeys.kanaGakiSuppressAdverb, SettingsKeys.kanaGakiSuppressConjunction, SettingsKeys.kanaGakiSuppressAuxiliary,
                SettingsKeys.kanaGakiSuppressFormalNoun, SettingsKeys.kanaGakiSuppressDemonstrative],
        "X.9": [SettingsKeys.kakikaePreference],
        "X.10": [SettingsKeys.radicalStrokeCountStyle],
        "X.11": [SettingsKeys.kaCounterVariantPreference],
        "X.12": [SettingsKeys.okuriganaVariantPreference],
        "X.13": [SettingsKeys.ordinalMeKanjiPreferred],
        "X.14": [SettingsKeys.adjectiveMeKanjiCandidatesEnabled],
        "X.15": [SettingsKeys.emojiCandidateDisplayEnabled, SettingsKeys.kaomojiCandidateDisplayEnabled],
        "X.16": [SettingsKeys.contactCandidateDisplayMode],
        "X.17": [SettingsKeys.userDictionaryCandidateDisplayMode]
    ]

    // 見出しの先頭の番号(「X.9 常用漢字による書きかえ」→ X.9)
    static func cardID(fromTitle title: String) -> String? {
        guard let first = title.split(separator: " ", maxSplits: 1).first,
            keysByCardID[String(first)] != nil else {
            return nil
        }
        return String(first)
    }
}

// 見出しの右に置く「変更済み」の印。基準の初期設定から変わっている項目にだけ、小さく淡く出す(3432、ユーザ指定)
struct SettingsModifiedMark: View {
    let title: String
    @ObservedObject private var tracker = SettingsChangeTracker.shared

    var body: some View {
        let _ = tracker.revision
        if let cardID = SettingsCardKeys.cardID(fromTitle: title),
            let keys = SettingsCardKeys.keysByCardID[cardID],
            ContentView.isModifiedFromBasePreset(keys: keys) {
            Text("●")
                .font(.system(size: 8))
                .foregroundStyle(Color.accentColor.opacity(0.75))
                .accessibilityLabel("初期設定から変更あり")
        }
    }
}

// 項目の見出し(太字)と変更済みの印(3432)
struct SettingsCardHeadline: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Text(title)
                .font(.headline)
            SettingsModifiedMark(title: title)
        }
    }
}

// 設定カードの見出し。subtitle(旧タイトルの仏語例など)は小さく薄い字で 2 行目に置く(2817)
struct SettingsCardTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingsCardHeadline(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct SegmentedSettingsCard<Option: Hashable>: View {
    let title: String
    var subtitle: String? = nil
    let pickerTitle: String
    @Binding var selection: Option
    let options: [Option]
    let optionTitle: (Option) -> String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCardTitle(title: title, subtitle: subtitle)

            Picker(pickerTitle, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

// 脚注をビューで組み立てる版。箇条書きや消し線のように、ひとつの文字列では表せない説明に使う。
enum LatinCandidatePaneArrangementItem: String, CaseIterable, Identifiable {
    case latin
    case candidate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latin:
            return "ラテン文字"
        case .candidate:
            return "候補"
        }
    }
}

enum NumberPaneArrangementItem: String, CaseIterable, Identifiable {
    case number
    case symbols

    var id: String { rawValue }

    var title: String {
        switch self {
        case .number:
            return "数字"
        case .symbols:
            return "記号"
        }
    }
}

struct PanePairSwapDropDelegate<Item: Equatable>: DropDelegate {
    let targetItem: Item
    let orderedItems: [Item]
    @Binding var draggingItem: Item?
    let onReorder: ([Item]) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggingItem,
            draggingItem != targetItem,
            let sourceIndex = orderedItems.firstIndex(of: draggingItem),
            let targetIndex = orderedItems.firstIndex(of: targetItem) else {
            return
        }

        var nextOrder = orderedItems
        nextOrder.swapAt(sourceIndex, targetIndex)
        onReorder(nextOrder)
        self.draggingItem = targetItem
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}

struct DraggablePanePairRow<Item: Identifiable & Equatable>: View where Item.ID == String {
    let items: [Item]
    let title: (Item) -> String
    let onReorder: ([Item]) -> Void

    @State private var draggingItem: Item?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 7) {
                    Image(systemName: "line.3.horizontal")
                        .rotationEffect(.degrees(90))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(title(item))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.controlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            draggingItem == item
                                ? Color.accentColor.opacity(0.55)
                                : AppTheme.subtleBorder,
                            lineWidth: draggingItem == item ? 1.4 : 1
                        )
                )
                .onDrag {
                    draggingItem = item
                    return NSItemProvider(object: NSString(string: item.id))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: PanePairSwapDropDelegate(
                        targetItem: item,
                        orderedItems: items,
                        draggingItem: $draggingItem,
                        onReorder: onReorder
                    )
                )
            }
        }
    }
}

struct ScrollIndexBadgeView: View {
    let title: String
    let isVisible: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Spacer(minLength: 8)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(minWidth: 26, minHeight: 20)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.indexBadgeBackground)
                )
                .opacity(isVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.28), value: isVisible)
        }
    }
}

func applyScrollIndexIndicatorState(
    title: String,
    isVisible: Bool,
    scrollIndexTitle: Binding<String>,
    isScrollIndexVisible: Binding<Bool>
) {
    DispatchQueue.main.async {
        if !title.isEmpty, scrollIndexTitle.wrappedValue != title {
            scrollIndexTitle.wrappedValue = title
        }

        if isScrollIndexVisible.wrappedValue != isVisible {
            withAnimation(.easeOut(duration: 0.28)) {
                isScrollIndexVisible.wrappedValue = isVisible
            }
        }
    }
}

struct DictionaryRegistrationHeaderView: View {
    let title: String
    let count: Int
    let isRegistrationVisible: Bool
    let showAccessibilityLabel: String
    let hideAccessibilityLabel: String
    let onToggleRegistration: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)

            Text("\(count)件")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(action: onToggleRegistration) {
                Image(systemName: isRegistrationVisible ? "xmark" : "plus")
                    .font(.headline.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(
                                isRegistrationVisible
                                    ? Color.red.opacity(0.16)
                                    : Color.accentColor.opacity(0.14)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isRegistrationVisible
                    ? hideAccessibilityLabel
                    : showAccessibilityLabel
            )
        }
    }
}

struct DictionaryInputField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.controlBackground)
            )
            .frame(maxWidth: .infinity)
    }
}

struct DictionaryRegistrationActionRow: View {
    let isEditing: Bool
    let canSubmit: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(isEditing ? "保存" : "登録") {
                onSubmit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .font(.footnote.weight(.semibold))
            .disabled(!canSubmit)

            if isEditing {
                Button("キャンセル") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.subheadline)
            }
        }
    }
}

struct DictionaryRegistrationForm<Fields: View>: View {
    let title: String
    let isEditing: Bool
    let canSubmit: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let fields: Fields

    init(
        title: String,
        isEditing: Bool,
        canSubmit: Bool,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder fields: () -> Fields
    ) {
        self.title = title
        self.isEditing = isEditing
        self.canSubmit = canSubmit
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.fields = fields()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                fields

                DictionaryRegistrationActionRow(
                    isEditing: isEditing,
                    canSubmit: canSubmit,
                    onSubmit: onSubmit,
                    onCancel: onCancel
                )
            }
        }
    }
}
