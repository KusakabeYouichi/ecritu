import AppKit
import EcrituInput

/// 自前の候補ウインドウ。InputSession.candidatePageSize 件ごとのページを番号つきで出し、選択行を強調する
final class CandidateWindow {
    private static let font = NSFont.systemFont(ofSize: 15)
    private static let rowPadding: CGFloat = 4
    private static let horizontalPadding: CGFloat = 8

    private let panel: NSPanel
    private let stack: NSStackView

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        panel.contentView = stack
    }

    /// 候補を出す。anchor は未確定の行の矩形(スクリーン座標)。その下に出し、下に入りきらなければ上に出す
    func show(_ list: CandidateList, below anchor: NSRect) {
        let pageSize = InputSession.candidatePageSize
        let pageStart = (list.selectedIndex / pageSize) * pageSize
        let pageEnd = min(pageStart + pageSize, list.items.count)

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for index in pageStart..<pageEnd {
            let row = Self.makeRow(
                number: index - pageStart + 1,
                text: list.items[index],
                isSelected: index == list.selectedIndex
            )
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let size = stack.fittingSize
        // 行がある画面の、メニューバーと Dock を除いた範囲に収める
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let origin: NSPoint
        if let visibleFrame = screen?.visibleFrame {
            origin = CandidatePlacement.origin(size: size, anchor: anchor, visibleFrame: visibleFrame)
        } else {
            origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }

    private static func makeRow(number: Int, text: String, isSelected: Bool) -> NSView {
        let label = NSTextField(labelWithString: "\(number)  \(text)")
        label.font = font
        label.textColor = isSelected ? .selectedMenuItemTextColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: rowPadding),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -rowPadding),
        ])
        return row
    }
}
