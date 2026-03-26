import Foundation

/// One scheduled occurrence on the calendar (paid or unpaid).
package struct FinanceCalendarDueLine: Identifiable, Equatable {
    package let id: String
    package let scheduled: ScheduledTransaction
    /// Scheduled occurrence due date; the column day is the due day when unpaid, or the paid-on date when paid.
    package let occurrenceDueDate: Date
    package let isPaid: Bool
    /// Date the payment was recorded (`FinancialTransaction.date`), when known.
    package let paidRecordedDate: Date?
    /// Shown only on **today**: unpaid items whose scheduled due date is before today (not listed on the due day).
    package let isRollupOnToday: Bool

    package init(
        scheduled: ScheduledTransaction,
        occurrenceDueDate: Date,
        isPaid: Bool,
        paidRecordedDate: Date? = nil,
        isRollupOnToday: Bool = false
    ) {
        self.scheduled = scheduled
        self.occurrenceDueDate = occurrenceDueDate
        self.isPaid = isPaid
        self.paidRecordedDate = paidRecordedDate
        self.isRollupOnToday = isRollupOnToday
        let base = "\(scheduled.id.uuidString)|\(occurrenceDueDate.timeIntervalSinceReferenceDate)"
        self.id = isRollupOnToday ? "\(base)|rollupToday" : base
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
        allDues: [(scheduled: ScheduledTransaction, date: Date)],
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
        }

        var buckets: [Date: Bucket] = [:]
        var overdueMirrorIncomeLines: [FinanceCalendarDueLine] = []
        var overdueMirrorExpenseLines: [FinanceCalendarDueLine] = []
        var overdueIncomeSum: Double = 0
        var overdueExpenseSum: Double = 0

        for (scheduled, dueDate) in allDues {
            let dueDay = calendar.startOfDay(for: dueDate)
            let paid = isPaid(scheduled.id, dueDate)
            let recorded = paid ? paidRecordedOn(scheduled.id, dueDate) : nil

            // Unpaid past-due: only on today's column, not on the historical due date.
            if !paid, dueDay < todayStart, dueDay >= windowStart, dueDay <= windowEnd {
                let rollup = FinanceCalendarDueLine(
                    scheduled: scheduled,
                    occurrenceDueDate: dueDate,
                    isPaid: false,
                    paidRecordedDate: nil,
                    isRollupOnToday: true
                )
                switch scheduled.type {
                case .income:
                    overdueIncomeSum += scheduled.amount
                    overdueMirrorIncomeLines.append(rollup)
                case .expense:
                    overdueExpenseSum += scheduled.amount
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
                scheduled: scheduled,
                occurrenceDueDate: dueDate,
                isPaid: paid,
                paidRecordedDate: recorded,
                isRollupOnToday: false
            )

            var bucket = buckets[bucketDay] ?? Bucket()
            switch scheduled.type {
            case .income:
                if !paid {
                    bucket.incomeTotalUnpaid += scheduled.amount
                }
                bucket.incomeLines.append(line)
            case .expense:
                if !paid {
                    bucket.expenseTotalUnpaid += scheduled.amount
                }
                bucket.expenseLines.append(line)
            }
            buckets[bucketDay] = bucket
        }

        func sortedLines(_ lines: [FinanceCalendarDueLine]) -> [FinanceCalendarDueLine] {
            lines.sorted { lhs, rhs in
                let n1 = lhs.scheduled.name.localizedCaseInsensitiveCompare(rhs.scheduled.name)
                if n1 != .orderedSame { return n1 == .orderedAscending }
                return lhs.occurrenceDueDate < rhs.occurrenceDueDate
            }
        }

        var cumulativeUnpaidNetBeforeToday: Double = 0
        var scan = windowStart
        while scan < todayStart {
            let bucket = buckets[scan] ?? Bucket()
            cumulativeUnpaidNetBeforeToday += bucket.incomeTotalUnpaid - bucket.expenseTotalUnpaid
            guard let next = calendar.date(byAdding: .day, value: 1, to: scan) else { break }
            scan = next
        }
        // Past-due unpaid is intentionally omitted from buckets. Do **not** fold it into cumulative here—that would
        // inflate early columns (e.g. show balance starting at S + overdue expenses). Instead, `balance` entering
        // today equals `startingBalanceAtTodayStart`, and we adjust today’s displayed start below.

        var balance = startingBalanceAtTodayStart - cumulativeUnpaidNetBeforeToday

        func sortedBucket(_ bucket: Bucket) -> (income: [FinanceCalendarDueLine], expense: [FinanceCalendarDueLine]) {
            (sortedLines(bucket.incomeLines), sortedLines(bucket.expenseLines))
        }

        var columns: [FinanceCalendarDayColumn] = []
        var dayCursor = windowStart

        while dayCursor <= windowEnd {
            let bucket = buckets[dayCursor] ?? Bucket()
            let incomeTotal = bucket.incomeTotalUnpaid
            let expenseTotal = bucket.expenseTotalUnpaid
            let isTodayCol = calendar.isDate(dayCursor, inSameDayAs: todayStart)

            let startOfDayBalance: Double
            if isTodayCol {
                // `balance` here is end-of-prior-day walk = startingBalanceAtTodayStart when prior days only used buckets.
                startOfDayBalance = startingBalanceAtTodayStart - overdueExpenseSum + overdueIncomeSum
            } else {
                startOfDayBalance = balance
            }

            let inBalanceAfterIncome = startOfDayBalance + incomeTotal
            balance = inBalanceAfterIncome - expenseTotal

            let sortedIncome: [FinanceCalendarDueLine]
            let sortedExpense: [FinanceCalendarDueLine]
            if isTodayCol {
                sortedIncome = sortedLines(overdueMirrorIncomeLines) + sortedLines(bucket.incomeLines)
                sortedExpense = sortedLines(overdueMirrorExpenseLines) + sortedLines(bucket.expenseLines)
            } else {
                let s = sortedBucket(bucket)
                sortedIncome = s.income
                sortedExpense = s.expense
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
