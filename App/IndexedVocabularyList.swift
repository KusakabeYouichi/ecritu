import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct IndexedVocabularyList: UIViewRepresentable {
    let entries: [VocabularyEntry]
    let listHeight: CGFloat
    let selectedEntryID: String?
    // 確認のダイアログを出している行(取り消し線で示す)。閉じて nil に戻ると[削除]も引っ込める
    var pendingDeletionEntryID: String? = nil
    // [削除]が押されたときに呼ぶ。消すのは呼び出し側が確認を取ってから
    let onDelete: ((VocabularyEntry) -> Void)?
    let onSelect: ((VocabularyEntry) -> Void)?
    let onIndexIndicatorStateChange: (String, Bool) -> Void

    private static let kanaIndexTitles: [String] = ["あ", "か", "さ", "た", "な", "は", "ま", "や", "ら", "わ"]
    private static let allIndexTitles: [String] = kanaIndexTitles
    private static let customIndexWidth: CGFloat = 28
    private static let customIndexVerticalInset: CGFloat = 4
    private static let customIndexFontSize: CGFloat = 12

    func makeCoordinator() -> Coordinator {
        Coordinator(
            entries: entries,
            listHeight: listHeight,
            selectedEntryID: selectedEntryID,
            onDelete: onDelete,
            onSelect: onSelect,
            onIndexIndicatorStateChange: onIndexIndicatorStateChange
        )
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView(frame: .zero)
        containerView.backgroundColor = .clear

        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Coordinator.cellReuseIdentifier)
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.rowHeight = 30
        tableView.separatorStyle = .none
        tableView.sectionIndexColor = .clear
        tableView.sectionIndexBackgroundColor = .clear
        tableView.sectionIndexTrackingBackgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let indexContainerView = UIView(frame: .zero)
        indexContainerView.backgroundColor = .clear
        indexContainerView.translatesAutoresizingMaskIntoConstraints = false
        indexContainerView.isUserInteractionEnabled = true

        let indexStackView = UIStackView(frame: .zero)
        indexStackView.axis = .vertical
        indexStackView.alignment = .fill
        indexStackView.distribution = .fillEqually
        indexStackView.spacing = 0
        indexStackView.translatesAutoresizingMaskIntoConstraints = false

        indexContainerView.addSubview(indexStackView)
        containerView.addSubview(tableView)
        containerView.addSubview(indexContainerView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: containerView.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            indexContainerView.topAnchor.constraint(
                equalTo: tableView.topAnchor,
                constant: Self.customIndexVerticalInset
            ),
            indexContainerView.bottomAnchor.constraint(
                equalTo: tableView.bottomAnchor,
                constant: -Self.customIndexVerticalInset
            ),
            indexContainerView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor, constant: -2),
            indexContainerView.widthAnchor.constraint(equalToConstant: Self.customIndexWidth),

            indexStackView.topAnchor.constraint(equalTo: indexContainerView.topAnchor),
            indexStackView.bottomAnchor.constraint(equalTo: indexContainerView.bottomAnchor),
            indexStackView.leadingAnchor.constraint(equalTo: indexContainerView.leadingAnchor),
            indexStackView.trailingAnchor.constraint(equalTo: indexContainerView.trailingAnchor)
        ])

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCustomIndexTap(_:))
        )
        indexContainerView.addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCustomIndexPan(_:))
        )
        panGesture.maximumNumberOfTouches = 1
        indexContainerView.addGestureRecognizer(panGesture)

        // 標準の左スワイプは行を左へずらして文字が見えなくなる(3597 のショートカット語彙と同じ)ので、
        // 横に払う動きを自前で拾い、文字は動かさずに行の右端へ[削除]を出す
        let deletionRevealPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDeletionRevealPan(_:))
        )
        deletionRevealPan.maximumNumberOfTouches = 1
        deletionRevealPan.cancelsTouchesInView = false
        deletionRevealPan.delegate = context.coordinator
        tableView.addGestureRecognizer(deletionRevealPan)

        context.coordinator.attach(
            tableView: tableView,
            indexContainerView: indexContainerView,
            indexStackView: indexStackView
        )

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let needsReload = context.coordinator.update(
            entries: entries,
            listHeight: listHeight,
            selectedEntryID: selectedEntryID,
            pendingDeletionEntryID: pendingDeletionEntryID,
            onDelete: onDelete,
            onSelect: onSelect,
            onIndexIndicatorStateChange: onIndexIndicatorStateChange
        )

        if needsReload {
            context.coordinator.reloadData()
        } else {
            context.coordinator.refreshCustomIndexPresentation()
        }
    }

    private static func indexTitle(for reading: String) -> String {
        let trimmed = reading.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = trimmed.first else {
            return "あ"
        }

        let firstString = String(first)

        let hiragana = firstString.applyingTransform(.hiraganaToKatakana, reverse: true) ?? firstString

        guard let kana = hiragana.first else {
            return "あ"
        }

        switch kana {
        case "ぁ", "あ", "ぃ", "い", "ぅ", "う", "ぇ", "え", "ぉ", "お", "ゔ":
            return "あ"
        case "か", "が", "き", "ぎ", "く", "ぐ", "け", "げ", "こ", "ご":
            return "か"
        case "さ", "ざ", "し", "じ", "す", "ず", "せ", "ぜ", "そ", "ぞ":
            return "さ"
        case "た", "だ", "ち", "ぢ", "っ", "つ", "づ", "て", "で", "と", "ど":
            return "た"
        case "な", "に", "ぬ", "ね", "の":
            return "な"
        case "は", "ば", "ぱ", "ひ", "び", "ぴ", "ふ", "ぶ", "ぷ", "へ", "べ", "ぺ", "ほ", "ぼ", "ぽ":
            return "は"
        case "ま", "み", "む", "め", "も":
            return "ま"
        case "ゃ", "や", "ゅ", "ゆ", "ょ", "よ":
            return "や"
        case "ら", "り", "る", "れ", "ろ":
            return "ら"
        case "ゎ", "わ", "を", "ん":
            return "わ"
        default:
            return "あ"
        }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
        static let cellReuseIdentifier = "IndexedVocabularyCell"
        static let candidateLabelTag = 1001
        static let readingLabelTag = 1002
        static let deleteButtonTag = 1003
        static let readingBeforeDeleteButtonConstraintID = "readingBeforeDeleteButton"
        static let deleteActionID = UIAction.Identifier("deleteVocabularyEntry")

        private var entries: [VocabularyEntry]
        private var listHeight: CGFloat
        private var selectedEntryID: String?
        private var onDelete: ((VocabularyEntry) -> Void)?
        private var onSelect: ((VocabularyEntry) -> Void)?
        private var onIndexIndicatorStateChange: (String, Bool) -> Void
        private var groupedEntries: [String: [VocabularyEntry]] = [:]
        private var visibleSectionTitles: [String] = []
        private var overlayHideWorkItem: DispatchWorkItem?
        private var currentIndexIndicatorTitle = ""
        private weak var tableView: UITableView?
        private weak var indexContainerView: UIView?
        private weak var indexStackView: UIStackView?
        private var displayedIndexTitles: [String] = []
        private var pendingDeletionEntryID: String?
        private var revealedDeletionEntryID: String?
        private var isRowSwipeActionVisible: Bool {
            revealedDeletionEntryID != nil
        }
        private var entriesStorageIdentity: UInt

        init(
            entries: [VocabularyEntry],
            listHeight: CGFloat,
            selectedEntryID: String?,
            onDelete: ((VocabularyEntry) -> Void)?,
            onSelect: ((VocabularyEntry) -> Void)?,
            onIndexIndicatorStateChange: @escaping (String, Bool) -> Void
        ) {
            self.entries = entries
            self.listHeight = listHeight
            self.selectedEntryID = selectedEntryID
            self.onDelete = onDelete
            self.onSelect = onSelect
            self.onIndexIndicatorStateChange = onIndexIndicatorStateChange
            self.entriesStorageIdentity = Self.storageIdentity(for: entries)
            super.init()
            rebuildSections()
        }

        private static func storageIdentity(for entries: [VocabularyEntry]) -> UInt {
            let baseAddress: UInt = entries.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else {
                    return 0
                }
                return UInt(bitPattern: base)
            }

            return baseAddress ^ UInt(entries.count)
        }

        private static func hasDifferentEntryIDs(
            _ lhs: [VocabularyEntry],
            _ rhs: [VocabularyEntry]
        ) -> Bool {
            guard lhs.count == rhs.count else {
                return true
            }

            for index in lhs.indices {
                if lhs[index].id != rhs[index].id {
                    return true
                }
            }

            return false
        }

        func attach(tableView: UITableView, indexContainerView: UIView, indexStackView: UIStackView) {
            self.tableView = tableView
            self.indexContainerView = indexContainerView
            self.indexStackView = indexStackView
            tableView.reloadData()
            tableView.layoutIfNeeded()
            refreshCustomIndexPresentation()
            schedulePostLayoutCustomIndexRefresh()
        }

        func reloadData() {
            tableView?.reloadData()
            tableView?.layoutIfNeeded()
            refreshCustomIndexPresentation()
            schedulePostLayoutCustomIndexRefresh()
        }

        func refreshCustomIndexPresentation() {
            refreshCustomIndexTitles()
            refreshCustomIndexVisibility()
        }

        private var isCustomIndexInteractionEnabled: Bool {
            guard onDelete != nil else {
                return true
            }

            return !isRowSwipeActionVisible
        }

        private var customIndexLabelColor: UIColor {
            if isCustomIndexInteractionEnabled {
                return .systemBlue
            }

            return UIColor.systemBlue.withAlphaComponent(0.58)
        }

        private func refreshCustomIndexInteractionState() {
            indexContainerView?.isUserInteractionEnabled = isCustomIndexInteractionEnabled
            updateCustomIndexLabelAppearance()
        }

        private func updateCustomIndexLabelAppearance() {
            guard let indexStackView else {
                return
            }

            let color = customIndexLabelColor

            for arrangedSubview in indexStackView.arrangedSubviews {
                guard let label = arrangedSubview as? UILabel else {
                    continue
                }

                if label.textColor != color {
                    label.textColor = color
                }
            }
        }

        private func schedulePostLayoutCustomIndexRefresh() {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.refreshCustomIndexTitles()
                self.refreshCustomIndexVisibility()
            }
        }

        @discardableResult
        func update(
            entries: [VocabularyEntry],
            listHeight: CGFloat,
            selectedEntryID: String?,
            pendingDeletionEntryID: String?,
            onDelete: ((VocabularyEntry) -> Void)?,
            onSelect: ((VocabularyEntry) -> Void)?,
            onIndexIndicatorStateChange: @escaping (String, Bool) -> Void
        ) -> Bool {
            let nextEntriesStorageIdentity = Self.storageIdentity(for: entries)
            let entriesChanged: Bool

            if entriesStorageIdentity == nextEntriesStorageIdentity {
                entriesChanged = false
            } else {
                entriesChanged = Self.hasDifferentEntryIDs(self.entries, entries)
                entriesStorageIdentity = nextEntriesStorageIdentity
            }

            let deleteAvailabilityChanged = (self.onDelete != nil) != (onDelete != nil)
            let selectAvailabilityChanged = (self.onSelect != nil) != (onSelect != nil)
            let selectedEntryChanged = self.selectedEntryID != selectedEntryID
            let listHeightChanged = abs(self.listHeight - listHeight) > 0.5

            self.entries = entries
            self.listHeight = listHeight
            self.selectedEntryID = selectedEntryID
            self.onDelete = onDelete
            self.onSelect = onSelect
            self.onIndexIndicatorStateChange = onIndexIndicatorStateChange

            if entriesChanged {
                rebuildSections()
            }

            let pendingDeletionChanged = self.pendingDeletionEntryID != pendingDeletionEntryID
            if pendingDeletionChanged, pendingDeletionEntryID == nil {
                // ダイアログを閉じたら([キャンセル]でも[削除]でも)[削除]ボタンも引っ込める
                revealedDeletionEntryID = nil
            }
            self.pendingDeletionEntryID = pendingDeletionEntryID
            if onDelete == nil
                || (revealedDeletionEntryID.map { id in !entries.contains { $0.id == id } } ?? false) {
                revealedDeletionEntryID = nil
            }
            // 行が変わったときは表の読み直し(cellForRow)で反映する。読み直す前に見えている行を
            // 引くと、古い行番号で新しい entries を引いてしまう
            if pendingDeletionChanged, !entriesChanged {
                refreshDeletionAppearanceOfVisibleRows(animated: true)
            }

            return entriesChanged
                || deleteAvailabilityChanged
                || selectAvailabilityChanged
                || selectedEntryChanged
                || listHeightChanged
        }

        func refreshCustomIndexVisibility() {
            if visibleSectionTitles.isEmpty {
                hideScrollingIndexOverlayImmediately()
            }

            indexContainerView?.isHidden = displayedIndexTitles.isEmpty || !canScrollInTableView()
            refreshCustomIndexInteractionState()
        }

        private func refreshCustomIndexTitles() {
            guard let indexStackView else {
                return
            }

            let nextTitles: [String] = visibleSectionTitles.count > 1 && canScrollInTableView()
                ? visibleSectionTitles
                : []

            if displayedIndexTitles == nextTitles {
                indexContainerView?.isHidden = nextTitles.isEmpty
                refreshCustomIndexInteractionState()
                return
            }

            displayedIndexTitles = nextTitles

            for arrangedSubview in indexStackView.arrangedSubviews {
                indexStackView.removeArrangedSubview(arrangedSubview)
                arrangedSubview.removeFromSuperview()
            }

            for title in nextTitles {
                let label = UILabel()
                label.text = title
                label.font = UIFont.systemFont(ofSize: IndexedVocabularyList.customIndexFontSize, weight: .semibold)
                label.textColor = customIndexLabelColor
                label.textAlignment = .center
                label.isUserInteractionEnabled = false
                indexStackView.addArrangedSubview(label)
            }

            indexContainerView?.isHidden = nextTitles.isEmpty
            refreshCustomIndexInteractionState()
        }

        private func canScrollInTableView() -> Bool {
            guard listHeight > 1 else {
                return false
            }

            let totalRows = visibleSectionTitles.reduce(0) { partialResult, title in
                partialResult + (groupedEntries[title]?.count ?? 0)
            }
            let rowHeight = tableView?.rowHeight ?? 30
            let resolvedRowHeight = rowHeight > 0 ? rowHeight : 30
            let contentHeight = CGFloat(totalRows) * resolvedRowHeight

            return contentHeight > listHeight + 1
        }

        private func resolveSection(for title: String, at index: Int) -> Int {
            guard !visibleSectionTitles.isEmpty else {
                return 0
            }

            if let exactIndex = visibleSectionTitles.firstIndex(of: title) {
                return exactIndex
            }

            for next in index..<IndexedVocabularyList.allIndexTitles.count {
                let candidate = IndexedVocabularyList.allIndexTitles[next]
                if let resolvedIndex = visibleSectionTitles.firstIndex(of: candidate) {
                    return resolvedIndex
                }
            }

            for previous in stride(from: index, through: 0, by: -1) {
                let candidate = IndexedVocabularyList.allIndexTitles[previous]
                if let resolvedIndex = visibleSectionTitles.firstIndex(of: candidate) {
                    return resolvedIndex
                }
            }

            return 0
        }

        private func rebuildSections() {
            var grouped: [String: [VocabularyEntry]] = [:]

            for indexTitle in IndexedVocabularyList.allIndexTitles {
                grouped[indexTitle] = []
            }

            for entry in entries {
                let indexTitle = IndexedVocabularyList.indexTitle(for: entry.reading)
                grouped[indexTitle, default: []].append(entry)
            }

            groupedEntries = grouped
            visibleSectionTitles = IndexedVocabularyList.allIndexTitles.filter {
                !(groupedEntries[$0]?.isEmpty ?? true)
            }

            refreshCustomIndexVisibility()

            if visibleSectionTitles.isEmpty {
                hideScrollingIndexOverlayImmediately()
            }
        }

        private func currentVisibleSectionTitle(in tableView: UITableView) -> String? {
            let topY = tableView.contentOffset.y + tableView.adjustedContentInset.top + 1
            let probePoint = CGPoint(x: 8, y: max(topY, 1))

            if let indexPath = tableView.indexPathForRow(at: probePoint),
                indexPath.section < visibleSectionTitles.count {
                return visibleSectionTitles[indexPath.section]
            }

            guard let firstVisible = tableView.indexPathsForVisibleRows?.sorted(by: {
                if $0.section == $1.section {
                    return $0.row < $1.row
                }
                return $0.section < $1.section
            }).first,
            firstVisible.section < visibleSectionTitles.count else {
                return nil
            }

            return visibleSectionTitles[firstVisible.section]
        }

        private func showScrollingIndexOverlay(title: String?) {
            guard let title, !title.isEmpty else {
                return
            }

            overlayHideWorkItem?.cancel()
            currentIndexIndicatorTitle = title
            onIndexIndicatorStateChange(title, true)
        }

        private func scheduleHideScrollingIndexOverlay() {
            overlayHideWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else {
                    return
                }

                self.onIndexIndicatorStateChange(self.currentIndexIndicatorTitle, false)
            }

            overlayHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        private func hideScrollingIndexOverlayImmediately() {
            overlayHideWorkItem?.cancel()
            onIndexIndicatorStateChange(currentIndexIndicatorTitle, false)
        }

        private func sectionIndexTitlesForCustomIndex() -> [String] {
            displayedIndexTitles
        }

        private func dismissVisibleSwipeActionImmediately() {
            guard isRowSwipeActionVisible, pendingDeletionEntryID == nil else {
                return
            }

            setRevealedDeletionEntryID(nil, animated: false)
        }

        private func setRevealedDeletionEntryID(_ id: String?, animated: Bool) {
            guard revealedDeletionEntryID != id else {
                return
            }

            revealedDeletionEntryID = id
            refreshDeletionAppearanceOfVisibleRows(animated: animated)
            refreshCustomIndexInteractionState()
        }

        private func refreshDeletionAppearanceOfVisibleRows(animated: Bool) {
            guard let tableView else {
                return
            }

            for cell in tableView.visibleCells {
                guard let indexPath = tableView.indexPath(for: cell) else {
                    continue
                }
                applyDeletionAppearance(to: cell, entry: entry(at: indexPath), animated: animated)
            }
            refreshCustomIndexInteractionState()
        }

        // [削除]が出ている間と確認を待つ間は取り消し線で示す(ショートカット語彙と同じ。3598)
        private func applyDeletionAppearance(to cell: UITableViewCell, entry: VocabularyEntry, animated: Bool) {
            guard let candidateLabel = cell.contentView.viewWithTag(Self.candidateLabelTag) as? UILabel,
                let readingLabel = cell.contentView.viewWithTag(Self.readingLabelTag) as? UILabel,
                let deleteButton = cell.contentView.viewWithTag(Self.deleteButtonTag) as? UIButton else {
                return
            }

            let isRevealed = onDelete != nil && revealedDeletionEntryID == entry.id
            let isMarkedForDeletion = isRevealed || pendingDeletionEntryID == entry.id
            let strikethrough: [NSAttributedString.Key: Any] = isMarkedForDeletion
                ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
                : [:]

            candidateLabel.attributedText = NSAttributedString(string: entry.candidate, attributes: strikethrough)
            candidateLabel.textColor = isMarkedForDeletion ? .secondaryLabel : .label
            readingLabel.attributedText = NSAttributedString(string: entry.reading, attributes: strikethrough)

            cell.contentView.constraints
                .first { $0.identifier == Self.readingBeforeDeleteButtonConstraintID }?
                .isActive = isRevealed

            deleteButton.removeAction(identifiedBy: Self.deleteActionID, for: .touchUpInside)
            deleteButton.addAction(
                UIAction(identifier: Self.deleteActionID) { [weak self] _ in
                    self?.onDelete?(entry)
                },
                for: .touchUpInside
            )

            let changes = {
                deleteButton.alpha = isRevealed ? 1 : 0
                deleteButton.transform = isRevealed ? .identity : CGAffineTransform(translationX: 16, y: 0)
                cell.contentView.layoutIfNeeded()
            }
            deleteButton.isUserInteractionEnabled = isRevealed
            if animated {
                UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut], animations: changes)
            } else {
                changes()
            }
        }

        // 横に払ったときだけ反応する(縦のスクロールは表に任せる)。左で出し、右で引っ込める
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                pan.view === tableView else {
                return true
            }
            guard onDelete != nil else {
                return false
            }

            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleDeletionRevealPan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended,
                let tableView else {
                return
            }

            let translation = gesture.translation(in: tableView)
            guard abs(translation.x) > abs(translation.y) * 1.5 else {
                return
            }

            let location = gesture.location(in: tableView)
            let startPoint = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            guard let indexPath = tableView.indexPathForRow(at: startPoint) else {
                return
            }

            let target = entry(at: indexPath)
            if translation.x < -30 {
                setRevealedDeletionEntryID(target.id, animated: true)
            } else if translation.x > 30, revealedDeletionEntryID == target.id {
                setRevealedDeletionEntryID(nil, animated: true)
            }
        }

        private func customIndexTitle(for locationY: CGFloat, in indexView: UIView) -> String? {
            let titles = sectionIndexTitlesForCustomIndex()

            guard !titles.isEmpty, indexView.bounds.height > 0 else {
                return nil
            }

            let clampedY = min(max(locationY, 0), max(0, indexView.bounds.height - 0.5))
            let slotHeight = indexView.bounds.height / CGFloat(titles.count)

            guard slotHeight > 0 else {
                return nil
            }

            let slot = min(titles.count - 1, max(0, Int(clampedY / slotHeight)))
            return titles[slot]
        }

        private func scrollToCustomIndexTitle(_ title: String, animated: Bool) {
            guard let tableView else {
                return
            }

            let titleIndex = IndexedVocabularyList.allIndexTitles.firstIndex(of: title) ?? 0
            let section = resolveSection(for: title, at: titleIndex)

            guard section < visibleSectionTitles.count else {
                return
            }

            let rowCount = tableView.numberOfRows(inSection: section)
            guard rowCount > 0 else {
                return
            }

            tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: animated)
        }

        @objc func handleCustomIndexTap(_ gesture: UITapGestureRecognizer) {
            guard isCustomIndexInteractionEnabled else {
                dismissVisibleSwipeActionImmediately()
                return
            }

            guard gesture.state == .ended,
                let indexView = gesture.view,
                let title = customIndexTitle(for: gesture.location(in: indexView).y, in: indexView) else {
                return
            }

            scrollToCustomIndexTitle(title, animated: true)
            showScrollingIndexOverlay(title: title)
            scheduleHideScrollingIndexOverlay()
        }

        @objc func handleCustomIndexPan(_ gesture: UIPanGestureRecognizer) {
            guard isCustomIndexInteractionEnabled else {
                dismissVisibleSwipeActionImmediately()
                if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                    scheduleHideScrollingIndexOverlay()
                }
                return
            }

            guard let indexView = gesture.view else {
                return
            }

            switch gesture.state {
            case .began, .changed:
                guard let title = customIndexTitle(for: gesture.location(in: indexView).y, in: indexView) else {
                    return
                }

                scrollToCustomIndexTitle(title, animated: false)
                showScrollingIndexOverlay(title: title)
            case .ended, .cancelled, .failed:
                scheduleHideScrollingIndexOverlay()
            default:
                break
            }
        }

        private func entry(at indexPath: IndexPath) -> VocabularyEntry {
            let sectionTitle = visibleSectionTitles[indexPath.section]
            return groupedEntries[sectionTitle]![indexPath.row]
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            visibleSectionTitles.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            let sectionTitle = visibleSectionTitles[section]
            return groupedEntries[sectionTitle]?.count ?? 0
        }

        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            nil
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            CGFloat.leastNonzeroMagnitude
        }

        func sectionIndexTitles(for tableView: UITableView) -> [String]? {
            nil
        }

        func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
            showScrollingIndexOverlay(title: title)
            scheduleHideScrollingIndexOverlay()
            return resolveSection(for: title, at: index)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? UITableView else {
                return
            }

            dismissVisibleSwipeActionImmediately()

            showScrollingIndexOverlay(title: currentVisibleSectionTitle(in: tableView))
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? UITableView else {
                return
            }

            let isUserInteracting = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            guard isUserInteracting else {
                return
            }

            showScrollingIndexOverlay(title: currentVisibleSectionTitle(in: tableView))
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                scheduleHideScrollingIndexOverlay()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            scheduleHideScrollingIndexOverlay()
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)
            let entry = entry(at: indexPath)

            let candidateLabel: UILabel
            let readingLabel: UILabel

            if let existingCandidateLabel = cell.contentView.viewWithTag(Self.candidateLabelTag) as? UILabel,
                let existingReadingLabel = cell.contentView.viewWithTag(Self.readingLabelTag) as? UILabel {
                candidateLabel = existingCandidateLabel
                readingLabel = existingReadingLabel
            } else {
                candidateLabel = UILabel()
                candidateLabel.tag = Self.candidateLabelTag
                candidateLabel.translatesAutoresizingMaskIntoConstraints = false
                candidateLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
                candidateLabel.textColor = .label
                candidateLabel.textAlignment = .left
                candidateLabel.lineBreakMode = .byTruncatingTail

                readingLabel = UILabel()
                readingLabel.tag = Self.readingLabelTag
                readingLabel.translatesAutoresizingMaskIntoConstraints = false
                readingLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                readingLabel.textColor = .secondaryLabel
                readingLabel.textAlignment = .left
                readingLabel.lineBreakMode = .byTruncatingTail

                // [削除]は左へ払った行だけに出す(ショートカット語彙と同じ赤い丸ボタン)
                var deleteButtonConfiguration = UIButton.Configuration.filled()
                deleteButtonConfiguration.baseBackgroundColor = .systemRed
                deleteButtonConfiguration.baseForegroundColor = .white
                deleteButtonConfiguration.cornerStyle = .capsule
                deleteButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
                deleteButtonConfiguration.attributedTitle = AttributedString(
                    "削除",
                    attributes: AttributeContainer([
                        .font: UIFont.systemFont(
                            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
                            weight: .semibold
                        )
                    ])
                )
                let deleteButton = UIButton(configuration: deleteButtonConfiguration)
                deleteButton.tag = Self.deleteButtonTag
                deleteButton.translatesAutoresizingMaskIntoConstraints = false
                deleteButton.alpha = 0
                deleteButton.isUserInteractionEnabled = false

                cell.contentView.addSubview(candidateLabel)
                cell.contentView.addSubview(readingLabel)
                cell.contentView.addSubview(deleteButton)

                let readingBeforeDeleteButton = readingLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: deleteButton.leadingAnchor,
                    constant: -6
                )
                readingBeforeDeleteButton.identifier = Self.readingBeforeDeleteButtonConstraintID

                NSLayoutConstraint.activate([
                    candidateLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 10),
                    candidateLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.centerXAnchor, constant: -10),
                    candidateLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),

                    readingLabel.leadingAnchor.constraint(equalTo: cell.contentView.centerXAnchor, constant: -2),
                    readingLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -10),
                    readingLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),

                    // 右端の索引(あかさたな)と重ならない位置に出す
                    deleteButton.trailingAnchor.constraint(
                        equalTo: cell.contentView.trailingAnchor,
                        constant: -(IndexedVocabularyList.customIndexWidth + 6)
                    ),
                    deleteButton.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
                ])
            }

            let isSelected = entry.id == selectedEntryID

            cell.textLabel?.text = nil
            cell.backgroundColor = isSelected
                ? UIColor.systemBlue.withAlphaComponent(0.18)
                : UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.95)
            cell.selectionStyle = .none
            applyDeletionAppearance(to: cell, entry: entry, animated: false)

            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            // [削除]を出している間のタップは、ボタンを引っ込めるだけ
            if isRowSwipeActionVisible {
                setRevealedDeletionEntryID(nil, animated: true)
                return
            }
            onSelect?(entry(at: indexPath))
        }
    }
}
