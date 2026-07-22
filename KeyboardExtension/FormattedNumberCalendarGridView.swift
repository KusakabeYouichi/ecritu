import SwiftUI

// 書式化数値モード用の自前カレンダー(常時表示・コンパクト)。閏年・日数・曜日は
// グレゴリオ暦の Calendar で算出する。週開始(日/月)と曜日表記(日/英/仏)は設定で切替。
// フォントはカレンダー向きの Avenir Next。
struct FormattedNumberCalendarGridView: View {
    @Binding var selectedDate: Date
    let weekStartsMonday: Bool
    let language: DateFormatCatalog.CalendarWeekdayLanguage

    @State private var monthAnchor: Date

    init(
        selectedDate: Binding<Date>,
        weekStartsMonday: Bool,
        language: DateFormatCatalog.CalendarWeekdayLanguage
    ) {
        _selectedDate = selectedDate
        self.weekStartsMonday = weekStartsMonday
        self.language = language
        _monthAnchor = State(initialValue: selectedDate.wrappedValue)
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 3) {
            header
            weekdayHeaderRow
            daysGrid
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

    private var weekdayHeaderRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(orderedWeekdayLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(calendarFont(size: 10))
                    .foregroundColor(KeyboardThemePalette.keyLabel.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var daysGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<leadingBlanks, id: \.self) { index in
                Color.clear
                    .frame(height: 1)
                    .id("blank-\(index)")
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let selected = isSelected(day)
        return Button(action: { selectDay(day) }) {
            Text("\(day)")
                .font(calendarFont(size: 15, weight: selected ? .bold : .regular))
                .monospacedDigit()
                .foregroundColor(selected ? Color.white : KeyboardThemePalette.keyLabel)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    Circle()
                        .fill(selected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
