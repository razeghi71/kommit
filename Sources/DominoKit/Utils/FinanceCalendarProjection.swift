import Foundation

/// One unpaid scheduled occurrence shown in the calendar (income or expense).
package struct FinanceCalendarDueLine: Identifiable, Equatable {
    package let id: String
    package let scheduled: ScheduledTransaction
    /// Calendar occurrence date (actual due); may differ from the column when rolled up to today.
    package let occurrenceDueDate: Date

    package init(scheduled: ScheduledTransaction, occurrenceDueDate: Date) {
        self.scheduled = scheduled
        self.occurrenceDueDate = occurrenceDueDate
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
    package let incomeTotal: Double
    package let incomeLines: [FinanceCalendarDueLine]
    package let expenseLines: [FinanceCalendarDueLine]
    package let expenseTotal: Double
    package let endOfDayBalance: Double
}

package enum FinanceCalendarProjection {
    /// Past-due **expenses** roll onto `todayStart`; **income** only appears on its due day within the window (no past-income columns).
    package static func buildColumns(
        calendar: Calendar,
        today: Date,
        horizonDays: Int,
        allDues: [(scheduled: ScheduledTransaction, date: Date)],
        isPaid: (UUID, Date) -> Bool,
        startingBalance: Double
    ) -> [FinanceCalendarDayColumn] {
        let todayStart = calendar.startOfDay(for: today)
        guard horizonDays >= 0,
              let lastDayStart = calendar.date(byAdding: .day, value: horizonDays, to: todayStart)
        else { return [] }

        struct Bucket {
            var incomeTotal: Double = 0
            var incomeLines: [FinanceCalendarDueLine] = []
            var expenseLines: [FinanceCalendarDueLine] = []
        }

        var buckets: [Date: Bucket] = [:]

        for (scheduled, dueDate) in allDues {
            guard !isPaid(scheduled.id, dueDate) else { continue }
            let dueDay = calendar.startOfDay(for: dueDate)

            let displayDay: Date?
            switch scheduled.type {
            case .expense:
                if dueDay < todayStart {
                    displayDay = todayStart
                } else if dueDay <= lastDayStart {
                    displayDay = dueDay
                } else {
                    displayDay = nil
                }
            case .income:
                if dueDay >= todayStart && dueDay <= lastDayStart {
                    displayDay = dueDay
                } else {
                    displayDay = nil
                }
            }

            guard let displayDay else { continue }

            var bucket = buckets[displayDay] ?? Bucket()
            switch scheduled.type {
            case .income:
                bucket.incomeTotal += scheduled.amount
                bucket.incomeLines.append(FinanceCalendarDueLine(scheduled: scheduled, occurrenceDueDate: dueDate))
            case .expense:
                bucket.expenseLines.append(FinanceCalendarDueLine(scheduled: scheduled, occurrenceDueDate: dueDate))
            }
            buckets[displayDay] = bucket
        }

        func sortedLines(_ lines: [FinanceCalendarDueLine]) -> [FinanceCalendarDueLine] {
            lines.sorted { lhs, rhs in
                let n1 = lhs.scheduled.name.localizedCaseInsensitiveCompare(rhs.scheduled.name)
                if n1 != .orderedSame { return n1 == .orderedAscending }
                return lhs.occurrenceDueDate < rhs.occurrenceDueDate
            }
        }

        var columns: [FinanceCalendarDayColumn] = []
        var balance = startingBalance
        var dayCursor = todayStart

        for _ in 0 ... horizonDays {
            let bucket = buckets[dayCursor] ?? Bucket()
            let incomeTotal = bucket.incomeTotal
            let expenseTotal = bucket.expenseLines.reduce(0) { $0 + $1.scheduled.amount }
            let startOfDayBalance = balance
            let inBalanceAfterIncome = startOfDayBalance + incomeTotal
            balance = inBalanceAfterIncome - expenseTotal

            columns.append(
                FinanceCalendarDayColumn(
                    displayDayStart: dayCursor,
                    startOfDayBalance: startOfDayBalance,
                    inBalanceAfterIncome: inBalanceAfterIncome,
                    incomeTotal: incomeTotal,
                    incomeLines: sortedLines(bucket.incomeLines),
                    expenseLines: sortedLines(bucket.expenseLines),
                    expenseTotal: expenseTotal,
                    endOfDayBalance: balance
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
            dayCursor = next
        }

        return columns
    }
}
