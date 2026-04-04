import AppKit
import SwiftUI

// MARK: - Formatting

enum CalendarDatePickerFormatting {
    static let rowLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = .autoupdatingCurrent
        return f
    }()

    /// Shared for calendar grid cell accessibility (42 cells); do not allocate per call.
    static let accessibilityFullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        f.locale = .autoupdatingCurrent
        return f
    }()
}

// MARK: - Shared day math (date-only, startOfDay)

enum CalendarDatePickerDayMath {
    static func todayStart(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: Date())
    }

    static func monthYearKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    static func isSelectable(_ dayStart: Date, minDate: Date?, maxDate: Date?, calendar: Calendar = .current) -> Bool {
        let d = calendar.startOfDay(for: dayStart)
        if let minDate, d < calendar.startOfDay(for: minDate) { return false }
        if let maxDate, d > calendar.startOfDay(for: maxDate) { return false }
        return true
    }

    static func firstDayOfMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let comps = calendar.dateComponents([.year, .month], from: start)
        return calendar.date(from: comps) ?? start
    }
}

// MARK: - Month grid

private enum CalendarGridConstants {
    /// Full row height for hit testing (entire cell is clickable, not just the digit).
    static let dayCellHeight: CGFloat = 40
    /// Visual ring/dot behind the day number.
    static let dayMarkerDiameter: CGFloat = 32
    static let gridRowSpacing: CGFloat = 6
    static let gridColumnSpacing: CGFloat = 4
    /// Fixed row count so month navigation controls never shift vertically.
    static let weekRowCount = 6
    static let gridBodyHeight: CGFloat =
        CGFloat(weekRowCount) * dayCellHeight + CGFloat(weekRowCount - 1) * gridRowSpacing

    /// Wider than the glyph so prev/next month are easy to hit (macOS pointer).
    static let monthStepHitWidth: CGFloat = 48
    static let monthStepHitHeight: CGFloat = 36
    /// Same semantic color AppKit uses for text on selected controls; contrasts with accent fills.
    static let selectedDayNumberForegroundColor = Color(nsColor: .selectedMenuItemTextColor)
}

/// Date-only calendar: month navigation, weekday grid, and trailing/leading days from adjacent months.
struct CalendarGridDatePicker: View {
    @Binding var selectedDate: Date
    @Binding var monthAnchor: Date

    /// Snapshot at construction; not reactive if a parent swaps `Calendar` without replacing this view (use `.id` / new identity when the calendar must change).
    let calendar: Calendar
    /// Derived once from `calendar` (`firstWeekday` + locale symbols); not recomputed every `body`.
    private let weekdaySymbols: [String]
    var minDate: Date? = nil
    var maxDate: Date? = nil

