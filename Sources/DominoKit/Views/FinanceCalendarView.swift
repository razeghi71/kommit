import SwiftUI

package struct FinanceCalendarView: View {
    @ObservedObject var viewModel: DominoViewModel

    @State private var appliedStartingBalance: Double = 0
    @State private var customRecordPayload: FinanceCalendarCustomRecordPayload?
    @State private var didInitialScrollToToday = false

    private let horizonDays = 150
    private let columnWidth: CGFloat = 172
    /// Cap history so we do not build tens of thousands of day columns or scan decades of months.
    private let calendarLookbackDays = 548

    package init(viewModel: DominoViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            calendarBody
        }
        .sheet(item: $customRecordPayload) { payload in
            FinanceCalendarCustomRecordSheet(
                dueDate: payload.dueDate,
                onRecord: { picked in
                    recordScheduledOccurrence(scheduled: payload.scheduled, dueDate: payload.dueDate, recordedOn: picked)
                    customRecordPayload = nil
                },
                onCancel: { customRecordPayload = nil }
            )
        }
    }

    private var calendar: Calendar { .current }

    private var dayColumns: [FinanceCalendarDayColumn] {
        let cal = calendar
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        guard let historyCap = cal.date(byAdding: .day, value: -calendarLookbackDays, to: todayStart),
              let rangeTo = cal.date(byAdding: .day, value: horizonDays, to: todayStart)
        else { return [] }

        let oldestScheduled = viewModel.scheduledTransactions.values
            .map { cal.startOfDay(for: $0.createdAt) }
            .min()
        let rangeFrom = oldestScheduled.map { max(historyCap, $0) } ?? historyCap

        var paidOccurrenceKeys = Set<String>()
        var paidRecordedDateByKey: [String: Date] = [:]
        for txn in viewModel.financialTransactions.values {
            guard let sid = txn.scheduledTransactionID else { continue }
            let key = Self.scheduledOccurrenceKey(scheduledID: sid, dueDate: txn.dueDate, calendar: cal)
            paidOccurrenceKeys.insert(key)
            paidRecordedDateByKey[key] = txn.date
        }

        let dues = viewModel.expectedDues(from: rangeFrom, to: rangeTo, calendar: cal)
        return FinanceCalendarProjection.buildColumns(
            calendar: cal,
            rangeStart: rangeFrom,
            rangeEnd: rangeTo,
            today: now,
            allDues: dues,
            isPaid: { id, due in
                paidOccurrenceKeys.contains(Self.scheduledOccurrenceKey(scheduledID: id, dueDate: due, calendar: cal))
            },
            paidRecordedOn: { id, due in
                paidRecordedDateByKey[Self.scheduledOccurrenceKey(scheduledID: id, dueDate: due, calendar: cal)]
            },
            startingBalanceAtTodayStart: appliedStartingBalance
        )
    }

    private static func scheduledOccurrenceKey(scheduledID: UUID, dueDate: Date, calendar cal: Calendar) -> String {
        let day = cal.startOfDay(for: dueDate)
        return "\(scheduledID.uuidString)|\(day.timeIntervalSinceReferenceDate)"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            FinanceCalendarStartingBalanceBar(onApply: { appliedStartingBalance = $0 })
            Spacer()
        }
        .padding(12)
    }

    private var calendarBody: some View {
        GeometryReader { geo in
            let middleScrollHeight = max(140, geo.size.height - 210)
            let now = Date()
            let cal = calendar
            let todayAnchor = cal.startOfDay(for: now)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(dayColumns) { column in
                            dayColumn(
                                column: column,
                                isToday: cal.isDate(column.displayDayStart, inSameDayAs: now),
                                middleHeight: middleScrollHeight
                            )
                            .frame(width: columnWidth)
                            .id(column.displayDayStart)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
                .onAppear {
                    scheduleScrollToToday(proxy: proxy, todayAnchor: todayAnchor)
                }
                .onChange(of: dayColumns.count) { _, _ in
                    scheduleScrollToToday(proxy: proxy, todayAnchor: todayAnchor)
                }
            }
        }
    }

    private func scheduleScrollToToday(proxy: ScrollViewProxy, todayAnchor: Date) {
        guard !didInitialScrollToToday, !dayColumns.isEmpty else { return }
        didInitialScrollToToday = true
        DispatchQueue.main.async {
            proxy.scrollTo(todayAnchor, anchor: .center)
        }
    }

    private func dayColumn(column: FinanceCalendarDayColumn, isToday: Bool, middleHeight: CGFloat) -> some View {
        let cal = calendar
        return VStack(alignment: .leading, spacing: 0) {
            dayHeader(date: column.displayDayStart, isToday: isToday, calendar: cal)

            Divider()
                .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if column.incomeLines.isEmpty && column.expenseLines.isEmpty {
                        Text("—")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(column.incomeLines) { line in
                            transactionEventBlock(line, displayDayStart: column.displayDayStart)
                        }
                        ForEach(column.expenseLines) { line in
                            transactionEventBlock(line, displayDayStart: column.displayDayStart)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .frame(height: middleHeight)

            Divider()
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Out Balance")
                    .font(.system(size: 11, weight: .bold))
                Text(formatAmount(column.endOfDayBalance, positivePrefix: ""))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                VStack(alignment: .leading, spacing: 2) {
                    Text("In \(formatAmount(column.incomeTotal, positivePrefix: "+"))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Out \(formatAmount(column.expenseTotal, positivePrefix: ""))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isToday ? 0.06 : 0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isToday ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: isToday ? 1.5 : 1)
        }
        .padding(.trailing, 6)
    }

    private func dayHeader(date: Date, isToday: Bool, calendar cal: Calendar) -> some View {
        let weekday = Self.weekdayFormatter.string(from: date)
        let dayLabel = Self.dayFormatter.string(from: date)
        return VStack(spacing: 3) {
            Text(weekday)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(dayLabel)
                .font(.system(size: 14, weight: isToday ? .bold : .semibold))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if isToday {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func transactionEventBlock(_ line: FinanceCalendarDueLine, displayDayStart: Date) -> some View {
        let colors = eventColors(for: line)
        let isIncome = line.scheduled.type == .income
        let due = line.occurrenceDueDate
        let scheduled = line.scheduled
        let trailingPadding: CGFloat = 22

        return ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(colors.accent)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scheduled.name.isEmpty ? "Untitled" : scheduled.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(4)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, trailingPadding)

                    Text(isIncome ? "+\(formatPlainAmount(scheduled.amount))" : "−\(formatPlainAmount(scheduled.amount))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isIncome ? Color.green : .primary)

                    if !calendar.isDate(due, inSameDayAs: displayDayStart) {
                        Text("Due: \(Self.shortDueFormatter.string(from: due))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .padding(.leading, 6)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if line.isPaid {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
            } else {
                Menu {
                    Button("Record on first working day on or after the due date") {
                        let recordedOn = FinancialScheduling.firstWorkingDateOnOrAfter(due, calendar: calendar)
                        recordScheduledOccurrence(scheduled: scheduled, dueDate: due, recordedOn: recordedOn)
                    }
                    Button("Record on due date") {
                        recordScheduledOccurrence(scheduled: scheduled, dueDate: due, recordedOn: due)
                    }
                    Button("Record on Today") {
                        recordScheduledOccurrence(scheduled: scheduled, dueDate: due, recordedOn: Date())
                    }
                    Button("Record on custom date…") {
                        customRecordPayload = FinanceCalendarCustomRecordPayload(scheduled: scheduled, dueDate: due)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.trailing, 4)
                .contentShape(Rectangle())
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(colors.fill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
    }

    private func recordScheduledOccurrence(scheduled: ScheduledTransaction, dueDate: Date, recordedOn: Date) {
        let txn = FinancialTransaction(
            scheduledTransactionID: scheduled.id,
            name: scheduled.name,
            amount: scheduled.amount,
            type: scheduled.type,
            date: recordedOn,
            dueDate: dueDate
        )
        viewModel.addFinancialTransaction(txn)
    }

    private func eventColors(for line: FinanceCalendarDueLine) -> (accent: Color, fill: Color) {
        let pairs = line.scheduled.type == .income ? Self.incomeEventPairs : Self.expenseEventPairs
        let base = pairs[Self.stablePaletteIndex(line.id, count: pairs.count)]
        return (base, base.opacity(0.28))
    }

    private static let incomeEventPairs: [Color] = [
        .green,
        .mint,
        Color(red: 0.2, green: 0.72, blue: 0.48),
        .teal,
    ]

    private static let expenseEventPairs: [Color] = [
        .teal,
        .blue,
        .indigo,
        .purple,
        Color(red: 0.35, green: 0.55, blue: 0.95),
        .cyan,
        .orange,
        .pink,
    ]

    private static func stablePaletteIndex(_ key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var h: UInt64 = 5381
        for b in key.utf8 {
            h = ((h &<< 5) &+ h) &+ UInt64(b)
        }
        return Int(h % UInt64(count))
    }

    private func formatAmount(_ amount: Double, positivePrefix: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let core = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
        let prefix: String
        if amount < 0 {
            prefix = "-$"
        } else if positivePrefix == "+" && amount > 0 {
            prefix = "+$"
        } else {
            prefix = "$"
        }
        return prefix + core
    }

    private func formatPlainAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let core = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "$" + core
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let shortDueFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

private struct FinanceCalendarCustomRecordPayload: Identifiable {
    var id: String { "\(scheduled.id.uuidString)|\(dueDate.timeIntervalSinceReferenceDate)" }
    let scheduled: ScheduledTransaction
    let dueDate: Date
}

private struct FinanceCalendarCustomRecordSheet: View {
    @State private var recordDate: Date
    let onRecord: (Date) -> Void
    let onCancel: () -> Void

    init(dueDate: Date, onRecord: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        _recordDate = State(initialValue: dueDate)
        self.onRecord = onRecord
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker("Record date", selection: $recordDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Spacer()
            }
            .padding()
            .navigationTitle("Custom Record Date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") {
                        onRecord(recordDate)
                    }
                }
            }
        }
    }
}

/// Draft text lives here so each keystroke does not rebuild the full calendar (`dayColumns` is expensive).
private struct FinanceCalendarStartingBalanceBar: View {
    @State private var draftText: String = "0"
    var onApply: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Starting balance")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("0", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 120, alignment: .leading)
                .multilineTextAlignment(.leading)
            Button("Apply") {
                let trimmed = draftText.replacingOccurrences(of: ",", with: "")
                onApply(Double(trimmed) ?? 0)
            }
            .buttonStyle(.borderedProminent)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
