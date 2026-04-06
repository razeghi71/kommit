import Foundation

/// Shared surface for commitment/forecast occurrence iteration (`recurrence` + anchor date).
private protocol FinancialOccurrenceSource {
    var recurrence: Recurrence? { get }
    var createdAt: Date { get }
}

extension Commitment: FinancialOccurrenceSource {}
extension Forecast: FinancialOccurrenceSource {}

@MainActor
extension KommitViewModel {
    // MARK: - Finances CRUD

    package func addCommitment(_ commitment: Commitment) {
        commitments[commitment.id] = commitment
        isDirty = true
    }

    package func updateCommitment(_ commitment: Commitment) {
        commitments[commitment.id] = commitment
        isDirty = true
    }

    package func deleteCommitment(_ id: UUID) {
        commitments.removeValue(forKey: id)
        isDirty = true
    }

    package func addForecast(_ forecast: Forecast) {
        forecasts[forecast.id] = forecast
        isDirty = true
    }

    package func updateForecast(_ forecast: Forecast) {
        forecasts[forecast.id] = forecast
        isDirty = true
    }

    package func deleteForecast(_ id: UUID) {
        forecasts.removeValue(forKey: id)
        isDirty = true
    }

    package func addFinancialTransaction(_ transaction: FinancialTransaction) {
        financialTransactions[transaction.id] = transaction
        isDirty = true
    }

    package func updateFinancialTransaction(_ transaction: FinancialTransaction) {
        financialTransactions[transaction.id] = transaction
        isDirty = true
    }

    package func deleteFinancialTransaction(_ id: UUID) {
        financialTransactions.removeValue(forKey: id)
        isDirty = true
    }

    package func upsertFinanceAccount(_ account: FinanceAccount) {
        if let i = financeAccounts.firstIndex(where: { $0.id == account.id }) {
            financeAccounts[i] = account
        } else {
            financeAccounts.append(account)
        }
        isDirty = true
    }

    package func removeFinanceAccount(id: UUID) {
        financeAccounts.removeAll { $0.id == id }
        isDirty = true
    }

    package func removeFinanceAccounts(at offsets: IndexSet) {
        financeAccounts.remove(atOffsets: offsets)
        isDirty = true
    }

    // MARK: - Finances Queries

    package func transactionsForMonth(month: Int, year: Int, calendar: Calendar = .current) -> [FinancialTransaction] {
        financialTransactions.values.filter { txn in
            let comps = calendar.dateComponents([.year, .month], from: txn.date)
            return comps.year == year && comps.month == month
        }.sorted { $0.date < $1.date }
    }

    package func recordedTransactionsForMonth(month: Int, year: Int, calendar: Calendar = .current) -> [FinancialTransaction] {
        transactionsForMonth(month: month, year: year, calendar: calendar)
            .filter(\.isRecorded)
    }

    /// Cash-flow view of a month: direct recorded transactions plus settlements.
    /// Deferred recorded transactions are excluded because their cash leaves on the later settlement date instead.
    package func cashTransactionsForMonth(month: Int, year: Int, calendar: Calendar = .current) -> [FinancialTransaction] {
        transactionsForMonth(month: month, year: year, calendar: calendar)
            .filter { txn in
                txn.isSettlement || (txn.isRecorded && txn.deferredTo == nil)
            }
    }

    package func commitments(ofType type: FinancialFlowType) -> [Commitment] {
        commitments.values.filter { $0.type == type }
            .sorted { $0.name < $1.name }
    }

    /// Expected (item, occurrence date) pairs for planning rows in a calendar month.
    private func expectedOccurrences<Item: FinancialOccurrenceSource>(
        forItems items: some Sequence<Item>,
        month: Int,
        year: Int,
        calendar: Calendar
    ) -> [(item: Item, date: Date)] {
        var results: [(item: Item, date: Date)] = []
        for item in items {
            if var rec = item.recurrence {
                rec.startDate = item.createdAt
                let dates = rec.occurrences(in: month, year: year, calendar: calendar)
                for date in dates {
                    results.append((item: item, date: date))
                }
            } else {
                let comps = calendar.dateComponents([.year, .month], from: item.createdAt)
                if comps.year == year && comps.month == month {
                    results.append((item: item, date: item.createdAt))
                }
            }
        }
        return results.sorted { $0.date < $1.date }
    }

