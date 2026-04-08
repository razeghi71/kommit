import SwiftUI

// MARK: - Finance Summary View

struct FinanceSummaryView: View {
    /// Minimum width to show "Spending by Tag" and "Forecast vs Actual" side by side.
    private static let sideBySideBreakpoint: CGFloat = 960

    @ObservedObject var viewModel: KommitViewModel
    @Binding var filterMonth: Int
    @Binding var filterYear: Int
    @State private var drilldown: TransactionDrilldown?

    init(viewModel: KommitViewModel, filterMonth: Binding<Int>, filterYear: Binding<Int>) {
        self.viewModel = viewModel
        _filterMonth = filterMonth
        _filterYear = filterYear
    }

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 24) {
                        incomeExpenseCard

                        if geo.size.width >= Self.sideBySideBreakpoint {
                            HStack(alignment: .top, spacing: 16) {
                                tagBreakdownCard
                                    .frame(maxWidth: .infinity, alignment: .top)
                                forecastComparisonCard
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                        } else {
                            VStack(spacing: 24) {
                                tagBreakdownCard
                                forecastComparisonCard
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .sheet(item: $drilldown) { payload in
            SummaryTransactionsDrilldownView(viewModel: viewModel, payload: payload)
        }
    }

    // MARK: - Header with month picker

    private var header: some View {
        HStack {
            Text("Summary")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            monthPicker
        }
        .padding(12)
    }

    private var monthPicker: some View {
        HStack(spacing: 4) {
            Button { previousMonth() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Text(monthYearLabel)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 120)

            Button { nextMonth() } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }

    private var monthYearLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let comps = DateComponents(year: filterYear, month: filterMonth, day: 1)
        guard let date = calendar.date(from: comps) else { return "" }
        return formatter.string(from: date)
    }

    private func previousMonth() {
        filterMonth -= 1
        if filterMonth < 1 { filterMonth = 12; filterYear -= 1 }
    }

    private func nextMonth() {
        filterMonth += 1
        if filterMonth > 12 { filterMonth = 1; filterYear += 1 }
    }

    // MARK: - Data helpers

    private var summaryMonthTransactions: [FinancialTransaction] {
        viewModel.transactionsForMonth(month: filterMonth, year: filterYear).filter { txn in
            if txn.isRecorded {
                return true
            }
            if txn.isSettlement {
                return !viewModel.settlementRepresentsDeferredPayment(txn, calendar: calendar)
            }
            return false
        }
    }

    private var recordedMonthTransactions: [FinancialTransaction] {
        viewModel.recordedTransactionsForMonth(month: filterMonth, year: filterYear)
    }

    private var summaryExpenseMonthTransactions: [FinancialTransaction] {
        summaryMonthTransactions.filter { $0.type == .expense }
    }

    private var totalIncome: Double {
        summaryMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + viewModel.resolvedTransactionAmount($1) }
    }

    private var totalExpenses: Double {
        summaryExpenseMonthTransactions.reduce(0) { $0 + viewModel.resolvedTransactionAmount($1) }
    }

    // MARK: - 1) Income / Expense Overview

    private var incomeExpenseCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Overview", systemImage: "banknote")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 14)

            HStack(spacing: 0) {
                summaryStatBlock(
                    title: "Income",
                    amount: totalIncome,
                    color: Self.incomeGreen,
                    prefix: "+"
                )

                Divider()
                    .frame(height: 52)

                summaryStatBlock(
                    title: "Expenses",
                    amount: totalExpenses,
                    color: Self.expenseRed,
                    prefix: "-"
                )

                Divider()
                    .frame(height: 52)

                let net = totalIncome - totalExpenses
                summaryStatBlock(
                    title: "Net",
                    amount: abs(net),
                    color: net >= 0 ? Self.incomeGreen : Self.expenseRed,
                    prefix: net >= 0 ? "+" : "-"
                )
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func summaryStatBlock(title: String, amount: Double, color: Color, prefix: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(prefix)\(viewModel.formatFinancialCurrencyUnsigned(amount))")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2) Tag Breakdown

    private var tagSpending: [(tag: String, amount: Double)] {
        var totals: [String: Double] = [:]
        for txn in summaryExpenseMonthTransactions {
            let amount = viewModel.resolvedTransactionAmount(txn)
            if txn.tags.isEmpty {
                totals["Untagged", default: 0] += amount
            } else {
                for tag in txn.tags {
                    totals[tag, default: 0] += amount
                }
            }
        }
        return totals.map { (tag: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    private var tagBreakdownCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Spending by Tag", systemImage: "tag")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 14)

            let items = tagSpending
            if items.isEmpty {
                emptyPlaceholder(message: "No expenses this month")
            } else {
                let maxAmount = items.map(\.amount).max() ?? 1
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        tagRow(
                            tag: item.tag,
                            amount: item.amount,
                            maxAmount: maxAmount,
                            color: Self.tagBarColors[index % Self.tagBarColors.count],
                            onTap: { openTagDrilldown(tag: item.tag) }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func tagRow(tag: String, amount: Double, maxAmount: Double, color: Color, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tag)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 8)

                    Spacer()
                    Text(summaryIntegerCurrency(amount))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Self.expenseRed)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                GeometryReader { geo in
                    let fraction = maxAmount > 0 ? amount / maxAmount : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color)
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(height: 8)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3) Forecast vs Actual

    private var forecastComparisons: [(forecast: Forecast, expected: Double, actual: Double)] {
        let occurrences = viewModel.expectedForecastOccurrences(month: filterMonth, year: filterYear)

        var expectedByForecast: [UUID: Double] = [:]
        for occ in occurrences {
            expectedByForecast[occ.forecast.id, default: 0] += occ.forecast.amount
        }

        var actualByForecast: [UUID: Double] = [:]
        for txn in recordedMonthTransactions {
            guard let fid = txn.forecastID else { continue }
            actualByForecast[fid, default: 0] += viewModel.resolvedTransactionAmount(txn)
        }

        let allIDs = Set(expectedByForecast.keys).union(actualByForecast.keys)
        var results: [(forecast: Forecast, expected: Double, actual: Double)] = []
        for id in allIDs {
            guard let forecast = viewModel.forecasts[id] else { continue }
            let expected = expectedByForecast[id] ?? 0
            let actual = actualByForecast[id] ?? 0
            results.append((forecast: forecast, expected: expected, actual: actual))
        }
        return results.sorted { $0.expected > $1.expected }
    }

    private var forecastComparisonCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Forecast vs Actual", systemImage: "chart.bar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 14)

            let items = forecastComparisons
            if items.isEmpty {
                emptyPlaceholder(message: "No forecasts for this month")
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        forecastRow(item: item, onTap: { openForecastDrilldown(forecastID: item.forecast.id) })
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func forecastRow(item: (forecast: Forecast, expected: Double, actual: Double), onTap: @escaping () -> Void) -> some View {
        let isIncome = item.forecast.type == .income
        let maxVal = max(item.expected, item.actual, 1)
        let expectedFraction = item.expected / maxVal
        let actualFraction = item.actual / maxVal
        let overBudget = !isIncome && item.actual > item.expected && item.expected > 0
        let underBudget = isIncome && item.actual < item.expected && item.expected > 0

        return Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.forecast.name.isEmpty ? "Untitled" : item.forecast.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    if overBudget {
                        Text("Over")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Self.expenseRed))
                    } else if underBudget {
                        Text("Under")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange))
                    }

                    Text(isIncome ? "Income" : "Expense")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 5) {
                    forecastBarRow(
                        label: "Expected",
                        amount: item.expected,
                        fraction: expectedFraction,
                        color: Self.forecastExpectedColor
                    )
                    forecastBarRow(
                        label: "Actual",
                        amount: item.actual,
                        fraction: actualFraction,
                        color: overBudget ? Self.expenseRed : Self.forecastActualColor
                    )
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func forecastBarRow(label: String, amount: Double, fraction: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: max(4, geo.size.width * fraction))
            }
            .frame(height: 10)

            Text(summaryIntegerCurrency(amount))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 90, alignment: .trailing)
        }
    }

    // MARK: - Shared helpers

    private func emptyPlaceholder(message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundStyle(.quaternary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func summaryIntegerCurrency(_ amount: Double) -> String {
        viewModel.formatFinancialCurrencyUnsigned(amount.rounded())
    }

    private func openTagDrilldown(tag: String) {
        let transactions = summaryExpenseMonthTransactions.filter { txn in
            if tag == "Untagged" {
                return txn.tags.isEmpty
            }
            return txn.tags.contains(tag)
        }
        let title = tag == "Untagged" ? "Transactions · Untagged" : "Transactions · #\(tag)"
        drilldown = TransactionDrilldown(
            title: title,
            transactions: sortDrilldownTransactions(transactions),
            showTransactionTags: false
        )
    }

    private func openForecastDrilldown(forecastID: UUID) {
        guard let forecast = viewModel.forecasts[forecastID] else { return }
        let transactions = recordedMonthTransactions.filter { $0.forecastID == forecastID }
        let name = forecast.name.isEmpty ? "Untitled" : forecast.name
        drilldown = TransactionDrilldown(
            title: "Transactions · \(name)",
            transactions: sortDrilldownTransactions(transactions),
            showTransactionTags: true
        )
    }

    private func sortDrilldownTransactions(_ transactions: [FinancialTransaction]) -> [FinancialTransaction] {
        transactions.sorted { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type == .expense
            }
            let lhsAmount = viewModel.resolvedTransactionAmount(lhs)
            let rhsAmount = viewModel.resolvedTransactionAmount(rhs)
            if lhsAmount != rhsAmount {
                return lhsAmount > rhsAmount
            }
            return lhs.date > rhs.date
        }
    }

    // MARK: - Colors

    private static let incomeGreen = Color(red: 0.20, green: 0.56, blue: 0.46)
    private static let expenseRed = Color(red: 0.78, green: 0.30, blue: 0.34)
    private static let forecastExpectedColor = Color(red: 0.45, green: 0.55, blue: 0.72)
    private static let forecastActualColor = Color(red: 0.48, green: 0.40, blue: 0.72)

    private static let tagBarColors: [Color] = [
        Color(red: 0.35, green: 0.55, blue: 0.82),
        Color(red: 0.62, green: 0.42, blue: 0.72),
        Color(red: 0.85, green: 0.52, blue: 0.35),
        Color(red: 0.30, green: 0.65, blue: 0.55),
        Color(red: 0.75, green: 0.38, blue: 0.52),
        Color(red: 0.50, green: 0.60, blue: 0.40),
        Color(red: 0.68, green: 0.55, blue: 0.35),
        Color(red: 0.42, green: 0.48, blue: 0.70),
    ]
}

