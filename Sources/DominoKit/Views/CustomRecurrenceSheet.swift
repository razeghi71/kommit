import SwiftUI

// MARK: - Custom Recurrence Sheet (Google Calendar-style)

enum RecurrenceEndMode: Hashable {
    case never
    case onDate
    case afterCount
}

struct CustomRecurrenceSheet: View {
    let initial: Recurrence?
    let eventDate: Date
    let onSave: (Recurrence) -> Void
    let onCancel: () -> Void

    @State private var frequency: RecurrenceFrequency = .weekly
    @State private var interval: Int = 1
    @State private var selectedWeekdays: Set<Weekday> = []
    @State private var monthDay: Int = 1
    @State private var monthDayMode: MonthDayMode = .dayOfMonth
    @State private var nthOccurrence: Int = 1
    @State private var nthWeekday: Weekday = .monday
    @State private var yearMonth: Int = 1
    @State private var yearDay: Int = 1
    @State private var endMode: RecurrenceEndMode = .never
    @State private var endDate: Date = Date().addingTimeInterval(90 * 24 * 3600)
    @State private var endCount: Int = 13
    @State private var recurrenceBaseline: Recurrence?

    private enum MonthDayMode: String, CaseIterable {
        case dayOfMonth
        case weekdayOfMonth
    }

    private var hasUnsavedCustomRecurrenceDraft: Bool {
        guard let recurrenceBaseline else { return false }
        return buildRecurrence() != recurrenceBaseline
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Recurrence")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") { cancelCustomRecurrence() }
                    .buttonStyle(.borderless)
                Button("Done") { onSave(buildRecurrence()) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FieldGroup("Repeat") {
                        repeatEveryRow

                        if frequency == .weekly {
                            weekdaySelector
                        }

                        if frequency == .monthly {
                            monthlySelector
                        }

                        if frequency == .yearly {
                            yearlySelector
                        }
                    }

                    FieldGroup("Ends") {
                        endsContent
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 440)
        .interactiveDismissDisabled(hasUnsavedCustomRecurrenceDraft)
        .onAppear { loadInitial() }
    }

    private func cancelCustomRecurrence() {
        guard hasUnsavedCustomRecurrenceDraft else {
            onCancel()
            return
        }
        if DominoViewModel.showDiscardConfirmation(
            messageText: "Discard changes?",
            informativeText: "Your custom recurrence settings will be lost."
        ) {
            onCancel()
        }
    }

