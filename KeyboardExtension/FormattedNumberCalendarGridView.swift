import SwiftUI

// 書式化数値モード用の自前カレンダー(常時表示・コンパクト)。閏年・日数・曜日は
// グレゴリオ暦の Calendar で算出する。週開始(日/月)と曜日表記(日/英/仏)は設定で切替。
// フォントはカレンダー向きの Avenir Next。
struct FormattedNumberCalendarGridView: View {
    // ナビ(年月と前後移動)の配置。縦画面はグリッド上のヘッダー、横画面は縦の余裕が乏しいので
    // グリッドの右に縦積み(月名/年/前後)にして縦を節約する。
    enum NavigationPlacement {
        case top
        case trailing
    }

    @Binding var selectedDate: Date
    let weekStartsMonday: Bool
    let language: DateFormatCatalog.CalendarWeekdayLanguage
    // 日曜列の色(nil=他曜日と同じ)。
    let sundayColor: Color?
    let navigationPlacement: NavigationPlacement
    private let cellHeight: CGFloat
    private let columnSpacing: CGFloat

    @State private var monthAnchor: Date
    // 押したままなぞって選択するための、各日セルの矩形(グリッド座標系)。
    @State private var dayCellFrames: [Int: CGRect] = [:]
    @State private var lastDraggedDay: Int?
    private let gridCoordinateSpace = "formattedNumberCalendarDaysGrid"

    init(
        selectedDate: Binding<Date>,
        weekStartsMonday: Bool,
        language: DateFormatCatalog.CalendarWeekdayLanguage,
        sundayColor: Color?,
        navigationPlacement: NavigationPlacement = .top,
        cellHeight: CGFloat = 22,
        columnSpacing: CGFloat = 2
    ) {
        _selectedDate = selectedDate
        self.weekStartsMonday = weekStartsMonday
        self.language = language
        self.sundayColor = sundayColor
        self.navigationPlacement = navigationPlacement
        self.cellHeight = cellHeight
        self.columnSpacing = columnSpacing
        _monthAnchor = State(initialValue: selectedDate.wrappedValue)
    }

    // 週開始に合わせた日曜の列インデックス(0起点)。
    private var sundayColumnIndex: Int {
        weekStartsMonday ? 6 : 0
    }

    // その日が日曜か(weekday 1=日曜)。
    private func isSunday(_ day: Int) -> Bool {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        return calendar.component(.weekday, from: date) == 1
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = weekStartsMonday ? 2 : 1
        return calendar
    }

    private var year: Int {
        calendar.component(.year, from: monthAnchor)
    }

    private var month: Int {
        calendar.component(.month, from: monthAnchor)
    }

