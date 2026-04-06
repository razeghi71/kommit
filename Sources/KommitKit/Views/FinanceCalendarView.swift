import SwiftUI

package struct FinanceCalendarView: View {
    @ObservedObject var viewModel: KommitViewModel

    @State private var customRecordPayload: FinanceCalendarCustomRecordPayload?
    @State private var forecastQuickLogPayload: FinanceCalendarForecastQuickLogPayload?
    @State private var editingCalendarTransaction: FinancialTransaction?
    @State private var financeAccountsPresentation: FinanceAccountsSheetLaunch?
    @State private var didInitialScrollToToday = false
    @State private var pendingScrollTarget: Date?

    private let horizonDays = 150
    private let columnWidth: CGFloat = 228
    /// Space left under day columns so they don’t sit flush on the window bottom.
    private let calendarColumnBottomInset: CGFloat = 20
    /// Cap history so we do not build tens of thousands of day columns or scan decades of months.
    private let calendarLookbackDays = 548

    package init(viewModel: KommitViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(onScrollToToday: { scrollCalendarToToday(proxy: proxy) })
                Divider()
                calendarBody(scrollProxy: proxy)
            }
            .onChange(of: pendingScrollTarget) { _, target in
                guard let target else { return }
                scrollCalendarToDate(target, proxy: proxy)
                pendingScrollTarget = nil
            }
        }
        .sheet(item: $customRecordPayload) { payload in
            FinanceCalendarCustomRecordSheet(
                dueDate: payload.dueDate,
                calendar: calendar,
                onRecord: { picked in
                    recordCommitmentOccurrence(commitment: payload.commitment, dueDate: payload.dueDate, recordedOn: picked)
                    customRecordPayload = nil
                },
                onCancel: { customRecordPayload = nil }
            )
        }
        .sheet(item: $forecastQuickLogPayload) { payload in
            let comps = Calendar.current.dateComponents([.year, .month], from: payload.occurrenceDate)
            TransactionEditorView(
                viewModel: viewModel,
                transaction: nil,
                defaultMonth: comps.month ?? 1,
                defaultYear: comps.year ?? 2026,
                prefilledForecastID: payload.forecast.id,
                prefilledPaymentDate: payload.occurrenceDate
            )
        }
        .sheet(item: $editingCalendarTransaction) { txn in
            TransactionEditorView(
                viewModel: viewModel,
                transaction: txn,
                defaultMonth: Calendar.current.component(.month, from: txn.date),
                defaultYear: Calendar.current.component(.year, from: txn.date)
            )
        }
        .sheet(item: $financeAccountsPresentation) { launch in
            FinanceAccountsSheet(viewModel: viewModel, launch: launch)
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
            guard txn.isSettlement, let settles = txn.settles else { continue }
            let key = Self.commitmentOccurrenceKey(commitmentID: settles.commitmentID, dueDate: settles.dueDate, calendar: cal)
            paidOccurrenceKeys.insert(key)
            paidRecordedDateByKey[key] = txn.date
        }

        let commitmentOccurrences = viewModel.expectedCommitmentOccurrences(from: rangeFrom, to: rangeTo, calendar: cal)
        let forecastOccurrences = viewModel.expectedForecastOccurrences(from: rangeFrom, to: rangeTo, calendar: cal)
        let recordedTransactions = viewModel.financialTransactions.values.filter(\.isRecorded)
        return FinanceCalendarProjection.buildColumns(
            calendar: cal,
            rangeStart: rangeFrom,
            rangeEnd: rangeTo,
            today: now,
            allCommitments: commitmentOccurrences,
            allForecasts: forecastOccurrences,
            recordedTransactions: Array(recordedTransactions),
            forecastsByID: viewModel.forecasts,
            commitmentsByID: viewModel.commitments,
            commitmentAmount: { id, due in
                viewModel.expectedCommitmentAmount(for: id, dueDate: due, calendar: cal)
            },
            paidSettlementAmount: { id, due in
                let key = Self.commitmentOccurrenceKey(commitmentID: id, dueDate: due, calendar: cal)
                return viewModel.financialTransactions.values.first { txn in
                    guard txn.isSettlement, let settles = txn.settles else { return false }
                    let txnKey = Self.commitmentOccurrenceKey(
                        commitmentID: settles.commitmentID,
                        dueDate: settles.dueDate,
                        calendar: cal
                    )
                    return txnKey == key
                }?.amount
            },
            recordedTransactionAmount: { txn in
                viewModel.resolvedTransactionAmount(txn)
            },
            isPaid: { id, due in
                paidOccurrenceKeys.contains(Self.commitmentOccurrenceKey(commitmentID: id, dueDate: due, calendar: cal))
            },
            paidRecordedOn: { id, due in
                paidRecordedDateByKey[Self.commitmentOccurrenceKey(commitmentID: id, dueDate: due, calendar: cal)]
            },
            startingBalanceAtTodayStart: viewModel.financeCalendarTotalBalance
        )
    }

    private static func commitmentOccurrenceKey(commitmentID: UUID, dueDate: Date, calendar cal: Calendar) -> String {
        let day = cal.startOfDay(for: dueDate)
        return "\(commitmentID.uuidString)|\(day.timeIntervalSinceReferenceDate)"
    }

    private func financialTransactionForPaidCommitmentLine(_ line: FinanceCalendarDueLine) -> FinancialTransaction? {
        guard line.isPaid else { return nil }
        let cal = calendar
        let target = Self.commitmentOccurrenceKey(
            commitmentID: line.commitment.id,
            dueDate: line.occurrenceDueDate,
            calendar: cal
        )
        return viewModel.financialTransactions.values.first { txn in
            guard txn.isSettlement, let settles = txn.settles else { return false }
            return Self.commitmentOccurrenceKey(commitmentID: settles.commitmentID, dueDate: settles.dueDate, calendar: cal) == target
        }
    }

    private func header(onScrollToToday: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current balance")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Button {
                        financeAccountsPresentation = .manage
                    } label: {
                        Text(viewModel.formatFinancialCurrency(viewModel.financeCalendarTotalBalance))
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .help("View and edit accounts")
                }
                if viewModel.financeAccounts.isEmpty {
                    Button {
                        financeAccountsPresentation = .addAccount
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .help("Add account")
                } else {
                    Button {
                        financeAccountsPresentation = .manage
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .help("Edit accounts")
                }
            }
            Spacer()
            Button("Today", action: onScrollToToday)
                .buttonStyle(.bordered)
        }
        .padding(16)
    }

    private func calendarBody(scrollProxy: ScrollViewProxy) -> some View {
        GeometryReader { geo in
            let columnHeight = max(0, geo.size.height - calendarColumnBottomInset)
            // Reserve header + dividers + footer band (includes day header bottom padding).
            let middleScrollHeight = max(188, columnHeight - 208)
            let now = Date()
            let cal = calendar
            let todayAnchor = cal.startOfDay(for: now)
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(dayColumns) { column in
                        dayColumn(
                            column: column,
                            isToday: cal.isDate(column.displayDayStart, inSameDayAs: now),
                            todayStart: todayAnchor,
                            middleHeight: middleScrollHeight,
                            columnHeight: columnHeight
                        )
                        .id(column.displayDayStart)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
            .onAppear {
                scheduleScrollToToday(proxy: scrollProxy, todayAnchor: todayAnchor)
            }
            .onChange(of: dayColumns.count) { _, _ in
                scheduleScrollToToday(proxy: scrollProxy, todayAnchor: todayAnchor)
            }
        }
    }

    private func scrollCalendarToToday(proxy: ScrollViewProxy) {
        let todayAnchor = calendar.startOfDay(for: Date())
        DispatchQueue.main.async {
            proxy.scrollTo(todayAnchor, anchor: .center)
        }
    }

    private func scrollCalendarToDate(_ date: Date, proxy: ScrollViewProxy) {
        let target = calendar.startOfDay(for: date)
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .center)
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
        middleHeight: CGFloat,
        columnHeight: CGFloat
    ) -> some View {
        let cal = calendar
        let isPastDay = column.displayDayStart < todayStart
        let scrollHeight = middleHeight
        return VStack(alignment: .leading, spacing: 0) {
            dayHeader(date: column.displayDayStart, isToday: isToday, calendar: cal)

            Divider()
                .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let hasCommitments = !column.incomeLines.isEmpty || !column.expenseLines.isEmpty
                    let hasForecastProjections =
                        !column.forecastIncomeLines.isEmpty || !column.forecastExpenseLines.isEmpty
                    let hasForecastRealized =
                        !column.forecastRealizedIncomeLines.isEmpty || !column.forecastRealizedExpenseLines.isEmpty
                    if !hasCommitments && !hasForecastProjections && !hasForecastRealized {
                        Text("—")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        if hasForecastProjections {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(column.forecastIncomeLines) { line in
                                    forecastEventBlock(line, displayDayStart: column.displayDayStart, isPastDay: isPastDay, isToday: isToday)
                                }
                                ForEach(column.forecastExpenseLines) { line in
                                    forecastEventBlock(line, displayDayStart: column.displayDayStart, isPastDay: isPastDay, isToday: isToday)
                                }
                            }
                        }
                        if hasForecastRealized {
                            ForEach(column.forecastRealizedIncomeLines) { line in
                                forecastRealizedEventBlock(line, displayDayStart: column.displayDayStart)
                            }
                            ForEach(column.forecastRealizedExpenseLines) { line in
                                forecastRealizedEventBlock(line, displayDayStart: column.displayDayStart)
                            }
                        }
                        ForEach(column.incomeLines) { line in
                            transactionEventBlock(line, displayDayStart: column.displayDayStart, todayStart: todayStart)
                        }
                        ForEach(column.expenseLines) { line in
                            transactionEventBlock(line, displayDayStart: column.displayDayStart, todayStart: todayStart)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .frame(height: scrollHeight)

            Divider()
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 9) {
                financeCalendarDayFooter(column: column)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .background {
                if !isPastDay, column.endOfDayBalance < 0 {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Self.harmonizedExpenseRed.opacity(0.14))
                }
            }
        }
        .frame(width: columnWidth, height: columnHeight, alignment: .top)
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
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func financeCalendarDayFooter(column: FinanceCalendarDayColumn) -> some View {
        switch column.footer {
        case .pastFlows(let inAmount, let outAmount):
            VStack(alignment: .leading, spacing: 4) {
                Text("In \(formatCalendarFlowAmount(inAmount, leadingPlusWhenPositive: true))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Out \(formatCalendarFlowAmount(outAmount, leadingPlusWhenPositive: false))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .todaySplit(let inSoFar, let outSoFar, let expectedIn, let expectedOut):
            let isNegativeEndBalance = column.endOfDayBalance < 0
            VStack(alignment: .leading, spacing: 9) {
                Text(viewModel.formatFinancialCurrency(column.endOfDayBalance))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isNegativeEndBalance ? Self.harmonizedExpenseRed : Color.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("In till now \(formatCalendarFlowAmount(inSoFar, leadingPlusWhenPositive: true))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Out till now \(formatCalendarFlowAmount(outSoFar, leadingPlusWhenPositive: false))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Expected out \(formatCalendarFlowAmount(expectedOut, leadingPlusWhenPositive: false))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Expected in till day end \(formatCalendarFlowAmount(expectedIn, leadingPlusWhenPositive: true))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if column.overdueUnpaidExpenseTotal > 0 || column.overdueUnpaidIncomeTotal > 0 {
                        overdueStartCaption(column: column)
                    }
                }
            }
        case .futureExpected(let inAmount, let outAmount):
            let isNegativeEndBalance = column.endOfDayBalance < 0
            VStack(alignment: .leading, spacing: 9) {
                Text(viewModel.formatFinancialCurrency(column.endOfDayBalance))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isNegativeEndBalance ? Self.harmonizedExpenseRed : Color.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("In \(formatCalendarFlowAmount(inAmount, leadingPlusWhenPositive: true))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Out \(formatCalendarFlowAmount(outAmount, leadingPlusWhenPositive: false))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func overdueStartCaption(column: FinanceCalendarDayColumn) -> some View {
        Group {
            if column.overdueUnpaidExpenseTotal > 0 {
                Text("Overdue out \(viewModel.formatFinancialCurrency(-column.overdueUnpaidExpenseTotal))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if column.overdueUnpaidIncomeTotal > 0 {
                Text("Overdue in \(formatCalendarFlowAmount(column.overdueUnpaidIncomeTotal, leadingPlusWhenPositive: true))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func transactionEventBlock(_ line: FinanceCalendarDueLine, displayDayStart: Date, todayStart: Date) -> some View {
        let cal = calendar
        let isOverdueRollupStriped = line.isRollupOnToday
        let colors = eventColors(for: line, todayStart: todayStart)
        let isIncome = line.commitment.type == .income
        let amountColor: Color = isIncome ? Self.harmonizedIncomeGreen : Self.harmonizedExpenseRed
        let due = line.occurrenceDueDate
        let commitment = line.commitment
        let trailingPadding: CGFloat = line.isPaid ? 10 : 30

        let card = ZStack(alignment: .topTrailing) {
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

                    Text(isIncome ? "+\(viewModel.formatFinancialCurrencyUnsigned(line.amount))" : "−\(viewModel.formatFinancialCurrencyUnsigned(line.amount))")
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

        if line.isPaid, let txn = financialTransactionForPaidCommitmentLine(line) {
            Button {
                editingCalendarTransaction = txn
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }

    private func forecastEventBlock(_ line: FinanceCalendarForecastLine, displayDayStart: Date, isPastDay: Bool, isToday: Bool) -> some View {
        let cal = calendar
        let forecast = line.forecast
        let isIncome = forecast.type == .income
        let amountColor: Color = isIncome ? Self.harmonizedIncomeGreen : Self.harmonizedExpenseRed
        let amountText = isIncome
            ? "+\(viewModel.formatFinancialCurrencyUnsigned(forecast.amount))"
            : "−\(viewModel.formatFinancialCurrencyUnsigned(forecast.amount))"
        let title = forecast.name.isEmpty ? "Untitled" : forecast.name
        let occ = line.occurrenceDate
        let showAltDay = !cal.isDate(occ, inSameDayAs: displayDayStart)

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if showAltDay {
                Text("  \(Self.shortDueFormatter.string(from: occ))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            
            if !isPastDay {
                Text(amountText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(amountColor)
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            if isPastDay || isToday {
                if isToday {
                    Spacer().frame(width: 6)
                }
                
                Button {
                    forecastQuickLogPayload = FinanceCalendarForecastQuickLogPayload(
                        forecast: forecast,
                        occurrenceDate: displayDayStart
                    )
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Self.futureUnpaidAccent, .white)
                        .symbolRenderingMode(.palette)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
    }

    /// Recorded planning-linked txn on its recorded date: forecast attribution and/or deferred-payment reference.
    @ViewBuilder
    private func forecastRealizedEventBlock(_ line: FinanceCalendarForecastRealizedLine, displayDayStart _: Date) -> some View {
        let txn = line.transaction
        let isIncome = txn.type == .income
        let amountColor: Color = isIncome ? Self.harmonizedIncomeGreen : Self.harmonizedExpenseRed
        let transactionTitle = txn.name.isEmpty ? "Untitled" : txn.name
        let isDeferred = txn.deferredTo != nil
        let isStandalone = line.forecast == nil && line.deferredCommitment == nil
        let planningCaption: String? = {
            guard let f = line.forecast, !f.name.isEmpty else { return nil }
            return f.name
        }() ?? {
            guard let commitment = line.deferredCommitment else { return nil }
            let title = commitment.name.isEmpty ? "Untitled" : commitment.name
            return "Deferred to \(title)"
        }()
        let accent: Color = {
            if isStandalone { return Self.standaloneRecordedAccent }
            return isDeferred ? Self.deferredRecordedAccent : Self.forecastRealizedAccent
        }()
        let fill = accent.opacity(0.14)

        let card = HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.92))
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 6) {
                Text(transactionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(4)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(isIncome ? "+\(viewModel.formatFinancialCurrencyUnsigned(line.amount))" : "−\(viewModel.formatFinancialCurrencyUnsigned(line.amount))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(amountColor)

                if let planningCaption {
                    Text(planningCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 0.5)
        }

        ZStack(alignment: .bottomTrailing) {
            Button {
                editingCalendarTransaction = txn
            } label: {
                card
            }
            .buttonStyle(.plain)

            if let deferredTo = txn.deferredTo {
                Button {
                    pendingScrollTarget = deferredTo.dueDate
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent, .white)
                        .symbolRenderingMode(.palette)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .help("Go to payment on \(Self.shortDueFormatter.string(from: deferredTo.dueDate))")
            }
        }
    }

    private func recordCommitmentOccurrence(commitment: Commitment, dueDate: Date, recordedOn: Date) {
        let txn = FinancialTransaction(
            kind: .settlement,
            settles: CommitmentOccurrenceRef(commitmentID: commitment.id, dueDate: dueDate),
            name: commitment.name,
            amount: viewModel.expectedCommitmentAmount(for: commitment.id, dueDate: dueDate),
            type: commitment.type,
            date: recordedOn,
            tags: commitment.tags
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

    @ViewBuilder
    private func eventTrailingIcon(
        isPaid: Bool,
        accentColor: Color,
        commitment: Commitment,
        dueDate: Date
    ) -> some View {
        if isPaid {
            EmptyView()
        } else {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: Self.eventTrailingSymbolSize))
                .foregroundStyle(accentColor, .white)
                .symbolRenderingMode(.palette)
                .frame(width: Self.eventTrailingSymbolFrame, height: Self.eventTrailingSymbolFrame)
                .contentShape(Rectangle())
                .overlay {
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
                .padding(.top, 5)
                .padding(.trailing, 5)
        }
    }

    /// Cool emerald—pairs with `harmonizedExpenseRed` without clashing like system green vs red.
    private static let harmonizedIncomeGreen = Color(red: 0.20, green: 0.56, blue: 0.46)
    private static let harmonizedExpenseRed = Color(red: 0.78, green: 0.30, blue: 0.34)
    private static let paidAccent = harmonizedIncomeGreen
    private static let dueAccent = harmonizedExpenseRed
    /// Soft azure—cool like the emerald green, distinct from green/red amount text.
    private static let futureUnpaidAccent = Color(red: 0.22, green: 0.52, blue: 0.86)
    /// Forecast-linked recorded txns (past)—distinct from commitment paid green.
    private static let forecastRealizedAccent = Color(red: 0.48, green: 0.40, blue: 0.72)
    /// Warm amber to indicate "recorded, but payment is deferred elsewhere".
    private static let deferredRecordedAccent = Color(red: 0.80, green: 0.61, blue: 0.20)
    /// Muted slate—recorded cash flow not tied to a forecast or bill.
    private static let standaloneRecordedAccent = Color(red: 0.38, green: 0.46, blue: 0.54)

    private func formatCalendarFlowAmount(_ amount: Double, leadingPlusWhenPositive: Bool) -> String {
        if amount < 0 {
            return viewModel.formatFinancialCurrency(amount)
        }
        if leadingPlusWhenPositive, amount > 0 {
            return "+" + viewModel.formatFinancialCurrencyUnsigned(amount)
        }
        return viewModel.formatFinancialCurrencyUnsigned(amount)
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

private struct FinanceCalendarForecastQuickLogPayload: Identifiable {
    var id: String { "\(forecast.id.uuidString)|\(occurrenceDate.timeIntervalSinceReferenceDate)" }
    let forecast: Forecast
    let occurrenceDate: Date
}

private struct FinanceCalendarCustomRecordSheet: View {
    let calendar: Calendar
    @State private var recordDate: Date
    @State private var recordMonthAnchor: Date
    let onRecord: (Date) -> Void
    let onCancel: () -> Void

    init(
        dueDate: Date,
        calendar: Calendar = .current,
        onRecord: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.calendar = calendar
        let start = calendar.startOfDay(for: dueDate)
        _recordDate = State(initialValue: start)
        _recordMonthAnchor = State(initialValue: CalendarDatePickerDayMath.firstDayOfMonth(containing: start, calendar: calendar))
        self.onRecord = onRecord
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                CalendarGridDatePicker(
                    selectedDate: $recordDate,
                    monthAnchor: $recordMonthAnchor,
                    calendar: calendar
                )
                Spacer()
            }
            .padding()
            .frame(minWidth: 300, minHeight: 420)
            .navigationTitle("Custom Record Date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") {
                        onRecord(calendar.startOfDay(for: recordDate))
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