    /// Expected occurrences for every month intersecting `rangeStart...rangeEnd`, filtered to occurrence days in that range.
    private func expectedOccurrences<Item: FinancialOccurrenceSource>(
        forItems items: some Sequence<Item>,
        from rangeStart: Date,
        to rangeEnd: Date,
        calendar: Calendar
    ) -> [(item: Item, date: Date)] {
        let fromDay = calendar.startOfDay(for: rangeStart)
        let toDay = calendar.startOfDay(for: rangeEnd)
        guard fromDay <= toDay else { return [] }

        var year = calendar.component(.year, from: fromDay)
        var month = calendar.component(.month, from: fromDay)
        let endYear = calendar.component(.year, from: toDay)
        let endMonth = calendar.component(.month, from: toDay)

        var results: [(item: Item, date: Date)] = []
        while year < endYear || (year == endYear && month <= endMonth) {
            results.append(contentsOf: expectedOccurrences(forItems: items, month: month, year: year, calendar: calendar))
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }

        return results.filter { pair in
            let d = calendar.startOfDay(for: pair.date)
            return d >= fromDay && d <= toDay
        }.sorted { $0.date < $1.date }
    }

    /// Expected (commitment, occurrence date) pairs for a given month based on recurrence rules.
    package func expectedCommitmentOccurrences(month: Int, year: Int, calendar: Calendar = .current) -> [(commitment: Commitment, date: Date)] {
        expectedOccurrences(forItems: commitments.values, month: month, year: year, calendar: calendar)
            .map { (commitment: $0.item, date: $0.date) }
    }

    /// Expected commitment occurrences for every month intersecting `rangeStart...rangeEnd`, filtered to occurrence days in that range.
    package func expectedCommitmentOccurrences(from rangeStart: Date, to rangeEnd: Date, calendar: Calendar = .current) -> [(commitment: Commitment, date: Date)] {
        expectedOccurrences(forItems: commitments.values, from: rangeStart, to: rangeEnd, calendar: calendar)
            .map { (commitment: $0.item, date: $0.date) }
    }

    /// Expected (forecast, occurrence date) pairs for a given month.
    package func expectedForecastOccurrences(month: Int, year: Int, calendar: Calendar = .current) -> [(forecast: Forecast, date: Date)] {
        expectedOccurrences(forItems: forecasts.values, month: month, year: year, calendar: calendar)
            .map { (forecast: $0.item, date: $0.date) }
    }

    package func expectedForecastOccurrences(from rangeStart: Date, to rangeEnd: Date, calendar: Calendar = .current) -> [(forecast: Forecast, date: Date)] {
        expectedOccurrences(forItems: forecasts.values, from: rangeStart, to: rangeEnd, calendar: calendar)
            .map { (forecast: $0.item, date: $0.date) }
    }

    package func expectedCommitmentAmount(
        for commitmentID: UUID,
        dueDate: Date,
        calendar: Calendar = .current
    ) -> Double {
        return commitments[commitmentID]?.amount ?? 0
    }

    package func resolvedTransactionAmount(_ transaction: FinancialTransaction) -> Double {
        if transaction.isRecorded,
            let deferredTo = transaction.deferredTo,
            let commitment = commitments[deferredTo.commitmentID] {
            return commitment.amount
        }
        return transaction.amount
    }

    /// Whether a settlement transaction already covers this commitment occurrence.
    package func isCommitmentOccurrencePaid(commitmentID: UUID, dueDate: Date, calendar: Calendar = .current) -> Bool {
        financialTransactions.values.contains { txn in
            guard txn.isSettlement, let settles = txn.settles else { return false }
            return settles.commitmentID == commitmentID && calendar.isDate(settles.dueDate, inSameDayAs: dueDate)
        }
    }

