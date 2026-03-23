import Foundation

// MARK: - Recording / occurrence helpers

package enum FinancialScheduling {
    /// First calendar day that is a weekday (Mon–Fri), on or after `date` (using `calendar.startOfDay`).
    package static func firstWorkingDateOnOrAfter(_ date: Date, calendar: Calendar = .current) -> Date {
        var d = calendar.startOfDay(for: date)
        while calendar.isDateInWeekend(d) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return d
    }

    /// Picks the occurrence date from `instances` that matches `stored` on the same calendar day, if any.
    package static func matchingOccurrence(in instances: [Date], forStoredDueDate stored: Date, calendar: Calendar = .current) -> Date? {
        instances.first { calendar.isDate($0, inSameDayAs: stored) }
    }

    /// Builds a sorted list of recurrence instances around a **view** month (not “today”), for pickers.
    package static func recurrenceInstances(
        for entry: FinancialEntry,
        centerMonth: Int,
        centerYear: Int,
        monthOffsetRange: ClosedRange<Int> = -4...4,
        calendar: Calendar = .current
    ) -> [Date] {
        guard var rec = entry.recurrence else { return [entry.createdAt] }
        rec.startDate = entry.createdAt

        var results: [Date] = []
        for offset in monthOffsetRange {
            var m = centerMonth + offset
            var y = centerYear
            while m < 1 {
                m += 12
                y -= 1
            }
            while m > 12 {
                m -= 12
                y += 1
            }
            results.append(contentsOf: rec.occurrences(in: m, year: y, calendar: calendar))
        }
        return results.sorted()
    }
}