    private var firstOfMonth: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? monthAnchor
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
    }

    // 月初の前に置く空白セル数(週開始設定を考慮)。
    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    // 週開始に合わせて並べ替えた曜日ラベル。
    private var orderedWeekdayLabels: [String] {
        let base = DateFormatCatalog.calendarWeekdayLabels(language)
        guard weekStartsMonday else {
            return base
        }
        return Array(base[1...]) + [base[0]]
    }

    private func calendarFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }

    private func isSelected(_ day: Int) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        return components.year == year && components.month == month && components.day == day
    }

    private func selectDay(_ day: Int) {
        if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
            selectedDate = date
        }
    }

    private func changeMonth(_ delta: Int) {
        if let date = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = date
        }
    }

    // 週数(4/5/6)で高さ・位置が変わらないよう常に6週=42セルを固定セル高さで描画する
    // (空セルも明示的に cellHeight を確保するので6行分の高さが常に一定。位置がずれない)。
    private let totalCells = 42
    private let rowSpacing: CGFloat = 2
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 7)
    }

    var body: some View {
        switch navigationPlacement {
        case .top:
            VStack(spacing: 3) {
                header
                weekdayHeaderRow
                daysGrid
            }
        case .trailing:
            // 横画面: ヘッダーを上に置かず、ナビを右に縦積みして縦を節約。
            // グリッド側を maxWidth:.infinity で幅いっぱいに広げる(縦画面はヘッダーの Spacer が
            // 幅を張るが、横画面はヘッダーが無いため明示しないとグリッドが痩せて日付が詰まる)。
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 3) {
                    weekdayHeaderRow
                    daysGrid
                }
                .frame(maxWidth: .infinity)
                trailingNavigationColumn
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: { changeMonth(-1) }) {
                Image(systemName: "chevron.left")
                    .font(calendarFont(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(DateFormatCatalog.calendarMonthTitle(language, year: year, month: month))
                .font(calendarFont(size: 15, weight: .semibold))
                .foregroundColor(KeyboardThemePalette.keyLabel)

            Spacer()

            Button(action: { changeMonth(1) }) {
                Image(systemName: "chevron.right")
                    .font(calendarFont(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(Color.accentColor)
        .padding(.horizontal, 6)
    }

    // 横画面用: グリッド右に「前(∧)/月名/年/次(∨)」を縦積み。縦並びなので上下向きの矢印にする。
    // 月名/年は上下矢印の中間(縦センター)に置く(Spacer で挟む)。列はグリッド高さいっぱいに伸ばす。
    private var trailingNavigationColumn: some View {
        // 上下矢印を年月に近づけた密な塊にし、上下の Spacer で塊ごと縦センターに置く。
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 13) {
                Button(action: { changeMonth(-1) }) {
                    Image(systemName: "chevron.up")
                        .font(calendarFont(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)

                VStack(spacing: 1) {
                    Text(DateFormatCatalog.calendarMonthName(language, month: month))
                        .font(calendarFont(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(String(year))
                        .font(calendarFont(size: 13))
                        .monospacedDigit()
                }
                .foregroundColor(KeyboardThemePalette.keyLabel)

                Button(action: { changeMonth(1) }) {
                    Image(systemName: "chevron.down")
                        .font(calendarFont(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .foregroundColor(Color.accentColor)
        .frame(width: 66)
        .frame(maxHeight: .infinity)
    }

    private var weekdayHeaderRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(orderedWeekdayLabels.enumerated()), id: \.offset) { index, label in
                let isSundayColumn = index == sundayColumnIndex
                Text(label)
                    .font(calendarFont(size: 10))
                    .foregroundColor(
                        (isSundayColumn ? sundayColor : nil) ?? KeyboardThemePalette.keyLabel.opacity(0.5)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    // 末尾を空セルで 42(6週)まで埋め、月ごとに高さ・位置がずれないようにする。
    private var trailingBlanks: Int {
        max(0, totalCells - leadingBlanks - daysInMonth)
    }

    private var daysGrid: some View {
        LazyVGrid(columns: columns, spacing: rowSpacing) {
            ForEach(0..<leadingBlanks, id: \.self) { index in
                blankCell.id("lead-\(index)")
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day)
            }
            ForEach(0..<trailingBlanks, id: \.self) { index in
                blankCell.id("trail-\(index)")
            }
        }
        .coordinateSpace(name: gridCoordinateSpace)
        .onPreferenceChange(DayCellFramePreferenceKey.self) { frames in
            dayCellFrames = frames
        }
        // iPhone 標準カレンダー風: 押したまま指を動かすと、指の下の日付が連続選択される。
        // minimumDistance:0 なので単純タップ(触れた瞬間)でも選択される。
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(gridCoordinateSpace))
                .onChanged { value in selectDay(atGridLocation: value.location) }
                .onEnded { _ in lastDraggedDay = nil }
        )
    }

    // グリッド座標系の指位置から、その位置にある日を選ぶ(なぞり中の連続選択用)。
    private func selectDay(atGridLocation location: CGPoint) {
        guard let day = dayCellFrames.first(where: { $0.value.contains(location) })?.key else {
            return
        }
        guard day != lastDraggedDay else {
            return
        }
        lastDraggedDay = day
        selectDay(day)
    }

    // 空セルも明示的に cellHeight を確保して6行分の高さを一定に保つ(潰れさせない)。
    private var blankCell: some View {
        Color.clear.frame(height: cellHeight)
    }

    // 選択はグリッド全体の DragGesture で行うため、各日セルは視覚+矩形記録のみ(Button にしない)。
    private func dayCell(_ day: Int) -> some View {
        let selected = isSelected(day)
        let dayColor: Color = selected
            ? Color.white
            : ((isSunday(day) ? sundayColor : nil) ?? KeyboardThemePalette.keyLabel)
        return Text("\(day)")
            .font(calendarFont(size: 15, weight: selected ? .bold : .regular))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundColor(dayColor)
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(
                Circle()
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: DayCellFramePreferenceKey.self,
                        value: [day: geometry.frame(in: .named(gridCoordinateSpace))]
                    )
                }
            )
            .accessibilityLabel("\(day)")
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// 各日セルの矩形(グリッド座標系)を集約するための PreferenceKey。
private struct DayCellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
