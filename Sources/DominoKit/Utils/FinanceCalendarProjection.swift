import Foundation

/// One commitment occurrence on the calendar (paid or unpaid).
package struct FinanceCalendarDueLine: Identifiable, Equatable {
    package let id: String
    package let commitment: Commitment
    /// Occurrence due date; the column day is the due day when unpaid, or the paid-on date when paid.
    package let occurrenceDueDate: Date
    package let isPaid: Bool
    /// Date the payment was recorded (`FinancialTransaction.date`), when known.
    package let paidRecordedDate: Date?
    /// Shown only on **today**: unpaid items whose due date is before today (not listed on the due day).
    package let isRollupOnToday: Bool

    package init(
        commitment: Commitment,
        occurrenceDueDate: Date,
        isPaid: Bool,
        paidRecordedDate: Date? = nil,
        isRollupOnToday: Bool = false
    ) {
        self.commitment = commitment
        self.occurrenceDueDate = occurrenceDueDate
        self.isPaid = isPaid
        self.paidRecordedDate = paidRecordedDate
        self.isRollupOnToday = isRollupOnToday
        let base = "\(commitment.id.uuidString)|\(occurrenceDueDate.timeIntervalSinceReferenceDate)"
        self.id = isRollupOnToday ? "\(base)|rollupToday" : base
    }
}

/// A forecast occurrence (always applied to projected balance; not dueable).
package struct FinanceCalendarForecastLine: Identifiable, Equatable {
    package let id: String
    package let forecast: Forecast
    package let occurrenceDate: Date

    package init(forecast: Forecast, occurrenceDate: Date) {
        self.forecast = forecast
        self.occurrenceDate = occurrenceDate
        self.id = "\(forecast.id.uuidString)|\(occurrenceDate.timeIntervalSinceReferenceDate)"
    }
}

/// A calendar day entry from a recorded transaction linked to a forecast (actual amount, one row per txn).
package struct FinanceCalendarForecastRealizedLine: Identifiable, Equatable {
    package var id: UUID { transaction.id }
    package let transaction: FinancialTransaction
    /// Present when the forecast still exists; otherwise use `transaction.name` in the UI.
    package let forecast: Forecast?

    package init(transaction: FinancialTransaction, forecast: Forecast?) {
        self.transaction = transaction
        self.forecast = forecast
    }
}

package struct FinanceCalendarDayColumn: Identifiable {
    package var id: Date { displayDayStart }
    package let displayDayStart: Date
    /// Balance at the start of this calendar day (after prior days’ activity).
    package let startOfDayBalance: Double
    /// Balance after applying that day’s expected income (`startOfDayBalance + incomeTotal`).
    package let inBalanceAfterIncome: Double
    /// Unpaid income due **this calendar day** only (not overdue rollup).
    package let incomeTotal: Double
    package let incomeLines: [FinanceCalendarDueLine]
    package let expenseLines: [FinanceCalendarDueLine]
    /// Unpaid expenses due **this calendar day** only (not overdue rollup).
    package let expenseTotal: Double
    /// Forecast income from projected occurrences (today and future only).
    package let forecastIncomeTotal: Double
    package let forecastExpenseTotal: Double
    package let forecastIncomeLines: [FinanceCalendarForecastLine]
    package let forecastExpenseLines: [FinanceCalendarForecastLine]
    /// Recorded transactions linked to a forecast (actual amounts), bucketed by payment `date`. Not included in balance / In–Out totals.
    package let forecastRealizedIncomeTotal: Double
    package let forecastRealizedExpenseTotal: Double
    package let forecastRealizedIncomeLines: [FinanceCalendarForecastRealizedLine]
    package let forecastRealizedExpenseLines: [FinanceCalendarForecastRealizedLine]
    package let endOfDayBalance: Double
    /// Unpaid amounts due before today, mirrored on today’s column (expenses reduce today’s start balance).
    package let overdueUnpaidExpenseTotal: Double
    package let overdueUnpaidIncomeTotal: Double
}