    init(
        selectedDate: Binding<Date>,
        monthAnchor: Binding<Date>,
        calendar: Calendar = .current,
        minDate: Date? = nil,
        maxDate: Date? = nil
    ) {
        _selectedDate = selectedDate
        _monthAnchor = monthAnchor
        self.calendar = calendar
        weekdaySymbols = Self.weekdaySymbolsOrdered(for: calendar)
        self.minDate = minDate
        self.maxDate = maxDate
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var monthSlideDirection: MonthSlideDirection = .forward

    private enum MonthSlideDirection {
        /// Later month: new grid enters from the right, old leaves to the left.
        case forward
        /// Earlier month: new grid enters from the left, old leaves to the right.
        case backward
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.locale = .autoupdatingCurrent
        return f
    }()

    private static func weekdaySymbolsOrdered(for calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday
        return (0..<7).map { i in
            let idx = (first - 1 + i) % 7
            return symbols[idx]
        }
    }

    /// Always 6×7 cells: includes grayed days from previous/next month; tapping them selects the day and moves the visible month.
    private var gridCells: [GridCell] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }
        let monthStart = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let padding = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -padding, to: monthStart) else { return [] }
        let anchorStart = calendar.startOfDay(for: gridStart)

        var cells: [GridCell] = []
        cells.reserveCapacity(42)
        for i in 0..<(7 * CalendarGridConstants.weekRowCount) {
            guard let raw = calendar.date(byAdding: .day, value: i, to: anchorStart) else { continue }
            let dayStart = calendar.startOfDay(for: raw)
            let outside = !calendar.isDate(dayStart, equalTo: monthAnchor, toGranularity: .month)
            let dayNumber = calendar.component(.day, from: dayStart)
            cells.append(.day(number: dayNumber, start: dayStart, outsideMonth: outside))
        }
        return cells
    }

    private enum GridCell: Identifiable {
        case day(number: Int, start: Date, outsideMonth: Bool)

        var id: String {
            switch self {
            case .day(_, let start, _):
                return "day-\(start.timeIntervalSinceReferenceDate)"
            }
        }
    }

    var body: some View {
        let todayStart = CalendarDatePickerDayMath.todayStart(calendar: calendar)
        return VStack(alignment: .leading, spacing: 14) {
            monthHeader
            weekdayHeaderRow
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: CalendarGridConstants.gridColumnSpacing), count: 7),
                spacing: CalendarGridConstants.gridRowSpacing
            ) {
                ForEach(gridCells) { cell in
                    switch cell {
                    case .day(let number, let dayStart, let outsideMonth):
                        dayCell(
                            number: number,
                            dayStart: dayStart,
                            outsideMonth: outsideMonth,
                            todayStart: todayStart
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CalendarGridConstants.gridBodyHeight)
            .clipped()
            .id(CalendarDatePickerDayMath.monthYearKey(for: monthAnchor, calendar: calendar))
            .transition(monthGridTransition(for: monthSlideDirection))
        }
    }

    private func monthGridTransition(for direction: MonthSlideDirection) -> AnyTransition {
        switch direction {
        case .forward:
            .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .backward:
            .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    private var monthHeader: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 10) {
                monthStepButton(delta: -1, systemName: "chevron.left", accessibilityLabel: "Previous month")
                Text(Self.monthYearFormatter.string(from: monthAnchor))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(minWidth: 120)
                    .animation(headerTitleAnimation, value: CalendarDatePickerDayMath.monthYearKey(for: monthAnchor, calendar: calendar))
                    .accessibilityIdentifier("calendar-visible-month")
                monthStepButton(delta: 1, systemName: "chevron.right", accessibilityLabel: "Next month")
            }
            Spacer(minLength: 0)
        }
        .frame(height: CalendarGridConstants.monthStepHitHeight)
    }

    private func monthStepButton(delta: Int, systemName: String, accessibilityLabel: String) -> some View {
        Button {
            shiftMonth(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(
                    width: CalendarGridConstants.monthStepHitWidth,
                    height: CalendarGridConstants.monthStepHitHeight,
                    alignment: .center
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .help(accessibilityLabel)
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(
        number: Int,
        dayStart: Date,
        outsideMonth: Bool,
        todayStart: Date
    ) -> some View {
        let selected = calendar.isDate(dayStart, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(dayStart, inSameDayAs: todayStart)
        let enabled = CalendarDatePickerDayMath.isSelectable(dayStart, minDate: minDate, maxDate: maxDate, calendar: calendar)

        let baseColor: Color = {
            if selected { return CalendarGridConstants.selectedDayNumberForegroundColor }
            if !enabled { return Color.primary.opacity(0.28) }
            if outsideMonth { return Color.secondary }
            return Color.primary
        }()

        let marker = CalendarGridConstants.dayMarkerDiameter

        return Button {
            applySelection(dayStart)
        } label: {
            ZStack {
                if selected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: marker, height: marker)
                } else if isToday {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                        .frame(width: marker, height: marker)
                }
                Text("\(number)")
                    .font(.system(size: 13, weight: selected ? .semibold : (outsideMonth ? .regular : .medium)))
                    .foregroundStyle(baseColor)
            }
            .frame(maxWidth: .infinity, minHeight: CalendarGridConstants.dayCellHeight, maxHeight: CalendarGridConstants.dayCellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(accessibilityDayLabel(for: dayStart, outsideMonth: outsideMonth)))
    }

    private func accessibilityDayLabel(for dayStart: Date, outsideMonth: Bool) -> String {
        let base = CalendarDatePickerFormatting.accessibilityFullDateFormatter.string(from: dayStart)
        if outsideMonth {
            return "\(base). Selects this day and moves the calendar to this month."
        }
        return base
    }

    private var headerTitleAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    /// Matches `runCalendarTransition` so accessibility announcements align with the visible slide, not the frame the animation starts.
    private static let monthGridTransitionAnimationDuration: TimeInterval = 0.28

    private func runCalendarTransition(_ updates: @escaping () -> Void) {
        if accessibilityReduceMotion {
            updates()
        } else {
            withAnimation(.easeInOut(duration: Self.monthGridTransitionAnimationDuration), updates)
        }
    }

    /// Selection ring / label when staying in the same visible month (shorter than full grid transition).
    private func runSameMonthSelectionAnimation(_ updates: @escaping () -> Void) {
        if accessibilityReduceMotion {
            updates()
        } else {
            withAnimation(.easeInOut(duration: 0.2), updates)
        }
    }

    private static func announceVisibleMonth(_ monthStart: Date) {
        let message = Self.monthYearFormatter.string(from: monthStart)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: message]
        )
    }

    /// After `runCalendarTransition`, VoiceOver should describe the month once the slide has finished (Reduce Motion: immediate).
    private func scheduleAnnounceVisibleMonthAfterGridTransition(_ monthStart: Date) {
        if accessibilityReduceMotion {
            Self.announceVisibleMonth(monthStart)
        } else {
            let delay = Self.monthGridTransitionAnimationDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.announceVisibleMonth(monthStart)
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let raw = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        let newAnchor = CalendarDatePickerDayMath.firstDayOfMonth(containing: raw, calendar: calendar)
        monthSlideDirection = delta > 0 ? .forward : .backward
        runCalendarTransition {
            monthAnchor = newAnchor
        }
        scheduleAnnounceVisibleMonthAfterGridTransition(newAnchor)
    }

    private func applySelection(_ dayStart: Date) {
        let normalized = calendar.startOfDay(for: dayStart)
        let newMonthStart = CalendarDatePickerDayMath.firstDayOfMonth(containing: normalized, calendar: calendar)
        let monthChanged = !calendar.isDate(monthAnchor, equalTo: newMonthStart, toGranularity: .month)

        if monthChanged {
            let previousMonthStart = monthAnchor
            monthSlideDirection = newMonthStart > previousMonthStart ? .forward : .backward
            runCalendarTransition {
                selectedDate = normalized
                monthAnchor = newMonthStart
            }
            scheduleAnnounceVisibleMonthAfterGridTransition(newMonthStart)
        } else {
            runSameMonthSelectionAnimation {
                selectedDate = normalized
                monthAnchor = newMonthStart
            }
        }
    }
}

// MARK: - Sheet wrapper (modal confirm)

/// Modal date picker; normalization and the grid share one `calendar` (defaults to `Calendar.current`).
struct CalendarDatePickerSheet: View {
    let calendar: Calendar
    var minDate: Date? = nil
    var maxDate: Date? = nil
    var doneButtonTitle: String = "Done"
    let onDone: (Date) -> Void
    let onCancel: () -> Void

    @State private var workingDate: Date
    @State private var monthAnchor: Date

    init(
        initialDate: Date,
        calendar: Calendar = .current,
        minDate: Date? = nil,
        maxDate: Date? = nil,
        doneButtonTitle: String = "Done",
        onDone: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.calendar = calendar
        self.minDate = minDate
        self.maxDate = maxDate
        self.doneButtonTitle = doneButtonTitle
        self.onDone = onDone
        self.onCancel = onCancel
        let start = calendar.startOfDay(for: initialDate)
        _workingDate = State(initialValue: start)
        _monthAnchor = State(initialValue: CalendarDatePickerDayMath.firstDayOfMonth(containing: start, calendar: calendar))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(doneButtonTitle) {
                    onDone(workingDate)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            CalendarGridDatePicker(
                selectedDate: $workingDate,
                monthAnchor: $monthAnchor,
                calendar: calendar,
                minDate: minDate,
                maxDate: maxDate
            )
            .padding(16)
        }
        .frame(minWidth: 300, idealWidth: 320, minHeight: 400)
    }
}

// MARK: - Inline row → sheet (forms)

struct SelectableCalendarDateRow: View {
    let title: String
    @Binding var date: Date
    var calendar: Calendar = .current
    var minDate: Date? = nil
    var maxDate: Date? = nil

    @State private var showSheet = false

    var body: some View {
        let normalizedDate = calendar.startOfDay(for: date)
        return LabeledContent(title) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    showSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Text(CalendarDatePickerFormatting.rowLabelFormatter.string(from: date))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 6) {
                    dayStepTextButton(delta: -1, title: "-1 day", normalizedDate: normalizedDate)
                    dayStepTextButton(delta: 1, title: "+1 day", normalizedDate: normalizedDate)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showSheet) {
            CalendarDatePickerSheet(
                initialDate: date,
                calendar: calendar,
                minDate: minDate,
                maxDate: maxDate,
                onDone: { newDate in
                    date = calendar.startOfDay(for: newDate)
                    showSheet = false
                },
                onCancel: { showSheet = false }
            )
        }
    }

    private func dayStepTextButton(delta: Int, title: String, normalizedDate: Date) -> some View {
        let steppedDate = calendar.date(byAdding: .day, value: delta, to: normalizedDate)
        let enabled = steppedDate.map {
            CalendarDatePickerDayMath.isSelectable($0, minDate: minDate, maxDate: maxDate, calendar: calendar)
        } ?? false

        return Button {
            guard let steppedDate else { return }
            date = calendar.startOfDay(for: steppedDate)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.38))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(enabled ? 0.06 : 0.03))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(enabled ? 0.14 : 0.07), lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(dayStepAccessibilityHint(delta: delta, enabled: enabled)))
        .help(delta < 0 ? "Previous day" : "Next day")
    }

    private func dayStepAccessibilityHint(delta: Int, enabled: Bool) -> String {
        let action = delta < 0
            ? "Moves the selected date back by one day."
            : "Moves the selected date forward by one day."
        if !enabled {
            return "\(action) Currently unavailable because that day is outside the allowed range."
        }
        return action
    }
}
