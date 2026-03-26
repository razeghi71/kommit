import Foundation

/// One scheduled occurrence on the calendar (paid or unpaid).
package struct FinanceCalendarDueLine: Identifiable, Equatable {
    package let id: String
    package let scheduled: ScheduledTransaction
    /// Scheduled occurrence due date; the column day is the due date when unpaid, or the paid-on date when paid.
    package let occurrenceDueDate: Date
    package let isPaid: Bool
    /// Date the payment was recorded (`FinancialTransaction.date`), when known.
    package let paidRecordedDate: Date?

    package init(
        scheduled: ScheduledTransaction,
        occurrenceDueDate: Date,
        isPaid: Bool,
        paidRecordedDate: Date? = nil
    ) {
        self.scheduled = scheduled
        self.occurrenceDueDate = occurrenceDueDate
        self.isPaid = isPaid
        self.paidRecordedDate = paidRecordedDate
        self.id = "\(scheduled.id.uuidString)|\(occurrenceDueDate.timeIntervalSinceReferenceDate)"
    }
}

package struct FinanceCalendarDayColumn: Identifiable {
    package var id: Date { displayDayStart }
    package let displayDayStart: Date
    /// Balance at the start of this calendar day (after prior days’ activity).
    package let startOfDayBalance: Double
    /// Balance after applying that day’s expected income (`startOfDayBalance + incomeTotal`).
    package let inBalanceAfterIncome: Double
    /// Unpaid income only (used for balance and summary).
    package let incomeTotal: Double
    package let incomeLines: [FinanceCalendarDueLine]
    package let expenseLines: [FinanceCalendarDueLine]
    /// Unpaid expenses only (used for balance and summary).
    package let expenseTotal: Double
    package let endOfDayBalance: Double
}

package enum FinanceCalendarProjection {
    /// Builds one column per calendar day from `rangeStart` through `rangeEnd` (start-of-day normalized).
    /// **Unpaid** lines sit on the due day; **paid** lines sit on the payment day (`paidRecordedOn`) when it falls in the window, else on the due day. **Unpaid** amounts drive balances.
    /// `startingBalanceAtTodayStart` is the balance at the **start** of `today`’s calendar day; earlier columns are
    /// back-filled so the running balance matches that anchor.
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

        for (scheduled, dueDate) in allDues {
            let dueDay = calendar.startOfDay(for: dueDate)
            let paid = isPaid(scheduled.id, dueDate)
            let recorded = paid ? paidRecordedOn(scheduled.id, dueDate) : nil

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
                paidRecordedDate: recorded
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
            let startOfDayBalance = balance
            let inBalanceAfterIncome = startOfDayBalance + incomeTotal
            balance = inBalanceAfterIncome - expenseTotal
            let sorted = sortedBucket(bucket)

            columns.append(
                FinanceCalendarDayColumn(
                    displayDayStart: dayCursor,
                    startOfDayBalance: startOfDayBalance,
                    inBalanceAfterIncome: inBalanceAfterIncome,
                    incomeTotal: incomeTotal,
                    incomeLines: sorted.income,
                    expenseLines: sorted.expense,
                    expenseTotal: expenseTotal,
                    endOfDayBalance: balance
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