    private var repeatEveryRow: some View {
        LabeledContent("Repeat every") {
            HStack(spacing: 6) {
                Stepper("\(interval)", value: $interval, in: 1...999)
                    .frame(width: 100)
                Picker("", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { f in
                        Text(interval == 1 ? f.displayName.lowercased() : "\(f.displayName.lowercased())s").tag(f)
                    }
                }
                .frame(width: 100)
            }
        }
    }

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repeat on")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Button {
                        if selectedWeekdays.contains(day) && selectedWeekdays.count > 1 {
                            selectedWeekdays.remove(day)
                        } else {
                            selectedWeekdays.insert(day)
                        }
                    } label: {
                        Text(String(day.shortName.prefix(1)))
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 32, height: 32)
                            .background {
                                Circle()
                                    .fill(selectedWeekdays.contains(day) ? Color.accentColor : Color.primary.opacity(0.06))
                            }
                            .foregroundStyle(selectedWeekdays.contains(day) ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var monthlySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $monthDayMode) {
                Text("Day of month").tag(MonthDayMode.dayOfMonth)
                Text("Nth weekday").tag(MonthDayMode.weekdayOfMonth)
            }
            .pickerStyle(.segmented)

            switch monthDayMode {
            case .dayOfMonth:
                LabeledContent("Day") {
                    Stepper("\(monthDay)", value: $monthDay, in: 1...31)
                        .frame(width: 100)
                }
            case .weekdayOfMonth:
                HStack(spacing: 8) {
                    Picker("", selection: $nthOccurrence) {
                        Text("First").tag(1)
                        Text("Second").tag(2)
                        Text("Third").tag(3)
                        Text("Fourth").tag(4)
                        Text("Last").tag(-1)
                    }
                    .frame(width: 100)
                    Picker("", selection: $nthWeekday) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Text(day.shortName).tag(day)
                        }
                    }
                }
            }
        }
    }

    private var yearlySelector: some View {
        HStack(spacing: 8) {
            Picker("Month", selection: $yearMonth) {
                let formatter = DateFormatter()
                ForEach(1...12, id: \.self) { m in
                    Text(formatter.monthSymbols[m - 1]).tag(m)
                }
            }
            .frame(width: 140)
            LabeledContent("Day") {
                Stepper("\(yearDay)", value: $yearDay, in: 1...31)
                    .frame(width: 100)
            }
        }
    }

    private var endsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $endMode) {
                Text("Never").tag(RecurrenceEndMode.never)
                Text("On date").tag(RecurrenceEndMode.onDate)
                Text("After").tag(RecurrenceEndMode.afterCount)
            }
            .pickerStyle(.radioGroup)

            switch endMode {
            case .never:
                EmptyView()
            case .onDate:
                DatePicker("", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            case .afterCount:
                HStack(spacing: 4) {
                    Stepper("\(endCount)", value: $endCount, in: 1...999)
                        .frame(width: 100)
                    Text("occurrences")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func buildRecurrence() -> Recurrence {
        let end: RecurrenceEnd
        switch endMode {
        case .never: end = .never
        case .onDate: end = .until(endDate)
        case .afterCount: end = .count(endCount)
        }

        switch frequency {
        case .daily:
            return Recurrence(frequency: .daily, interval: interval, end: end)
        case .weekly:
            let days = selectedWeekdays.isEmpty ? [Weekday.monday] : Array(selectedWeekdays).sorted()
            return Recurrence(frequency: .weekly, interval: interval, byWeekday: days, end: end)
        case .monthly:
            switch monthDayMode {
            case .dayOfMonth:
                return Recurrence(frequency: .monthly, interval: interval, byMonthDay: [monthDay], end: end)
            case .weekdayOfMonth:
                return Recurrence(frequency: .monthly, interval: interval, byWeekday: [nthWeekday], byMonthDay: [nthOccurrence], end: end)
            }
        case .yearly:
            return Recurrence(frequency: .yearly, interval: interval, byMonthDay: [yearDay], byMonth: yearMonth, end: end)
        }
    }

    private func loadInitial() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day, .weekday], from: eventDate)
        let dayOfMonth = comps.day ?? 1

        guard let rec = initial else {
            frequency = .weekly
            interval = 1
            let wd = Weekday.from(calendarWeekday: comps.weekday ?? 2) ?? .monday
            selectedWeekdays = [wd]
            monthDay = dayOfMonth
            yearMonth = comps.month ?? 1
            yearDay = dayOfMonth
            recurrenceBaseline = buildRecurrence()
            return
        }

        frequency = rec.frequency
        interval = rec.interval

        if let weekdays = rec.byWeekday, !weekdays.isEmpty {
            selectedWeekdays = Set(weekdays)
        } else {
            let wd = Weekday.from(calendarWeekday: comps.weekday ?? 2) ?? .monday
            selectedWeekdays = [wd]
        }

        if let days = rec.byMonthDay, let first = days.first {
            if rec.frequency == .monthly && rec.byWeekday != nil {
                monthDayMode = .weekdayOfMonth
                nthOccurrence = first
                nthWeekday = rec.byWeekday?.first ?? .monday
            } else if rec.frequency == .yearly {
                yearDay = first
                monthDay = dayOfMonth
            } else {
                monthDayMode = .dayOfMonth
                monthDay = first
            }
        } else {
            monthDay = dayOfMonth
            yearDay = dayOfMonth
        }

        yearMonth = rec.byMonth ?? (comps.month ?? 1)

        switch rec.end {
        case .never:
            endMode = .never
        case .until(let date):
            endMode = .onDate
            endDate = date
        case .count(let n):
            endMode = .afterCount
            endCount = n
        }

        recurrenceBaseline = buildRecurrence()
    }
}
