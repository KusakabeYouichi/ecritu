import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SegmentedSettingsCard<Option: Hashable>: View {
    let title: String
    let pickerTitle: String
    @Binding var selection: Option
    let options: [Option]
    let optionTitle: (Option) -> String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

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