private struct TransactionDrilldown: Identifiable {
    let id = UUID()
    let title: String
    let transactions: [FinancialTransaction]
    /// Tags are redundant when drilling down from a tag row (same tag on every line).
    var showTransactionTags: Bool
}

private struct SummaryTransactionsDrilldownView: View {
    @ObservedObject var viewModel: KommitViewModel
    let payload: TransactionDrilldown
    @Environment(\.dismiss) private var dismiss

    /// Fixed width so tag pills line up vertically across forecast drilldown rows.
    private static let tagColumnWidth: CGFloat = 140

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(payload.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            if payload.transactions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No transactions")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(payload.transactions) { transaction in
                            row(transaction)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 420)
        .onExitCommand { dismiss() }
    }

    private func row(_ transaction: FinancialTransaction) -> some View {
        HStack(alignment: .center, spacing: 12) {
            let resolvedAmount = viewModel.resolvedTransactionAmount(transaction)
            Text(Self.dateFormatter.string(from: transaction.date))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(transaction.name.isEmpty ? "Untitled" : transaction.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if payload.showTransactionTags {
                Group {
                    if transaction.tags.isEmpty {
                        Color.clear
                    } else {
                        FinancialMetadataStrip(items: transaction.tags, width: Self.tagColumnWidth)
                    }
                }
                .frame(width: Self.tagColumnWidth, alignment: .leading)
            }

            Text(transaction.type == .income ? "+\(viewModel.formatFinancialCurrencyUnsigned(resolvedAmount))" : "-\(viewModel.formatFinancialCurrencyUnsigned(resolvedAmount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(transaction.type == .income ? .green : .primary)
                .frame(minWidth: 100, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
