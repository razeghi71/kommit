import Foundation

// MARK: - Income / expense (commitments, forecasts, and transactions)

package enum FinancialFlowType: String, Codable, CaseIterable {
    case income
    case expense

    var displayName: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        }
    }
}

// MARK: - Weekday

package enum Weekday: String, Codable, CaseIterable, Comparable {
    case monday = "MO"
    case tuesday = "TU"
    case wednesday = "WE"
    case thursday = "TH"
    case friday = "FR"
    case saturday = "SA"
    case sunday = "SU"

    var calendarWeekday: Int {
        switch self {
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        case .sunday: 1
        }
    }

    var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    package static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.calendarWeekday < rhs.calendarWeekday
    }
}

// MARK: - Weekday Occurrence (e.g. "2TU" = 2nd Tuesday, "-1FR" = last Friday)

package struct WeekdayOccurrence: Codable, Equatable, Hashable {
    let weekday: Weekday
    /// 1-5 for "nth", -1 to -5 for "nth from end". nil = every occurrence.
    let occurrence: Int?

    var displayName: String {
        if let occurrence {
            let prefix: String
            switch occurrence {
            case 1: prefix = "First"
            case 2: prefix = "Second"
            case 3: prefix = "Third"
            case 4: prefix = "Fourth"
            case 5: prefix = "Fifth"
            case -1: prefix = "Last"
            case -2: prefix = "Second to last"
            case -3: prefix = "Third to last"
            default: prefix = occurrence > 0 ? "\(occurrence)th" : "\(occurrence)th from end"
            }
            return "\(prefix) \(weekday.shortName)"
        }
        return weekday.shortName
    }
}

// MARK: - Recurrence Frequency

package enum RecurrenceFrequency: String, Codable, CaseIterable {
    case daily
    case weekly
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .daily: "Day"
        case .weekly: "Week"
        case .monthly: "Month"
        case .yearly: "Year"
        }
    }
}

// MARK: - Recurrence End

package enum RecurrenceEnd: Codable, Equatable {
    case never
    case count(Int)
    case until(Date)
}

// MARK: - Recurrence

