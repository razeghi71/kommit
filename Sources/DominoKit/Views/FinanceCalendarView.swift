import SwiftUI

package struct FinanceCalendarView: View {
    @ObservedObject var viewModel: DominoViewModel

    @State private var appliedStartingBalance: Double = 0
    @State private var customRecordPayload: FinanceCalendarCustomRecordPayload?
    @State private var didInitialScrollToToday = false

    private let horizonDays = 150
    private let columnWidth: CGFloat = 228
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
                    recordCommitmentOccurrence(commitment: payload.commitment, dueDate: payload.dueDate, recordedOn: picked)
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

        let oldestCommitment = viewModel.commitments.values
            .map { cal.startOfDay(for: $0.createdAt) }
            .min()
        let oldestForecast = viewModel.forecasts.values
            .map { cal.startOfDay(for: $0.createdAt) }
            .min()
        let oldestPlanning = [oldestCommitment, oldestForecast].compactMap { $0 }.min()
        let rangeFrom = oldestPlanning.map { max(historyCap, $0) } ?? historyCap

        var paidOccurrenceKeys = Set<String>()
        var paidRecordedDateByKey: [String: Date] = [:]
        for txn in viewModel.financialTransactions.values {
            guard let sid = txn.commitmentID else { continue }
            let key = Self.commitmentOccurrenceKey(commitmentID: sid, dueDate: txn.dueDate, calendar: cal)
            paidOccurrenceKeys.insert(key)
            paidRecordedDateByKey[key] = txn.date
        }

        let commitmentOccurrences = viewModel.expectedCommitmentOccurrences(from: rangeFrom, to: rangeTo, calendar: cal)
        let forecastOccurrences = viewModel.expectedForecastOccurrences(from: rangeFrom, to: rangeTo, calendar: cal)
        return FinanceCalendarProjection.buildColumns(
            calendar: cal,
            rangeStart: rangeFrom,
            rangeEnd: rangeTo,
            today: now,
            allCommitments: commitmentOccurrences,
            allForecasts: forecastOccurrences,
            isPaid: { id, due in
                paidOccurrenceKeys.contains(Self.commitmentOccurrenceKey(commitmentID: id, dueDate: due, calendar: cal))
            },
            paidRecordedOn: { id, due in
                paidRecordedDateByKey[Self.commitmentOccurrenceKey(commitmentID: id, dueDate: due, calendar: cal)]
            },
            startingBalanceAtTodayStart: appliedStartingBalance
        )
    }

    private static func commitmentOccurrenceKey(commitmentID: UUID, dueDate: Date, calendar cal: Calendar) -> String {
        let day = cal.startOfDay(for: dueDate)
        return "\(commitmentID.uuidString)|\(day.timeIntervalSinceReferenceDate)"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            FinanceCalendarStartingBalanceBar(onApply: { appliedStartingBalance = $0 })
            Spacer()
        }
        .padding(16)
    }

    private var calendarBody: some View {
        GeometryReader { geo in
            let middleScrollHeight = max(188, geo.size.height - 196)
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
                                todayStart: todayAnchor,
                                middleHeight: middleScrollHeight
                            )
                            .frame(width: columnWidth)
                            .id(column.displayDayStart)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
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

    private func dayColumn(
        column: FinanceCalendarDayColumn,
        isToday: Bool,
        todayStart: Date,
        middleHeight: CGFloat
    ) -> some View {
        let cal = calendar
        return VStack(alignment: .leading, spacing: 0) {
            dayHeader(date: column.displayDayStart, isToday: isToday, calendar: cal)

            Divider()
                .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let hasCommitments = !column.incomeLines.isEmpty || !column.expenseLines.isEmpty
                    let hasForecasts = !column.forecastIncomeLines.isEmpty || !column.forecastExpenseLines.isEmpty
                    if !hasCommitments && !hasForecasts {
                        Text("—")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(column.incomeLines) { line in
                            transactionEventBlock(line, displayDayStart: column.displayDayStart, todayStart: todayStart)
                        }
                        ForEach(column.expenseLines) { line in
                            transactionEventBlock(line, displayDayStart: column.displayDayStart, todayStart: todayStart)
                        }
                        ForEach(column.forecastIncomeLines) { line in
                            forecastEventBlock(line, displayDayStart: column.displayDayStart)
                        }
                        ForEach(column.forecastExpenseLines) { line in
                            forecastEventBlock(line, displayDayStart: column.displayDayStart)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .frame(height: middleHeight)

            Divider()
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 9) {
                Text(formatAmount(column.endOfDayBalance, positivePrefix: ""))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                VStack(alignment: .leading, spacing: 4) {
                    Text("In \(formatAmount(column.incomeTotal, positivePrefix: "+"))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Out \(formatAmount(column.expenseTotal, positivePrefix: ""))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if column.forecastIncomeTotal > 0 {
                        Text("Forecast in \(formatAmount(column.forecastIncomeTotal, positivePrefix: "+"))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if column.forecastExpenseTotal > 0 {
                        Text("Forecast out \(formatAmount(column.forecastExpenseTotal, positivePrefix: ""))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if isToday, column.overdueUnpaidExpenseTotal > 0 || column.overdueUnpaidIncomeTotal > 0 {
                        overdueStartCaption(column: column)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(isToday ? 0.06 : 0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isToday ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: isToday ? 1.5 : 1)
        }
        .padding(.trailing, 10)
    }

    private func dayHeader(date: Date, isToday: Bool, calendar cal: Calendar) -> some View {
        let weekday = Self.weekdayFormatter.string(from: date)
        let dayLabel = Self.dayFormatter.string(from: date)
        return VStack(spacing: 5) {
            Text(weekday)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(dayLabel)
                .font(.system(size: 17, weight: isToday ? .bold : .semibold))
                .monospacedDigit()
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                    if isToday {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 11)
    }

    private func overdueStartCaption(column: FinanceCalendarDayColumn) -> some View {
        Group {
            if column.overdueUnpaidExpenseTotal > 0 {
                Text("Overdue out \(formatAmount(-column.overdueUnpaidExpenseTotal, positivePrefix: ""))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if column.overdueUnpaidIncomeTotal > 0 {
                Text("Overdue in \(formatAmount(column.overdueUnpaidIncomeTotal, positivePrefix: "+"))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func transactionEventBlock(_ line: FinanceCalendarDueLine, displayDayStart: Date, todayStart: Date) -> some View {
        let cal = calendar
        let isOverdueRollupStriped = line.isRollupOnToday
        let colors = eventColors(for: line, todayStart: todayStart)
        let isIncome = line.commitment.type == .income
        let amountColor: Color = isIncome ? Self.harmonizedIncomeGreen : Self.harmonizedExpenseRed
        let due = line.occurrenceDueDate
        let commitment = line.commitment
        let trailingPadding: CGFloat = 30

        return ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(colors.fill)
                if isOverdueRollupStriped {
                    FinanceCalendarPastDueStripeOverlay()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isOverdueRollupStriped ? 0.62 : 1)

            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(colors.accent)
                    .frame(width: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(commitment.name.isEmpty ? "Untitled" : commitment.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(4)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, trailingPadding)

                    Text(isIncome ? "+\(formatPlainAmount(commitment.amount))" : "−\(formatPlainAmount(commitment.amount))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(amountColor)

                    if line.isRollupOnToday || !cal.isDate(due, inSameDayAs: displayDayStart) {
                        Text("Due: \(Self.shortDueFormatter.string(from: due))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 10)
                .padding(.trailing, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            eventTrailingIcon(
                isPaid: line.isPaid,
                accentColor: colors.accent,
                commitment: commitment,
                dueDate: due
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
    }

    private func forecastEventBlock(_ line: FinanceCalendarForecastLine, displayDayStart: Date) -> some View {
        let cal = calendar
        let isIncome = line.forecast.type == .income
        let amountColor: Color = isIncome ? Self.harmonizedIncomeGreen : Self.harmonizedExpenseRed
        let occ = line.occurrenceDate
        let forecast = line.forecast
        let trailingPadding: CGFloat = 12

        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Self.forecastAccent.opacity(0.35), lineWidth: 1)
                }

            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.forecastAccent.opacity(0.85))
                    .frame(width: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Forecast")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Self.forecastAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(Self.forecastAccent.opacity(0.14)))

                    Text(forecast.name.isEmpty ? "Untitled" : forecast.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(4)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, trailingPadding)

                    Text(isIncome ? "+\(formatPlainAmount(forecast.amount))" : "−\(formatPlainAmount(forecast.amount))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(amountColor)

                    if !cal.isDate(occ, inSameDayAs: displayDayStart) {
                        Text("Day: \(Self.shortDueFormatter.string(from: occ))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 10)
                .padding(.trailing, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func recordCommitmentOccurrence(commitment: Commitment, dueDate: Date, recordedOn: Date) {
        let txn = FinancialTransaction(
            commitmentID: commitment.id,
            name: commitment.name,
            amount: commitment.amount,
            type: commitment.type,
            date: recordedOn,
            dueDate: dueDate
        )
        viewModel.addFinancialTransaction(txn)
    }

    /// Paid → green; unpaid due on or before today → red; unpaid future → azure blue.
    private func eventColors(for line: FinanceCalendarDueLine, todayStart: Date) -> (accent: Color, fill: Color) {
        let cal = calendar
        if line.isPaid {
            return (Self.paidAccent, Self.paidAccent.opacity(0.26))
        }
        let dueDay = cal.startOfDay(for: line.occurrenceDueDate)
        let today = cal.startOfDay(for: todayStart)
        if dueDay <= today {
            return (Self.dueAccent, Self.dueAccent.opacity(0.22))
        }
        return (Self.futureUnpaidAccent, Self.futureUnpaidAccent.opacity(0.26))
    }

    private static let eventTrailingSymbolSize: CGFloat = 18
    private static let eventTrailingSymbolFrame: CGFloat = 24

    private func eventTrailingIcon(
        isPaid: Bool,
        accentColor: Color,
        commitment: Commitment,
        dueDate: Date
    ) -> some View {
        Image(systemName: isPaid ? "checkmark.circle.fill" : "plus.circle.fill")
            .font(.system(size: Self.eventTrailingSymbolSize))
            .foregroundStyle(.white)
            .symbolRenderingMode(.hierarchical)
            .frame(width: Self.eventTrailingSymbolFrame, height: Self.eventTrailingSymbolFrame)
            .contentShape(Rectangle())
            .overlay {
                if !isPaid {
                    Menu {
                        Button("Record on first working day on or after the due date") {
                            let recordedOn = FinancialRecurrence.firstWorkingDateOnOrAfter(dueDate, calendar: calendar)
                            recordCommitmentOccurrence(commitment: commitment, dueDate: dueDate, recordedOn: recordedOn)
                        }
                        Button("Record on due date") {
                            recordCommitmentOccurrence(commitment: commitment, dueDate: dueDate, recordedOn: dueDate)
                        }
                        Button("Record on Today") {
                            recordCommitmentOccurrence(commitment: commitment, dueDate: dueDate, recordedOn: Date())
                        }
                        Button("Record on custom date…") {
                            customRecordPayload = FinanceCalendarCustomRecordPayload(commitment: commitment, dueDate: dueDate)
                        }
                    } label: {
                        Color.white.opacity(0.001)
                            .frame(width: Self.eventTrailingSymbolFrame, height: Self.eventTrailingSymbolFrame)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 5)
            .padding(.trailing, 5)
    }

    /// Cool emerald—pairs with `harmonizedExpenseRed` without clashing like system green vs red.
    private static let harmonizedIncomeGreen = Color(red: 0.20, green: 0.56, blue: 0.46)
    private static let harmonizedExpenseRed = Color(red: 0.78, green: 0.30, blue: 0.34)
    private static let paidAccent = harmonizedIncomeGreen
    private static let dueAccent = harmonizedExpenseRed
    /// Soft azure—cool like the emerald green, distinct from green/red amount text.
    private static let futureUnpaidAccent = Color(red: 0.22, green: 0.52, blue: 0.86)
    private static let forecastAccent = Color(red: 0.45, green: 0.42, blue: 0.62)

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

/// Subtle diagonal fill like Calendar’s tentative / unanswered invites.
private struct FinanceCalendarPastDueStripeOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let spacing: CGFloat = 11
                let band: CGFloat = 3
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height + band, y: size.height))
                    path.addLine(to: CGPoint(x: x + band, y: 0))
                    path.closeSubpath()
                    context.fill(path, with: .color(Color.primary.opacity(0.11)))
                    x += spacing
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FinanceCalendarCustomRecordPayload: Identifiable {
    var id: String { "\(commitment.id.uuidString)|\(dueDate.timeIntervalSinceReferenceDate)" }
    let commitment: Commitment
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
        HStack(spacing: 11) {
            Text("Starting balance")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("0", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, design: .monospaced))
                .frame(width: 148, alignment: .leading)
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