package enum FinanceCalendarProjection {
    /// Builds one column per calendar day from `rangeStart` through `rangeEnd` (start-of-day normalized).
    /// Unpaid lines sit on the due day when due today or later (or payment day when paid). Unpaid **past-due** items
    /// appear **only on today** with `isRollupOnToday`; today’s `startOfDayBalance` reflects overdue expenses and income.
    package static func buildColumns(
        calendar: Calendar,
        rangeStart: Date,
        rangeEnd: Date,
        today: Date,
        allCommitments: [(commitment: Commitment, date: Date)],
        allForecasts: [(forecast: Forecast, date: Date)],
        forecastLinkedTransactions: [FinancialTransaction],
        forecastsByID: [UUID: Forecast],
        isPaid: (UUID, Date) -> Bool,
        paidRecordedOn: (UUID, Date) -> Date?,
        startingBalanceAtTodayStart: Double
    ) -> [FinanceCalendarDayColumn] {
        let windowStart = calendar.startOfDay(for: rangeStart)
        let windowEnd = calendar.startOfDay(for: rangeEnd)
        let todayStart = calendar.startOfDay(for: today)
        guard windowStart <= windowEnd else { return [] }

        struct Bucket {
            var incomeTotalUnpaid: Double = 0
            var expenseTotalUnpaid: Double = 0
            var incomeLines: [FinanceCalendarDueLine] = []
            var expenseLines: [FinanceCalendarDueLine] = []
            var forecastIncomeTotal: Double = 0
            var forecastExpenseTotal: Double = 0
            var forecastIncomeLines: [FinanceCalendarForecastLine] = []
            var forecastExpenseLines: [FinanceCalendarForecastLine] = []
            var forecastRealizedIncomeTotal: Double = 0
            var forecastRealizedExpenseTotal: Double = 0
            var forecastRealizedIncomeLines: [FinanceCalendarForecastRealizedLine] = []
            var forecastRealizedExpenseLines: [FinanceCalendarForecastRealizedLine] = []
        }

        var buckets: [Date: Bucket] = [:]
        var overdueMirrorIncomeLines: [FinanceCalendarDueLine] = []
        var overdueMirrorExpenseLines: [FinanceCalendarDueLine] = []
        var overdueIncomeSum: Double = 0
        var overdueExpenseSum: Double = 0

        for (commitment, dueDate) in allCommitments {
            let dueDay = calendar.startOfDay(for: dueDate)
            let paid = isPaid(commitment.id, dueDate)
            let recorded = paid ? paidRecordedOn(commitment.id, dueDate) : nil

            // Unpaid past-due: only on today's column, not on the historical due date.
            if !paid, dueDay < todayStart, dueDay >= windowStart, dueDay <= windowEnd {
                let rollup = FinanceCalendarDueLine(
                    commitment: commitment,
                    occurrenceDueDate: dueDate,
                    isPaid: false,
                    paidRecordedDate: nil,
                    isRollupOnToday: true
                )
                switch commitment.type {
                case .income:
                    overdueIncomeSum += commitment.amount
                    overdueMirrorIncomeLines.append(rollup)
                case .expense:
                    overdueExpenseSum += commitment.amount
                    overdueMirrorExpenseLines.append(rollup)
                }
                continue
            }

            let bucketDay: Date
            if paid, let paidOn = recorded {
                let payDay = calendar.startOfDay(for: paidOn)
                if payDay >= windowStart, payDay <= windowEnd {
                    bucketDay = payDay
                } else if dueDay >= windowStart, dueDay <= windowEnd {
                    bucketDay = dueDay
                } else {
                    continue
                }
            } else {
                guard dueDay >= windowStart, dueDay <= windowEnd else { continue }
                bucketDay = dueDay
            }

            let line = FinanceCalendarDueLine(
                commitment: commitment,
                occurrenceDueDate: dueDate,
                isPaid: paid,
                paidRecordedDate: recorded,
                isRollupOnToday: false
            )

            var bucket = buckets[bucketDay] ?? Bucket()
            switch commitment.type {
            case .income:
                if !paid {
                    bucket.incomeTotalUnpaid += commitment.amount
                }
                bucket.incomeLines.append(line)
            case .expense:
                if !paid {
                    bucket.expenseTotalUnpaid += commitment.amount
                }
                bucket.expenseLines.append(line)
            }
            buckets[bucketDay] = bucket
        }

        // Occurrence days already covered by a linked transaction (match forecast + due day) so we skip projection and avoid double-counting.
        var forecastOccurrenceDaysWithRealized: Set<String> = []
        for txn in forecastLinkedTransactions {
            guard let fid = txn.forecastID else { continue }
            let dueDay = calendar.startOfDay(for: txn.dueDate)
            forecastOccurrenceDaysWithRealized.insert("\(fid.uuidString)|\(dueDay.timeIntervalSinceReferenceDate)")
        }

        for txn in forecastLinkedTransactions {
            guard let fid = txn.forecastID else { continue }
            let day = calendar.startOfDay(for: txn.date)
            guard day >= windowStart, day <= windowEnd else { continue }
            let forecast = forecastsByID[fid]
            let line = FinanceCalendarForecastRealizedLine(transaction: txn, forecast: forecast)
            var bucket = buckets[day] ?? Bucket()
            switch txn.type {
            case .income:
                bucket.forecastRealizedIncomeTotal += txn.amount
                bucket.forecastRealizedIncomeLines.append(line)
            case .expense:
                bucket.forecastRealizedExpenseTotal += txn.amount
                bucket.forecastRealizedExpenseLines.append(line)
            }
            buckets[day] = bucket
        }

        for (forecast, occDate) in allForecasts {
            let occDay = calendar.startOfDay(for: occDate)
            // Projections only for today and future; past days use realized transactions instead.
            guard occDay >= todayStart, occDay >= windowStart, occDay <= windowEnd else { continue }
            let realizedKey = "\(forecast.id.uuidString)|\(occDay.timeIntervalSinceReferenceDate)"
            if forecastOccurrenceDaysWithRealized.contains(realizedKey) { continue }
            let line = FinanceCalendarForecastLine(forecast: forecast, occurrenceDate: occDate)
            var bucket = buckets[occDay] ?? Bucket()
            switch forecast.type {
            case .income:
                bucket.forecastIncomeTotal += forecast.amount
                bucket.forecastIncomeLines.append(line)
            case .expense:
                bucket.forecastExpenseTotal += forecast.amount
                bucket.forecastExpenseLines.append(line)
            }
            buckets[occDay] = bucket
        }

        func sortedDueLines(_ lines: [FinanceCalendarDueLine]) -> [FinanceCalendarDueLine] {
            lines.sorted { lhs, rhs in
                let n1 = lhs.commitment.name.localizedCaseInsensitiveCompare(rhs.commitment.name)
                if n1 != .orderedSame { return n1 == .orderedAscending }
                return lhs.occurrenceDueDate < rhs.occurrenceDueDate
            }
        }

        func sortedForecastLines(_ lines: [FinanceCalendarForecastLine]) -> [FinanceCalendarForecastLine] {
            lines.sorted { lhs, rhs in
                let n1 = lhs.forecast.name.localizedCaseInsensitiveCompare(rhs.forecast.name)
                if n1 != .orderedSame { return n1 == .orderedAscending }
                return lhs.occurrenceDate < rhs.occurrenceDate
            }
        }

        var cumulativeUnpaidNetBeforeToday: Double = 0
        var cumulativeForecastNetBeforeToday: Double = 0
        var scan = windowStart
        while scan < todayStart {
            let bucket = buckets[scan] ?? Bucket()
            cumulativeUnpaidNetBeforeToday += bucket.incomeTotalUnpaid - bucket.expenseTotalUnpaid
            // Unrealized forecast projections only; realized forecast-linked txns are informational on the column.
            let forecastNet = bucket.forecastIncomeTotal - bucket.forecastExpenseTotal
            cumulativeForecastNetBeforeToday += forecastNet
            guard let next = calendar.date(byAdding: .day, value: 1, to: scan) else { break }
            scan = next
        }
        // Past-due unpaid is intentionally omitted from buckets. Do **not** fold it into cumulative here—that would
        // inflate early columns (e.g. show balance starting at S + overdue expenses). Instead, `balance` entering
        // today equals `startingBalanceAtTodayStart`, and we adjust today’s displayed start below.

        var balance = startingBalanceAtTodayStart - cumulativeUnpaidNetBeforeToday - cumulativeForecastNetBeforeToday

        func sortedRealizedForecastLines(_ lines: [FinanceCalendarForecastRealizedLine]) -> [FinanceCalendarForecastRealizedLine] {
            func title(_ line: FinanceCalendarForecastRealizedLine) -> String {
                if let f = line.forecast, !f.name.isEmpty { return f.name }
                if !line.transaction.name.isEmpty { return line.transaction.name }
                return ""
            }
            return lines.sorted { lhs, rhs in
                let n1 = title(lhs).localizedCaseInsensitiveCompare(title(rhs))
                if n1 != .orderedSame { return n1 == .orderedAscending }
                return lhs.transaction.date < rhs.transaction.date
            }
        }

        func sortedBucket(_ bucket: Bucket) -> (
            income: [FinanceCalendarDueLine],
            expense: [FinanceCalendarDueLine],
            fcInc: [FinanceCalendarForecastLine],
            fcExp: [FinanceCalendarForecastLine],
            frInc: [FinanceCalendarForecastRealizedLine],
            frExp: [FinanceCalendarForecastRealizedLine]
        ) {
            (
                sortedDueLines(bucket.incomeLines),
                sortedDueLines(bucket.expenseLines),
                sortedForecastLines(bucket.forecastIncomeLines),
                sortedForecastLines(bucket.forecastExpenseLines),
                sortedRealizedForecastLines(bucket.forecastRealizedIncomeLines),
                sortedRealizedForecastLines(bucket.forecastRealizedExpenseLines)
            )
        }

        var columns: [FinanceCalendarDayColumn] = []
        var dayCursor = windowStart

        while dayCursor <= windowEnd {
            let bucket = buckets[dayCursor] ?? Bucket()
            let incomeTotal = bucket.incomeTotalUnpaid
            let expenseTotal = bucket.expenseTotalUnpaid
            let fcIncTotal = bucket.forecastIncomeTotal
            let fcExpTotal = bucket.forecastExpenseTotal
            let isTodayCol = calendar.isDate(dayCursor, inSameDayAs: todayStart)

            let startOfDayBalance: Double
            if isTodayCol {
                // `balance` here is end-of-prior-day walk = startingBalanceAtTodayStart when prior days only used buckets.
                startOfDayBalance = startingBalanceAtTodayStart - overdueExpenseSum + overdueIncomeSum
            } else {
                startOfDayBalance = balance
            }

            let inBalanceAfterIncome = startOfDayBalance + incomeTotal + fcIncTotal
            balance = inBalanceAfterIncome - expenseTotal - fcExpTotal

            let sortedIncome: [FinanceCalendarDueLine]
            let sortedExpense: [FinanceCalendarDueLine]
            let sortedFcInc: [FinanceCalendarForecastLine]
            let sortedFcExp: [FinanceCalendarForecastLine]
            let sortedFrInc: [FinanceCalendarForecastRealizedLine]
            let sortedFrExp: [FinanceCalendarForecastRealizedLine]
            if isTodayCol {
                sortedIncome = sortedDueLines(overdueMirrorIncomeLines) + sortedDueLines(bucket.incomeLines)
                sortedExpense = sortedDueLines(overdueMirrorExpenseLines) + sortedDueLines(bucket.expenseLines)
                sortedFcInc = sortedForecastLines(bucket.forecastIncomeLines)
                sortedFcExp = sortedForecastLines(bucket.forecastExpenseLines)
                sortedFrInc = sortedRealizedForecastLines(bucket.forecastRealizedIncomeLines)
                sortedFrExp = sortedRealizedForecastLines(bucket.forecastRealizedExpenseLines)
            } else {
                let s = sortedBucket(bucket)
                sortedIncome = s.income
                sortedExpense = s.expense
                sortedFcInc = s.fcInc
                sortedFcExp = s.fcExp
                sortedFrInc = s.frInc
                sortedFrExp = s.frExp
            }

            columns.append(
                FinanceCalendarDayColumn(
                    displayDayStart: dayCursor,
                    startOfDayBalance: startOfDayBalance,
                    inBalanceAfterIncome: inBalanceAfterIncome,
                    incomeTotal: incomeTotal,
                    incomeLines: sortedIncome,
                    expenseLines: sortedExpense,
                    expenseTotal: expenseTotal,
                    forecastIncomeTotal: bucket.forecastIncomeTotal,
                    forecastExpenseTotal: bucket.forecastExpenseTotal,
                    forecastIncomeLines: sortedFcInc,
                    forecastExpenseLines: sortedFcExp,
                    forecastRealizedIncomeTotal: bucket.forecastRealizedIncomeTotal,
                    forecastRealizedExpenseTotal: bucket.forecastRealizedExpenseTotal,
                    forecastRealizedIncomeLines: sortedFrInc,
                    forecastRealizedExpenseLines: sortedFrExp,
                    endOfDayBalance: balance,
                    overdueUnpaidExpenseTotal: isTodayCol ? overdueExpenseSum : 0,
                    overdueUnpaidIncomeTotal: isTodayCol ? overdueIncomeSum : 0
                )
            )

            guard dayCursor < windowEnd,
                  let next = calendar.date(byAdding: .day, value: 1, to: dayCursor)
            else { break }
            dayCursor = next
        }

        return columns
    }
}