/// iCal-inspired recurrence rule. Modeled after RFC 5545 RRULE.
package struct Recurrence: Codable, Equatable {
    var frequency: RecurrenceFrequency
    var interval: Int  // every N frequency units (1 = every, 2 = every other, etc.)
    var byWeekday: [Weekday]?            // for weekly: which days. for monthly: nth weekday
    var byMonthDay: [Int]?               // for monthly: which day(s) (1-31, or -1 for last)
    var byMonth: Int?                    // for yearly: which month (1-12)
    var end: RecurrenceEnd

    package static let never = Recurrence(
        frequency: .daily,
        interval: 1,
        end: .never
    )

    // MARK: - Presets

    package static func everyDay(interval: Int = 1) -> Recurrence {
        Recurrence(frequency: .daily, interval: interval, end: .never)
    }

    package static func everyWeekday() -> Recurrence {
        Recurrence(
            frequency: .weekly,
            interval: 1,
            byWeekday: [.monday, .tuesday, .wednesday, .thursday, .friday],
            end: .never
        )
    }

    package static func everyWeek(on days: [Weekday], interval: Int = 1) -> Recurrence {
        Recurrence(frequency: .weekly, interval: interval, byWeekday: days, end: .never)
    }

    package static func everyMonth(day: Int, interval: Int = 1) -> Recurrence {
        Recurrence(frequency: .monthly, interval: interval, byMonthDay: [day], end: .never)
    }

    package static func nthWeekdayOfMonth(_ occurrence: Int, weekday: Weekday, interval: Int = 1) -> Recurrence {
        Recurrence(
            frequency: .monthly,
            interval: interval,
            byWeekday: [weekday],
            byMonthDay: [occurrence],
            end: .never
        )
    }

    package static func everyYear(month: Int, day: Int, interval: Int = 1) -> Recurrence {
        Recurrence(
            frequency: .yearly,
            interval: interval,
            byMonthDay: [day],
            byMonth: month,
            end: .never
        )
    }

    // MARK: - Human-readable description

    var description: String {
        var parts: [String] = []

        switch frequency {
        case .daily:
            if interval == 1 {
                parts.append("Daily")
            } else {
                parts.append("Every \(interval) days")
            }

        case .weekly:
            if let days = byWeekday, !days.isEmpty {
                let dayNames = days.map(\.shortName).joined(separator: ", ")
                if interval == 1 {
                    parts.append("Every week on \(dayNames)")
                } else {
                    parts.append("Every \(interval) weeks on \(dayNames)")
                }
            } else {
                if interval == 1 {
                    parts.append("Weekly")
                } else {
                    parts.append("Every \(interval) weeks")
                }
            }

        case .monthly:
            if let days = byMonthDay, !days.isEmpty, byWeekday == nil {
                let dayNames = days.map { day in
                    if day == -1 { return "last day" }
                    return Self.daySuffix(day)
                }.joined(separator: ", ")
                if interval == 1 {
                    parts.append("Every month on the \(dayNames)")
                } else {
                    parts.append("Every \(interval) months on the \(dayNames)")
                }
            } else if let days = byMonthDay, let weekdays = byWeekday,
                      !days.isEmpty, !weekdays.isEmpty {
                // Nth weekday pattern: byMonthDay contains occurrence, byWeekday contains the day
                let occurrence = days[0]
                let weekday = weekdays[0]
                let wo = WeekdayOccurrence(weekday: weekday, occurrence: occurrence)
                if interval == 1 {
                    parts.append("Every month on the \(wo.displayName)")
                } else {
                    parts.append("Every \(interval) months on the \(wo.displayName)")
                }
            } else {
                if interval == 1 {
                    parts.append("Monthly")
                } else {
                    parts.append("Every \(interval) months")
                }
            }

        case .yearly:
            if let month = byMonth, let days = byMonthDay, !days.isEmpty {
                let monthName = Self.monthName(month)
                let day = days[0]
                if interval == 1 {
                    parts.append("Every year on \(monthName) \(Self.daySuffix(day))")
                } else {
                    parts.append("Every \(interval) years on \(monthName) \(Self.daySuffix(day))")
                }
            } else {
                if interval == 1 {
                    parts.append("Yearly")
                } else {
                    parts.append("Every \(interval) years")
                }
            }
        }

        if let start = startDate {
            let startFormatter = DateFormatter()
            startFormatter.dateFormat = "MMM d yyyy"
            startFormatter.locale = .autoupdatingCurrent
            parts.append(" starting from \(startFormatter.string(from: start))")
        }

        switch end {
        case .count(let n):
            parts.append(", \(n) times")
        case .until(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append(", until \(formatter.string(from: date))")
        case .never:
            break
        }

        return parts.joined()
    }

    // MARK: - Occurrence computation

    /// Compute all occurrence dates for this recurrence within a given month/year.
    func occurrences(in month: Int, year: Int, calendar: Calendar = .current) -> [Date] {
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        else { return [] }

        var results: [Date] = []
        var candidate = monthStart

        // Walk through each day of the month and check if it matches
        while candidate <= monthEnd {
            if matches(date: candidate, calendar: calendar) && !isBeforeStart(candidate, calendar: calendar) {
                if isWithinEnd(candidate) {
                    results.append(candidate)
                }
            }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
        }

        return results
    }

    /// Check if a specific date is an occurrence of this recurrence.
    func matches(date: Date, calendar: Calendar = .current) -> Bool {
        let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: date)

        switch frequency {
        case .daily:
            return matchesDailyInterval(date: date, calendar: calendar)

        case .weekly:
            guard let weekday = Weekday.from(calendarWeekday: comps.weekday ?? 0) else { return false }
            if let byWeekday = byWeekday {
                guard byWeekday.contains(weekday) else { return false }
            }
            return matchesWeeklyInterval(date: date, calendar: calendar)

        case .monthly:
            if let days = byMonthDay, byWeekday == nil {
                let day = comps.day ?? 0
                let lastDay = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
                let matchesDay = days.contains(where: { d in
                    if d > 0 { return d == day }
                    return (lastDay + d + 1) == day
                })
                guard matchesDay else { return false }
                return matchesMonthlyInterval(date: date, calendar: calendar)
            } else if let days = byMonthDay, let weekdays = byWeekday,
                      let occurrence = days.first, let targetWeekday = weekdays.first {
                // Nth weekday of month
                let dayOfWeek = Weekday.from(calendarWeekday: comps.weekday ?? 0)
                guard dayOfWeek == targetWeekday else { return false }
                let day = comps.day ?? 0
                let weekOfMonth = (day - 1) / 7 + 1
                if occurrence > 0 {
                    guard weekOfMonth == occurrence else { return false }
                } else {
                    let lastDay = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
                    let remainingDays = lastDay - day
                    let weeksFromEnd = remainingDays / 7 + 1
                    guard weeksFromEnd == -occurrence else { return false }
                }
                return matchesMonthlyInterval(date: date, calendar: calendar)
            }
            return matchesMonthlyInterval(date: date, calendar: calendar)

        case .yearly:
            if let month = byMonth {
                guard comps.month == month else { return false }
            }
            if let days = byMonthDay, !days.isEmpty {
                guard let day = comps.day, days.contains(day) else { return false }
            }
            return matchesYearlyInterval(date: date, calendar: calendar)
        }
    }

    // MARK: - Interval matching helpers

    private func matchesDailyInterval(date: Date, calendar: Calendar) -> Bool {
        guard interval > 1 else { return true }
        guard let start = startDate else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                            to: calendar.startOfDay(for: date)).day ?? 0
        return days >= 0 && days % interval == 0
    }

    private func matchesWeeklyInterval(date: Date, calendar: Calendar) -> Bool {
        guard interval > 1 else { return true }
        guard let start = startDate else { return true }
        let weeks = calendar.dateComponents([.weekOfYear], from: calendar.startOfDay(for: start),
                                             to: calendar.startOfDay(for: date)).weekOfYear ?? 0
        return weeks >= 0 && weeks % interval == 0
    }

    private func matchesMonthlyInterval(date: Date, calendar: Calendar) -> Bool {
        guard interval > 1 else { return true }
        guard let start = startDate else { return true }
        let startComps = calendar.dateComponents([.year, .month], from: start)
        let dateComps = calendar.dateComponents([.year, .month], from: date)
        let startMonths = (startComps.year ?? 0) * 12 + (startComps.month ?? 0)
        let dateMonths = (dateComps.year ?? 0) * 12 + (dateComps.month ?? 0)
        let diff = dateMonths - startMonths
        return diff >= 0 && diff % interval == 0
    }

    private func matchesYearlyInterval(date: Date, calendar: Calendar) -> Bool {
        guard interval > 1 else { return true }
        guard let start = startDate else { return true }
        let startYear = calendar.component(.year, from: start)
        let dateYear = calendar.component(.year, from: date)
        let diff = dateYear - startYear
        return diff >= 0 && diff % interval == 0
    }

    private func isBeforeStart(_ date: Date, calendar: Calendar) -> Bool {
        guard let start = startDate else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: start)
    }

    private func isWithinEnd(_ date: Date) -> Bool {
        switch end {
        case .never: return true
        case .count: return true // count-based needs occurrence tracking, not per-date check
        case .until(let untilDate): return date <= untilDate
        }
    }

    /// Anchor date for interval calculations. Set externally when creating the entry.
    var startDate: Date?

    // MARK: - Helpers

    private static func daySuffix(_ day: Int) -> String {
        switch day {
        case 1, 21, 31: return "\(day)st"
        case 2, 22: return "\(day)nd"
        case 3, 23: return "\(day)rd"
        default: return "\(day)th"
        }
    }

    private static func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.monthSymbols[safe: month - 1] ?? "Month \(month)"
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Weekday from Calendar weekday

