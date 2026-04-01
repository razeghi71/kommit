import SwiftUI

// MARK: - Finance Summary View

struct FinanceSummaryView: View {
    @ObservedObject var viewModel: KommitViewModel
    @State private var filterMonth: Int
    @State private var filterYear: Int

    init(viewModel: KommitViewModel) {
        self.viewModel = viewModel
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        _filterMonth = State(initialValue: comps.month ?? 1)
        _filterYear = State(initialValue: comps.year ?? 2026)
    }

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    incomeExpenseCard
                    tagBreakdownCard
                    forecastComparisonCard
                }
                .padding(20)
            }
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

    private var cashMonthTransactions: [FinancialTransaction] {
        viewModel.cashTransactionsForMonth(month: filterMonth, year: filterYear)
    }

    private var recordedMonthTransactions: [FinancialTransaction] {
        viewModel.recordedTransactionsForMonth(month: filterMonth, year: filterYear)
    }

    private var totalIncome: Double {
        cashMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + viewModel.resolvedTransactionAmount($1) }
    }

    private var totalExpenses: Double {
        cashMonthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + viewModel.resolvedTransactionAmount($1) }
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
            Text("\(prefix)\(formatAmount(amount))")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2) Tag Breakdown

    private var tagSpending: [(tag: String, amount: Double)] {
        var totals: [String: Double] = [:]
        for txn in cashMonthTransactions where txn.type == .expense {
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
                            color: Self.tagBarColors[index % Self.tagBarColors.count]
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

    private func tagRow(tag: String, amount: Double, maxAmount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tag)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(formatAmount(amount))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Self.expenseRed)
            }

            GeometryReader { geo in
                let fraction = maxAmount > 0 ? amount / maxAmount : 0
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: max(4, geo.size.width * fraction))
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
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
                        forecastRow(item: item)
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

    private func forecastRow(item: (forecast: Forecast, expected: Double, actual: Double)) -> some View {
        let isIncome = item.forecast.type == .income
        let maxVal = max(item.expected, item.actual, 1)
        let expectedFraction = item.expected / maxVal
        let actualFraction = item.actual / maxVal
        let overBudget = !isIncome && item.actual > item.expected && item.expected > 0
        let underBudget = isIncome && item.actual < item.expected && item.expected > 0

        return VStack(alignment: .leading, spacing: 8) {
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

            Text(formatAmount(amount))
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

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let core = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "$" + core
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