    /// One-off commitments past their due day and paid, or finite recurring series whose end is in the past and every occurrence was paid.
    package func commitmentIsFullyPaid(_ commitment: Commitment, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        let todayStart = calendar.startOfDay(for: now)

        guard var rec = commitment.recurrence else {
            let due = commitment.createdAt
            guard todayStart > calendar.startOfDay(for: due) else { return false }
            return isCommitmentOccurrencePaid(commitmentID: commitment.id, dueDate: due, calendar: calendar)
        }

        rec.startDate = commitment.createdAt

        switch rec.end {
        case .never:
            return false
        case .until(let untilDate):
            guard todayStart > calendar.startOfDay(for: untilDate) else { return false }
            let dates = Self.commitmentOccurrenceDatesThroughUntil(recurrence: rec, untilDate: untilDate, calendar: calendar)
            guard !dates.isEmpty else { return false }
            return dates.allSatisfy { isCommitmentOccurrencePaid(commitmentID: commitment.id, dueDate: $0, calendar: calendar) }
        case .count(let n):
            guard n > 0 else { return false }
            let dates = Self.commitmentOccurrenceDatesForCount(recurrence: rec, count: n, calendar: calendar)
            guard dates.count == n, let last = dates.last else { return false }
            guard todayStart > calendar.startOfDay(for: last) else { return false }
            return dates.allSatisfy { isCommitmentOccurrencePaid(commitmentID: commitment.id, dueDate: $0, calendar: calendar) }
        }
    }

    /// Settlement transaction for this commitment occurrence, if any.
    package func financialTransactionCoveringCommitmentOccurrence(
        commitmentID: UUID,
        dueDate: Date,
        calendar: Calendar = .current
    ) -> FinancialTransaction? {
        financialTransactions.values.first { txn in
            guard txn.isSettlement, let settles = txn.settles else { return false }
            return settles.commitmentID == commitmentID && calendar.isDate(settles.dueDate, inSameDayAs: dueDate)
        }
    }

    package func monthlySummary(month: Int, year: Int, calendar: Calendar = .current) -> (income: Double, expenses: Double, net: Double) {
        let transactions = cashTransactionsForMonth(month: month, year: year, calendar: calendar)
        let income = transactions.filter { $0.type == .income }.reduce(0) { $0 + resolvedTransactionAmount($1) }
        let expenses = transactions.filter { $0.type == .expense }.reduce(0) { $0 + resolvedTransactionAmount($1) }
        return (income: income, expenses: expenses, net: income - expenses)
    }

    package func allFinancialTags() -> [String] {
        let tags =
            commitments.values.flatMap(\.tags) + forecasts.values.flatMap(\.tags)
        let nonEmpty = tags.filter { !$0.isEmpty }
        return Array(Set(nonEmpty)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    package func allTransactionTags() -> [String] {
        let tags = financialTransactions.values.flatMap(\.tags).filter { !$0.isEmpty }
        return Array(Set(tags)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Shared tag source for all financial entities (transactions, commitments, forecasts).
    package func allFinanceTags() -> [String] {
        let tags = allFinancialTags() + allTransactionTags()
        return Array(Set(tags)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Occurrence dates from the recurrence anchor through the month of `untilDate` (inclusive), respecting `until` in `occurrences(in:year:)`.
    private static func commitmentOccurrenceDatesThroughUntil(
        recurrence: Recurrence,
        untilDate: Date,
        calendar: Calendar
    ) -> [Date] {
        let rec = recurrence
        guard let start = rec.startDate else { return [] }
        var y = calendar.component(.year, from: start)
        var m = calendar.component(.month, from: start)
        let endY = calendar.component(.year, from: untilDate)
        let endM = calendar.component(.month, from: untilDate)
        var out: [Date] = []
        while y < endY || (y == endY && m <= endM) {
            out.append(contentsOf: rec.occurrences(in: m, year: y, calendar: calendar))
            m += 1
            if m > 12 {
                m = 1
                y += 1
            }
        }
        return out.sorted()
    }

    /// First `count` chronological occurrence dates for a finite recurrence (`.count` end), walking month by month from the anchor.
    private static func commitmentOccurrenceDatesForCount(
        recurrence: Recurrence,
        count: Int,
        calendar: Calendar
    ) -> [Date] {
        let rec = recurrence
        guard let start = rec.startDate else { return [] }
        var y = calendar.component(.year, from: start)
        var m = calendar.component(.month, from: start)
        var out: [Date] = []
        var monthIterations = 0
        let maxMonths = 1200
        while out.count < count && monthIterations < maxMonths {
            let monthDates = rec.occurrences(in: m, year: y, calendar: calendar).sorted()
            for d in monthDates {
                if out.count >= count { break }
                out.append(d)
            }
            m += 1
            if m > 12 {
                m = 1
                y += 1
            }
            monthIterations += 1
        }
        return out
    }

}