extension Weekday {
    package static func from(calendarWeekday: Int) -> Weekday? {
        switch calendarWeekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}

// MARK: - Commitment (recurring; cleared by logging a transaction)

package struct Commitment: Identifiable, Codable, Equatable {
    package let id: UUID
    var name: String
    var type: FinancialFlowType
    var amount: Double
    var recurrence: Recurrence?
    var tags: [String]
    var isActive: Bool
    var createdAt: Date

    package init(
        id: UUID = UUID(),
        name: String = "",
        type: FinancialFlowType = .expense,
        amount: Double = 0,
        recurrence: Recurrence? = nil,
        tags: [String] = [],
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.amount = amount
        self.recurrence = recurrence
        self.tags = tags
        self.isActive = isActive
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case amount
        case recurrence
        case tags
        case category
        case isActive
        case createdAt
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(FinancialFlowType.self, forKey: .type) ?? .expense
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        recurrence = try container.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        if let decodedTags = try container.decodeIfPresent([String].self, forKey: .tags) {
            tags = Self.normalizedTags(from: decodedTags)
        } else {
            let legacyCategory = try container.decodeIfPresent(String.self, forKey: .category)
            tags = Self.normalizedTags(from: legacyCategory.map { [$0] } ?? [])
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(recurrence, forKey: .recurrence)
        try container.encode(Self.normalizedTags(from: tags), forKey: .tags)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
    }

    var isRecurring: Bool {
        recurrence != nil
    }

    private static let nonRecurringDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = .autoupdatingCurrent
        return f
    }()

    var recurrenceDescription: String {
        guard let recurrence else {
            return Self.nonRecurringDateFormatter.string(from: createdAt)
        }
        var r = recurrence
        if r.startDate == nil {
            r.startDate = createdAt
        }
        return r.description
    }

    private static func normalizedTags(from rawTags: [String]) -> [String] {
        FinancialModels.normalizedFinancialTags(from: rawTags)
    }
}

// MARK: - Forecast (recurring projection; not a due commitment)

package struct Forecast: Identifiable, Codable, Equatable {
    package let id: UUID
    var name: String
    var type: FinancialFlowType
    var amount: Double
    var recurrence: Recurrence?
    var tags: [String]
    var isActive: Bool
    var createdAt: Date

    package init(
        id: UUID = UUID(),
        name: String = "",
        type: FinancialFlowType = .expense,
        amount: Double = 0,
        recurrence: Recurrence? = nil,
        tags: [String] = [],
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.amount = amount
        self.recurrence = recurrence
        self.tags = tags
        self.isActive = isActive
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case amount
        case recurrence
        case tags
        case category
        case isActive
        case createdAt
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(FinancialFlowType.self, forKey: .type) ?? .expense
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        recurrence = try container.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        if let decodedTags = try container.decodeIfPresent([String].self, forKey: .tags) {
            tags = FinancialModels.normalizedFinancialTags(from: decodedTags)
        } else {
            let legacyCategory = try container.decodeIfPresent(String.self, forKey: .category)
            tags = FinancialModels.normalizedFinancialTags(from: legacyCategory.map { [$0] } ?? [])
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(recurrence, forKey: .recurrence)
        try container.encode(FinancialModels.normalizedFinancialTags(from: tags), forKey: .tags)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
    }

    var isRecurring: Bool {
        recurrence != nil
    }

    private static let nonRecurringDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = .autoupdatingCurrent
        return f
    }()

    var recurrenceDescription: String {
        guard let recurrence else {
            return Self.nonRecurringDateFormatter.string(from: createdAt)
        }
        var r = recurrence
        if r.startDate == nil {
            r.startDate = createdAt
        }
        return r.description
    }
}

// MARK: - Financial Transaction

package struct CommitmentOccurrenceRef: Codable, Equatable {
    var commitmentID: UUID
    var dueDate: Date

    package init(commitmentID: UUID, dueDate: Date) {
        self.commitmentID = commitmentID
        self.dueDate = dueDate
    }
}

package enum FinancialTransactionKind: String, Codable, CaseIterable {
    case recorded
    case settlement
}

package struct FinancialTransaction: Identifiable, Codable, Equatable {
    package let id: UUID
    var kind: FinancialTransactionKind
    var forecastID: UUID?
    /// Present on recorded transactions that should be rolled into a later bill occurrence.
    var deferredTo: CommitmentOccurrenceRef?
    /// Present on settlement transactions that clear a due bill occurrence.
    var settles: CommitmentOccurrenceRef?
    var name: String
    var amount: Double
    var type: FinancialFlowType
    /// The day this transaction itself happened.
    var date: Date
    var tags: [String]
    var note: String?

    package init(
        id: UUID = UUID(),
        kind: FinancialTransactionKind = .recorded,
        forecastID: UUID? = nil,
        deferredTo: CommitmentOccurrenceRef? = nil,
        settles: CommitmentOccurrenceRef? = nil,
        name: String = "",
        amount: Double = 0,
        type: FinancialFlowType = .expense,
        date: Date = Date(),
        tags: [String] = [],
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.forecastID = forecastID
        self.deferredTo = deferredTo
        self.settles = settles
        self.name = name
        self.amount = amount
        self.type = type
        self.date = date
        self.tags = Self.normalizedTags(from: tags)
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case forecastID
        case deferredTo
        case settles
        case name
        case amount
        case type
        case date
        case tags
        case note
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(FinancialTransactionKind.self, forKey: .kind) ?? .recorded
        forecastID = try container.decodeIfPresent(UUID.self, forKey: .forecastID)
        deferredTo = try container.decodeIfPresent(CommitmentOccurrenceRef.self, forKey: .deferredTo)
        settles = try container.decodeIfPresent(CommitmentOccurrenceRef.self, forKey: .settles)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        type = try container.decodeIfPresent(FinancialFlowType.self, forKey: .type) ?? .expense
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        tags = Self.normalizedTags(from: try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(forecastID, forKey: .forecastID)
        try container.encodeIfPresent(deferredTo, forKey: .deferredTo)
        try container.encodeIfPresent(settles, forKey: .settles)
        try container.encode(name, forKey: .name)
        if !(kind == .recorded && deferredTo != nil) {
            try container.encode(amount, forKey: .amount)
        }
        try container.encode(type, forKey: .type)
        try container.encode(date, forKey: .date)
        try container.encode(Self.normalizedTags(from: tags), forKey: .tags)
        try container.encodeIfPresent(note, forKey: .note)
    }

    var isRecorded: Bool { kind == .recorded }
    var isSettlement: Bool { kind == .settlement }

    private static func normalizedTags(from rawTags: [String]) -> [String] {
        FinancialModels.normalizedFinancialTags(from: rawTags)
    }
}

// MARK: - Shared tag normalization

private enum FinancialModels {
    static func normalizedFinancialTags(from rawTags: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for rawTag in rawTags {
            let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            normalized.append(trimmed)
        }
        return normalized
    }
}
