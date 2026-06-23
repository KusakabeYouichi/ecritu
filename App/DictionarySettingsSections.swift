import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct UserDictionarySettingsSection: View {
    @Binding var entries: [VocabularyEntry]
    @Binding var readingInput: String
    @Binding var candidateInput: String
    @Binding var isRegistrationVisible: Bool
    @Binding var scrollIndexTitle: String
    @Binding var isScrollIndexVisible: Bool

    let canAddEntry: Bool
    let listHeight: CGFloat
    let onAddEntry: () -> Void
    let onUpdateEntry: (VocabularyEntry) -> Void
    let onDeleteEntry: (VocabularyEntry) -> Void
    let onDeleteAll: () -> Void
    let onReimportInitialEntries: () -> Void

    @State private var isDeleteAllConfirmationPresented = false
    @State private var isReimportConfirmationPresented = false
    @State private var editingEntry: VocabularyEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DictionaryRegistrationHeaderView(
                title: "追加語彙",
                count: entries.count,
                isRegistrationVisible: isRegistrationVisible,
                showAccessibilityLabel: "追加単語の登録欄を表示",
                hideAccessibilityLabel: "追加単語の登録欄を閉じる",
                onToggleRegistration: {
                    if isRegistrationVisible {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                        return
                    }

                    editingEntry = nil
                    readingInput = ""
                    candidateInput = ""

                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegistrationVisible = true
                    }
                }
            )

            if isRegistrationVisible {
                DictionaryRegistrationForm(
                    title: editingEntry == nil ? "追加単語の登録" : "追加単語の編集",
                    isEditing: editingEntry != nil,
                    canSubmit: canAddEntry,
                    onSubmit: {
                        if let editingEntry {
                            onUpdateEntry(editingEntry)
                        } else {
                            onAddEntry()
                        }
                        editingEntry = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                    },
                    onCancel: {
                        editingEntry = nil
                        readingInput = ""
                        candidateInput = ""
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                    }
                ) {
                    DictionaryInputField(placeholder: "候補", text: $candidateInput)
                    DictionaryInputField(placeholder: "よみ", text: $readingInput)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollIndexBadgeView(
                title: scrollIndexTitle,
                isVisible: isScrollIndexVisible
            )

            if entries.isEmpty {
                Text("登録済みの追加単語はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    listHeight: listHeight,
                    selectedEntryID: editingEntry?.id,
                    onDelete: { entry in
                        if editingEntry?.id == entry.id {
                            editingEntry = nil
                            readingInput = ""
                            candidateInput = ""
                        }
                        onDeleteEntry(entry)
                    },
                    onSelect: { entry in
                        editingEntry = entry
                        readingInput = entry.reading
                        candidateInput = entry.candidate

                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = true
                        }
                    },
                    onIndexIndicatorStateChange: { title, isVisible in
                        applyScrollIndexIndicatorState(
                            title: title,
                            isVisible: isVisible,
                            scrollIndexTitle: $scrollIndexTitle,
                            isScrollIndexVisible: $isScrollIndexVisible
                        )
                    }
                )
                .frame(height: listHeight)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        isReimportConfirmationPresented = true
                    } label: {
                        Text("初期語彙再投入")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .confirmationDialog(
                        "初期追加語彙を再投入しますか?",
                        isPresented: $isReimportConfirmationPresented,
                        titleVisibility: .visible
                    ) {
                        Button("再投入する") {
                            onReimportInitialEntries()
                        }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("現在の追加語彙を残したまま、初期追加語彙を再投入します。")
                    }

                    if !entries.isEmpty {
                        Button(role: .destructive) {
                            isDeleteAllConfirmationPresented = true
                        } label: {
                            Text("全削除")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .confirmationDialog(
                            "追加語彙をすべて削除しますか?",
                            isPresented: $isDeleteAllConfirmationPresented,
                            titleVisibility: .visible
                        ) {
                            Button("すべて削除", role: .destructive) {
                                onDeleteAll()
                            }
                            Button("キャンセル", role: .cancel) {}
                        } message: {
                            Text("この操作は元に戻せません。")
                        }
                    }
                }
            }

            Text("追加単語はキーボード拡張と共有され、候補の優先順位に反映されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct LearnedDictionarySettingsSection: View {
    @Binding var entries: [VocabularyEntry]
    @Binding var scrollIndexTitle: String
    @Binding var isScrollIndexVisible: Bool

    let listHeight: CGFloat
    let onDeleteEntry: (VocabularyEntry) -> Void
    let onDeleteAll: () -> Void
    let onResetLearning: () -> Void

    @State private var isDeleteAllConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("学習語彙")
                    .font(.headline)

                Text("\(entries.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
            }

            ScrollIndexBadgeView(
                title: scrollIndexTitle,
                isVisible: isScrollIndexVisible
            )

            if entries.isEmpty {
                Text("学習で蓄積された語彙はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    listHeight: listHeight,
                    selectedEntryID: nil,
                    onDelete: onDeleteEntry,
                    onSelect: nil,
                    onIndexIndicatorStateChange: { title, isVisible in
                        applyScrollIndexIndicatorState(
                            title: title,
                            isVisible: isVisible,
                            scrollIndexTitle: $scrollIndexTitle,
                            isScrollIndexVisible: $isScrollIndexVisible
                        )
                    }
                )
                .frame(height: listHeight)
            }

            HStack(spacing: 12) {
                Button {
                    onResetLearning()
                } label: {
                    Text("学習リセット")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !entries.isEmpty {
                    Button(role: .destructive) {
                        isDeleteAllConfirmationPresented = true
                    } label: {
                        Text("学習語彙全削除")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .confirmationDialog(
                        "学習語彙をすべて削除しますか?",
                        isPresented: $isDeleteAllConfirmationPresented,
                        titleVisibility: .visible
                    ) {
                        Button("すべて削除", role: .destructive) {
                            onDeleteAll()
                        }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("この操作は元に戻せません。")
                    }
                }
            }

            Text(
                "学習語彙は確定操作から自動登録された候補です。手動で登録する追加語彙とは別に管理されます。\n"
                    + "学習語彙全削除: 語彙リストは消えるが、学習スコア由来の癖は残る\n"
                    + "学習リセット: 語彙リストも学習スコアも消える(より完全な初期化)\n"
                    + "※ キーボードの『フルアクセスを許可』がOFFだと学習語彙と学習スコアは保存されません。"
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct SuppressionDictionarySettingsSection: View {
    @Binding var entries: [VocabularyEntry]
    @Binding var readingInput: String
    @Binding var candidateInput: String
    @Binding var isRegistrationVisible: Bool
    @Binding var scrollIndexTitle: String
    @Binding var isScrollIndexVisible: Bool

    let canAddEntry: Bool
    let listHeight: CGFloat
    let onAddEntry: () -> Void
    let onUpdateEntry: (VocabularyEntry) -> Void
    let onDeleteEntry: (VocabularyEntry) -> Void

    @State private var editingEntry: VocabularyEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DictionaryRegistrationHeaderView(
                title: "抑制語彙",
                count: entries.count,
                isRegistrationVisible: isRegistrationVisible,
                showAccessibilityLabel: "抑制単語の登録欄を表示",
                hideAccessibilityLabel: "抑制単語の登録欄を閉じる",
                onToggleRegistration: {
                    if isRegistrationVisible {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                        return
                    }

                    editingEntry = nil
                    readingInput = ""
                    candidateInput = ""

                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegistrationVisible = true
                    }
                }
            )

            if isRegistrationVisible {
                DictionaryRegistrationForm(
                    title: editingEntry == nil ? "抑制単語の登録" : "抑制単語の編集",
                    isEditing: editingEntry != nil,
                    canSubmit: canAddEntry,
                    onSubmit: {
                        if let editingEntry {
                            onUpdateEntry(editingEntry)
                        } else {
                            onAddEntry()
                        }
                        editingEntry = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                    },
                    onCancel: {
                        editingEntry = nil
                        readingInput = ""
                        candidateInput = ""
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                    }
                ) {
                    DictionaryInputField(placeholder: "単語", text: $candidateInput)
                    DictionaryInputField(placeholder: "よみ", text: $readingInput)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollIndexBadgeView(
                title: scrollIndexTitle,
                isVisible: isScrollIndexVisible
            )

            if entries.isEmpty {
                Text("登録済みの抑制単語はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    listHeight: listHeight,
                    selectedEntryID: editingEntry?.id,
                    onDelete: { entry in
                        if editingEntry?.id == entry.id {
                            editingEntry = nil
                            readingInput = ""
                            candidateInput = ""
                        }
                        onDeleteEntry(entry)
                    },
                    onSelect: { entry in
                        editingEntry = entry
                        readingInput = entry.reading
                        candidateInput = entry.candidate

                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = true
                        }
                    },
                    onIndexIndicatorStateChange: { title, isVisible in
                        applyScrollIndexIndicatorState(
                            title: title,
                            isVisible: isVisible,
                            scrollIndexTitle: $scrollIndexTitle,
                            isScrollIndexVisible: $isScrollIndexVisible
                        )
                    }
                )
                .frame(height: listHeight)
            }

            Text("抑制は『読み+単語』の組み合わせで適用され、同じ単語でも別の読み候補には影響しません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct ShortcutDictionarySettingsSection: View {
    @Binding var entries: [VocabularyEntry]
    @Binding var candidateInput: String
    @Binding var isRegistrationVisible: Bool

    @State private var pendingDeletionEntry: VocabularyEntry?
    @State private var editingEntry: VocabularyEntry?

    let canAddEntry: Bool
    let listHeight: CGFloat
    let onAddEntry: () -> Void
    let onUpdateEntry: (VocabularyEntry) -> Void
    let onDeleteEntry: (VocabularyEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DictionaryRegistrationHeaderView(
                title: "ショートカット語彙",
                count: entries.count,
                isRegistrationVisible: isRegistrationVisible,
                showAccessibilityLabel: "ショートカット語彙の登録欄を表示",
                hideAccessibilityLabel: "ショートカット語彙の登録欄を閉じる",
                onToggleRegistration: {
                    if isRegistrationVisible {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistrationVisible = false
                        }
                        return
                    }

                    editingEntry = nil
                    candidateInput = ""

                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegistrationVisible = true
                    }
                }
            )

            if isRegistrationVisible {
                VStack(alignment: .leading, spacing: 8) {
                    DictionaryRegistrationForm(
                        title: editingEntry == nil ? "ショートカット語彙の登録" : "ショートカット語彙の編集",
                        isEditing: editingEntry != nil,
                        canSubmit: canAddEntry,
                        onSubmit: {
                            if let editingEntry {
                                onUpdateEntry(editingEntry)
                            } else {
                                onAddEntry()
                            }
                            editingEntry = nil
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegistrationVisible = false
                            }
                        },
                        onCancel: {
                            editingEntry = nil
                            candidateInput = ""
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegistrationVisible = false
                            }
                        }
                    ) {
                        DictionaryInputField(placeholder: "候補", text: $candidateInput)

                        HStack(spacing: 6) {
                            Text("よみ")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text("☻（固定）")
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.controlBackground)
                        )
                    }

                    Text("読みは ☻ で固定されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if entries.isEmpty {
                Text("登録済みのショートカット語彙はありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Text(entry.candidate)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    editingEntry?.id == entry.id
                                        ? Color.accentColor.opacity(0.22)
                                        : AppTheme.listRowBackground
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            editingEntry?.id == entry.id
                                                ? Color.accentColor.opacity(0.6)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingEntry = entry
                            candidateInput = entry.candidate
                            pendingDeletionEntry = nil

                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegistrationVisible = true
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if editingEntry?.id == entry.id {
                                    editingEntry = nil
                                    candidateInput = ""
                                }
                                pendingDeletionEntry = entry
                            } label: {
                                Text("削除")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 30)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(height: listHeight)
            }

            Text("ショートカット語彙は顔文字入力の先頭側に表示され、固定顔文字とは区切り線で分離されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
        .alert(
            "ショートカット語彙を削除しますか？",
            isPresented: Binding(
                get: { pendingDeletionEntry != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionEntry = nil
                    }
                }
            ),
            presenting: pendingDeletionEntry
        ) { entry in
            Button("キャンセル", role: .cancel) {
                pendingDeletionEntry = nil
            }

            Button("削除", role: .destructive) {
                onDeleteEntry(entry)
                pendingDeletionEntry = nil
            }
        } message: { entry in
            Text("「\(entry.candidate)」を削除します。")
        }
    }
}

struct ReadOnlyDictionarySettingsSection: View {
    let title: String
    let entries: [VocabularyEntry]
    @Binding var scrollIndexTitle: String
    @Binding var isScrollIndexVisible: Bool
    let listHeight: CGFloat
    let emptyMessage: String
    let description: String
    let actionButtonTitle: String?
    let actionButtonLoadingTitle: String?
    let isActionLoading: Bool
    let isActionDisabled: Bool
    let onAction: (() -> Void)?

    init(
        title: String,
        entries: [VocabularyEntry],
        scrollIndexTitle: Binding<String>,
        isScrollIndexVisible: Binding<Bool>,
        listHeight: CGFloat,
        emptyMessage: String,
        description: String,
        actionButtonTitle: String? = nil,
        actionButtonLoadingTitle: String? = nil,
        isActionLoading: Bool = false,
        isActionDisabled: Bool = false,
        onAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.entries = entries
        self._scrollIndexTitle = scrollIndexTitle
        self._isScrollIndexVisible = isScrollIndexVisible
        self.listHeight = listHeight
        self.emptyMessage = emptyMessage
        self.description = description
        self.actionButtonTitle = actionButtonTitle
        self.actionButtonLoadingTitle = actionButtonLoadingTitle
        self.isActionLoading = isActionLoading
        self.isActionDisabled = isActionDisabled
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)

                Text("\(entries.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
            }

            if let onAction,
                let actionButtonTitle {
                Button(action: onAction) {
                    HStack(spacing: 8) {
                        if isActionLoading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(isActionLoading ? (actionButtonLoadingTitle ?? actionButtonTitle) : actionButtonTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActionDisabled || isActionLoading)
            }

            ScrollIndexBadgeView(
                title: scrollIndexTitle,
                isVisible: isScrollIndexVisible
            )

            if entries.isEmpty {
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                IndexedVocabularyList(
                    entries: entries,
                    listHeight: listHeight,
                    selectedEntryID: nil,
                    onDelete: nil,
                    onSelect: nil,
                    onIndexIndicatorStateChange: { title, isVisible in
                        applyScrollIndexIndicatorState(
                            title: title,
                            isVisible: isVisible,
                            scrollIndexTitle: $scrollIndexTitle,
                            isScrollIndexVisible: $isScrollIndexVisible
                        )
                    }
                )
                .frame(height: listHeight)
            }

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}
