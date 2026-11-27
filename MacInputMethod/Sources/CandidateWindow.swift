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

    /// 番号の列の幅。1〜9 のうち一番幅の広い数字に合わせる(数字ごとに幅が違う書体でも、候補の頭がそろう)
    private static let numberColumnWidth: CGFloat = {
        let widths = (1...InputSession.candidatePageSize).map { number in
            ("\(number)" as NSString).size(withAttributes: [.font: font]).width
        }
        // ラベルは文字の左右に 2 ポイントずつ余白を持つ。その分を足さないと数字が欠ける
        return ceil(widths.max() ?? 0) + 4
    }()
    /// 番号の列と候補の間
    private static let numberGap: CGFloat = 4

    /// 1 行: 番号の列(幅は一定、数字は列の中央)+ 候補(頭の位置は全部の行で同じ)
    private static func makeRow(number: Int, text: String, isSelected: Bool) -> NSView {
        let textColor: NSColor = isSelected ? .selectedMenuItemTextColor : .labelColor

        let numberLabel = NSTextField(labelWithString: "\(number)")
        numberLabel.font = font
        numberLabel.textColor = textColor
        numberLabel.alignment = .center
        numberLabel.translatesAutoresizingMaskIntoConstraints = false

        let candidateLabel = NSTextField(labelWithString: text)
        candidateLabel.font = font
        candidateLabel.textColor = textColor
        candidateLabel.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(numberLabel)
        row.addSubview(candidateLabel)
        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: horizontalPadding),
            numberLabel.widthAnchor.constraint(equalToConstant: numberColumnWidth),
            numberLabel.firstBaselineAnchor.constraint(equalTo: candidateLabel.firstBaselineAnchor),
            candidateLabel.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: numberGap),
            candidateLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -horizontalPadding),
            candidateLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: rowPadding),
            candidateLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -rowPadding),
        ])
        return row
    }
}
