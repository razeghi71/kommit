import SwiftUI

// MARK: - Finances Sub-tabs

private enum FinancesTab: String, CaseIterable, Identifiable {
    case entries
    case transactions
    case summary
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .entries: "Entries"
        case .transactions: "Transactions"
        case .summary: "Summary"
        case .upcoming: "Upcoming"
        }
    }

    var icon: String {
        switch self {
        case .entries: "list.bullet.rectangle"
        case .transactions: "arrow.left.arrow.right"
        case .summary: "chart.pie"
        case .upcoming: "calendar"
        }
    }
}

// MARK: - Main Finances View

package struct FinancesView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var selectedTab: FinancesTab = .entries

    package var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 180)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ForEach(FinancesTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .frame(width: 16)
                        Text(tab.title)
                        Spacer()
                    }
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.1))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .entries:
            EntriesListView(viewModel: viewModel)
        case .transactions:
            TransactionsListView(viewModel: viewModel)
        case .summary:
            MonthlySummaryView(viewModel: viewModel)
        case .upcoming:
            UpcomingDuesView(viewModel: viewModel)
        }
    }
}

// MARK: - Entries List

private struct EntriesListView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var showingAddEntry = false
    @State private var editingEntry: FinancialEntry?
    @State private var filterType: FinancialEntryType?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            entriesTable
        }
        .sheet(isPresented: $showingAddEntry) {
            EntryEditorView(viewModel: viewModel, entry: nil)
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditorView(viewModel: viewModel, entry: entry)
        }
    }

    private var header: some View {
        HStack {
            Text("Financial Entries")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Picker("", selection: $filterType) {
                Text("All").tag(nil as FinancialEntryType?)
                Text("Income").tag(FinancialEntryType.income as FinancialEntryType?)
                Text("Expense").tag(FinancialEntryType.expense as FinancialEntryType?)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button {
                showingAddEntry = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var filteredEntries: [FinancialEntry] {
        viewModel.financialEntries.values
            .filter { entry in
                if let filter = filterType { return entry.type == filter }
                return true
            }
            .sorted { $0.name < $1.name }
    }

    private var entriesTable: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredEntries) { entry in
                    EntryRow(entry: entry, onEdit: { editingEntry = entry }, onDelete: {
                        viewModel.deleteFinancialEntry(entry.id)
                    })
                    Divider()
                }
            }
        }
    }
}

private struct EntryRow: View {
    let entry: FinancialEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name.isEmpty ? "Untitled" : entry.name)
                        .font(.system(size: 14, weight: .medium))
                    if !entry.isActive {
                        Text("Paused")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }

                Text(entry.recurrenceDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.type == .income ? "+\(formatAmount(entry.amount))" : "-\(formatAmount(entry.amount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(entry.type == .income ? .green : .primary)

            if !entry.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
                .frame(maxWidth: 160)
            }

            Menu {
                Button("Edit") { onEdit() }
                Button("Delete", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Entry Editor

// MARK: - Recurrence Preset (Google Calendar-style)

private enum RecurrencePreset: Hashable {
    case doesNotRepeat
    case daily
    case weeklyOnDay
    case monthlyOnDay
    case annuallyOnDate
    case everyWeekday
    case custom
}

private struct EntryEditorView: View {
    @ObservedObject var viewModel: DominoViewModel
    let entry: FinancialEntry?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: FinancialEntryType = .expense
    @State private var amount: String = ""
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var isActive: Bool = true
    @State private var eventDate: Date = Date()

    @State private var selectedPreset: RecurrencePreset = .doesNotRepeat
    @State private var customRecurrence: Recurrence?
    @State private var showCustomRecurrence = false
    @State private var previousPreset: RecurrencePreset = .doesNotRepeat

    var isEditing: Bool { entry != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
                .padding(16)
        }
        .frame(width: 480, height: 440)
        .onAppear { loadEntry() }
        .onChange(of: selectedPreset) { old, new in
            if new == .custom {
                previousPreset = old
                showCustomRecurrence = true
            }
        }
        .sheet(isPresented: $showCustomRecurrence, onDismiss: {
            if customRecurrence == nil && selectedPreset == .custom {
                selectedPreset = previousPreset
            }
        }) {
            CustomRecurrenceSheet(
                initial: customRecurrence ?? recurrenceForPreset(previousPreset),
                eventDate: eventDate,
                onSave: { rec in
                    customRecurrence = rec
                    showCustomRecurrence = false
                },
                onCancel: {
                    if customRecurrence == nil {
                        selectedPreset = previousPreset
                    }
                    showCustomRecurrence = false
                }
            )
        }
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit Entry" : "New Entry")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.borderless)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Name") {
                    TextField("e.g. Rent, Salary", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    LabeledContent("Type") {
                        Picker("", selection: $type) {
                            ForEach(FinancialEntryType.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    LabeledContent("Amount") {
                        HStack(spacing: 2) {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $amount)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TagInputField(
                        tags: $tags,
                        input: $tagInput,
                        suggestions: tagSuggestions
                    )
                }

                Toggle("Active", isOn: $isActive)

                Divider()

                DatePicker("Date", selection: $eventDate, displayedComponents: .date)

                recurrencePicker

                if selectedPreset == .custom, let rec = customRecurrence {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(rec.description)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Recurrence Picker (Google Calendar-style dropdown)

    private var recurrencePicker: some View {
        LabeledContent("Repeats") {
            Picker("", selection: $selectedPreset) {
                Text("Does not repeat").tag(RecurrencePreset.doesNotRepeat)
                Divider()
                Text("Daily").tag(RecurrencePreset.daily)
                Text(weeklyLabel).tag(RecurrencePreset.weeklyOnDay)
                Text(monthlyOnDayLabel).tag(RecurrencePreset.monthlyOnDay)
                Text(annuallyLabel).tag(RecurrencePreset.annuallyOnDate)
                Text("Every weekday (Monday to Friday)").tag(RecurrencePreset.everyWeekday)
                Divider()
                Text("Custom…").tag(RecurrencePreset.custom)
            }
        }
    }

    // MARK: - Dynamic preset labels based on eventDate

    private var eventWeekday: Weekday {
        let wd = Calendar.current.component(.weekday, from: eventDate)
        return Weekday.from(calendarWeekday: wd) ?? .monday
    }

    private var weeklyLabel: String {
        "Weekly on \(eventWeekday.shortName)"
    }

    private var eventMonthDay: Int {
        Calendar.current.component(.day, from: eventDate)
    }

    private var monthlyOnDayLabel: String {
        "Monthly on the \(daySuffix(eventMonthDay))"
    }

    private static let daySuffixMap: [Int: String] = [
        1: "1st", 2: "2nd", 3: "3rd", 21: "21st", 22: "22nd", 23: "23rd", 31: "31st"
    ]

    private func daySuffix(_ day: Int) -> String {
        Self.daySuffixMap[day] ?? "\(day)th"
    }

    private var annuallyLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return "Annually on \(formatter.string(from: eventDate))"
    }

    // MARK: - Build recurrence from preset

    private func recurrenceForPreset(_ preset: RecurrencePreset) -> Recurrence? {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: eventDate)
        let monthDay = comps.day ?? 1
        let month = comps.month ?? 1

        switch preset {
        case .doesNotRepeat:
            return nil
        case .daily:
            return .everyDay()
        case .weeklyOnDay:
            return .everyWeek(on: [eventWeekday])
        case .monthlyOnDay:
            return .everyMonth(day: monthDay)
        case .annuallyOnDate:
            return .everyYear(month: month, day: monthDay)
        case .everyWeekday:
            return .everyWeekday()
        case .custom:
            return customRecurrence
        }
    }

    private func buildRecurrence() -> Recurrence? {
        recurrenceForPreset(selectedPreset)
    }

    // MARK: - Detect preset from existing recurrence

    private func presetForRecurrence(_ rec: Recurrence?) -> RecurrencePreset {
        guard let rec else { return .doesNotRepeat }

        let wd = eventWeekday
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: eventDate)
        let day = comps.day ?? 1
        let month = comps.month ?? 1

        if rec.frequency == .daily && rec.interval == 1 && rec.end == .never
            && rec.byWeekday == nil && rec.byMonthDay == nil && rec.byMonth == nil {
            return .daily
        }

        if rec.frequency == .weekly && rec.interval == 1 && rec.byWeekday == [wd]
            && rec.end == .never && rec.byMonthDay == nil && rec.byMonth == nil {
            return .weeklyOnDay
        }

        if rec.frequency == .monthly && rec.interval == 1 && rec.byWeekday == nil
            && rec.byMonthDay == [day] && rec.end == .never && rec.byMonth == nil {
            return .monthlyOnDay
        }

        if rec.frequency == .yearly && rec.interval == 1 && rec.byMonth == month
            && rec.byMonthDay == [day] && rec.end == .never && rec.byWeekday == nil {
            return .annuallyOnDate
        }

        if rec.frequency == .weekly && rec.interval == 1
            && Set(rec.byWeekday ?? []) == Set([Weekday.monday, .tuesday, .wednesday, .thursday, .friday])
            && rec.end == .never && rec.byMonthDay == nil && rec.byMonth == nil {
            return .everyWeekday
        }

        return .custom
    }

    // MARK: - Load / Save

    private func loadEntry() {
        guard let entry else { return }
        name = entry.name
        type = entry.type
        amount = String(format: "%.2f", entry.amount)
        tags = entry.tags
        isActive = entry.isActive
        eventDate = entry.createdAt

        let preset = presetForRecurrence(entry.recurrence)
        selectedPreset = preset
        if preset == .custom {
            customRecurrence = entry.recurrence
        }
    }

    private func save() {
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        var recurrence = buildRecurrence()
        recurrence?.startDate = eventDate

        let saved = FinancialEntry(
            id: entry?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: amountValue,
            recurrence: recurrence,
            tags: tags,
            isActive: isActive,
            createdAt: eventDate
        )

        if isEditing {
            viewModel.updateFinancialEntry(saved)
        } else {
            viewModel.addFinancialEntry(saved)
        }
        dismiss()
    }

    private var tagSuggestions: [String] {
        let existingTags = viewModel.allFinancialTags()
        let selected = Set(tags.map { normalizedTagKey($0) })
        let query = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let base = existingTags.filter { !selected.contains(normalizedTagKey($0)) }
        guard !query.isEmpty else { return Array(base.prefix(8)) }

        return base
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(8)
            .map { $0 }
    }

    private func normalizedTagKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct TagInputField: View {
    @Binding var tags: [String]
    @Binding var input: String
    let suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.system(size: 12))
                                Button {
                                    removeTag(tag)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
            }

            TextField("Add tag and press Enter", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addTag(input)
                }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                addTag(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func addTag(_ rawTag: String) {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = normalizedTagKey(trimmed)
        guard !tags.contains(where: { normalizedTagKey($0) == key }) else {
            input = ""
            return
        }
        tags.append(trimmed)
        input = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { normalizedTagKey($0) == normalizedTagKey(tag) }
    }

    private func normalizedTagKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

// MARK: - Custom Recurrence Sheet (Google Calendar-style)

private enum RecurrenceEndMode: Hashable {
    case never
    case onDate
    case afterCount
}

private struct CustomRecurrenceSheet: View {
    let initial: Recurrence?
    let eventDate: Date
    let onSave: (Recurrence) -> Void
    let onCancel: () -> Void

    @State private var frequency: RecurrenceFrequency = .weekly
    @State private var interval: Int = 1
    @State private var selectedWeekdays: Set<Weekday> = []
    @State private var monthDay: Int = 1
    @State private var monthDayMode: MonthDayMode = .dayOfMonth
    @State private var nthOccurrence: Int = 1
    @State private var nthWeekday: Weekday = .monday
    @State private var yearMonth: Int = 1
    @State private var yearDay: Int = 1
    @State private var endMode: RecurrenceEndMode = .never
    @State private var endDate: Date = Date().addingTimeInterval(90 * 24 * 3600)
    @State private var endCount: Int = 13

    private enum MonthDayMode: String, CaseIterable {
        case dayOfMonth
        case weekdayOfMonth
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Custom recurrence")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                repeatEveryRow

                if frequency == .weekly {
                    weekdaySelector
                }

                if frequency == .monthly {
                    monthlySelector
                }

                if frequency == .yearly {
                    yearlySelector
                }

                endsSection
            }
            .padding(16)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.borderless)
                Button("Done") { onSave(buildRecurrence()) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 400, height: 420)
        .onAppear { loadInitial() }
    }

    private var repeatEveryRow: some View {
        LabeledContent("Repeat every") {
            HStack(spacing: 6) {
                Stepper("\(interval)", value: $interval, in: 1...999)
                    .frame(width: 100)
                Picker("", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { f in
                        Text(interval == 1 ? f.displayName.lowercased() : "\(f.displayName.lowercased())s").tag(f)
                    }
                }
                .frame(width: 100)
            }
        }
    }

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repeat on")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Button {
                        if selectedWeekdays.contains(day) && selectedWeekdays.count > 1 {
                            selectedWeekdays.remove(day)
                        } else {
                            selectedWeekdays.insert(day)
                        }
                    } label: {
                        Text(String(day.shortName.prefix(1)))
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 32, height: 32)
                            .background {
                                Circle()
                                    .fill(selectedWeekdays.contains(day) ? Color.accentColor : Color.primary.opacity(0.06))
                            }
                            .foregroundStyle(selectedWeekdays.contains(day) ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var monthlySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $monthDayMode) {
                Text("Day of month").tag(MonthDayMode.dayOfMonth)
                Text("Nth weekday").tag(MonthDayMode.weekdayOfMonth)
            }
            .pickerStyle(.segmented)

            switch monthDayMode {
            case .dayOfMonth:
                LabeledContent("Day") {
                    Stepper("\(monthDay)", value: $monthDay, in: 1...31)
                        .frame(width: 100)
                }
            case .weekdayOfMonth:
                HStack(spacing: 8) {
                    Picker("", selection: $nthOccurrence) {
                        Text("First").tag(1)
                        Text("Second").tag(2)
                        Text("Third").tag(3)
                        Text("Fourth").tag(4)
                        Text("Last").tag(-1)
                    }
                    .frame(width: 100)
                    Picker("", selection: $nthWeekday) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Text(day.shortName).tag(day)
                        }
                    }
                }
            }
        }
    }

    private var yearlySelector: some View {
        HStack(spacing: 8) {
            Picker("Month", selection: $yearMonth) {
                let formatter = DateFormatter()
                ForEach(1...12, id: \.self) { m in
                    Text(formatter.monthSymbols[m - 1]).tag(m)
                }
            }
            .frame(width: 140)
            LabeledContent("Day") {
                Stepper("\(yearDay)", value: $yearDay, in: 1...31)
                    .frame(width: 100)
            }
        }
    }

    private var endsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ends")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("", selection: $endMode) {
                Text("Never").tag(RecurrenceEndMode.never)
                Text("On date").tag(RecurrenceEndMode.onDate)
                Text("After").tag(RecurrenceEndMode.afterCount)
            }
            .pickerStyle(.radioGroup)

            switch endMode {
            case .never:
                EmptyView()
            case .onDate:
                DatePicker("", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            case .afterCount:
                HStack(spacing: 4) {
                    Stepper("\(endCount)", value: $endCount, in: 1...999)
                        .frame(width: 100)
                    Text("occurrences")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func buildRecurrence() -> Recurrence {
        let end: RecurrenceEnd
        switch endMode {
        case .never: end = .never
        case .onDate: end = .until(endDate)
        case .afterCount: end = .count(endCount)
        }

        switch frequency {
        case .daily:
            return Recurrence(frequency: .daily, interval: interval, end: end)
        case .weekly:
            let days = selectedWeekdays.isEmpty ? [Weekday.monday] : Array(selectedWeekdays).sorted()
            return Recurrence(frequency: .weekly, interval: interval, byWeekday: days, end: end)
        case .monthly:
            switch monthDayMode {
            case .dayOfMonth:
                return Recurrence(frequency: .monthly, interval: interval, byMonthDay: [monthDay], end: end)
            case .weekdayOfMonth:
                return Recurrence(frequency: .monthly, interval: interval, byWeekday: [nthWeekday], byMonthDay: [nthOccurrence], end: end)
            }
        case .yearly:
            return Recurrence(frequency: .yearly, interval: interval, byMonthDay: [yearDay], byMonth: yearMonth, end: end)
        }
    }

    private func loadInitial() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day, .weekday], from: eventDate)
        let dayOfMonth = comps.day ?? 1

        guard let rec = initial else {
            frequency = .weekly
            interval = 1
            let wd = Weekday.from(calendarWeekday: comps.weekday ?? 2) ?? .monday
            selectedWeekdays = [wd]
            monthDay = dayOfMonth
            yearMonth = comps.month ?? 1
            yearDay = dayOfMonth
            return
        }

        frequency = rec.frequency
        interval = rec.interval

        if let weekdays = rec.byWeekday, !weekdays.isEmpty {
            selectedWeekdays = Set(weekdays)
        } else {
            let wd = Weekday.from(calendarWeekday: comps.weekday ?? 2) ?? .monday
            selectedWeekdays = [wd]
        }

        if let days = rec.byMonthDay, let first = days.first {
            if rec.frequency == .monthly && rec.byWeekday != nil {
                monthDayMode = .weekdayOfMonth
                nthOccurrence = first
                nthWeekday = rec.byWeekday?.first ?? .monday
            } else if rec.frequency == .yearly {
                yearDay = first
                monthDay = dayOfMonth
            } else {
                monthDayMode = .dayOfMonth
                monthDay = first
            }
        } else {
            monthDay = dayOfMonth
            yearDay = dayOfMonth
        }

        yearMonth = rec.byMonth ?? (comps.month ?? 1)

        switch rec.end {
        case .never:
            endMode = .never
        case .until(let date):
            endMode = .onDate
            endDate = date
        case .count(let n):
            endMode = .afterCount
            endCount = n
        }
    }
}

// MARK: - Transactions List

private struct TransactionsListView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var showingAddTransaction = false
    @State private var filterMonth: Int
    @State private var filterYear: Int
    @State private var editingTransaction: FinancialTransaction?

    init(viewModel: DominoViewModel) {
        self.viewModel = viewModel
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        _filterMonth = State(initialValue: comps.month ?? 1)
        _filterYear = State(initialValue: comps.year ?? 2026)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transactionsList
        }
        .sheet(isPresented: $showingAddTransaction) {
            TransactionEditorView(viewModel: viewModel, transaction: nil, defaultMonth: filterMonth, defaultYear: filterYear)
        }
        .sheet(item: $editingTransaction) { txn in
            TransactionEditorView(viewModel: viewModel, transaction: txn, defaultMonth: filterMonth, defaultYear: filterYear)
        }
    }

    private var header: some View {
        HStack {
            Text("Transactions")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            monthPicker

            Button {
                showingAddTransaction = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var monthPicker: some View {
        HStack(spacing: 4) {
            Button {
                previousMonth()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Text(monthYearLabel)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 120)

            Button {
                nextMonth()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }

    private var monthYearLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let comps = DateComponents(year: filterYear, month: filterMonth, day: 1)
        guard let date = Calendar.current.date(from: comps) else { return "" }
        return formatter.string(from: date)
    }

    private func previousMonth() {
        filterMonth -= 1
        if filterMonth < 1 {
            filterMonth = 12
            filterYear -= 1
        }
    }

    private func nextMonth() {
        filterMonth += 1
        if filterMonth > 12 {
            filterMonth = 1
            filterYear += 1
        }
    }

    private var filteredTransactions: [FinancialTransaction] {
        viewModel.transactionsForMonth(month: filterMonth, year: filterYear)
    }

    private var transactionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredTransactions.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                            .frame(height: 60)
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No transactions this month")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(filteredTransactions) { txn in
                        TransactionRow(
                            transaction: txn,
                            onEdit: { editingTransaction = txn },
                            onDelete: { viewModel.deleteFinancialTransaction(txn.id) }
                        )
                        Divider()
                    }
                }
            }
        }
    }
}

private struct TransactionRow: View {
    let transaction: FinancialTransaction
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.dateFormatter.string(from: transaction.date))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.name.isEmpty ? "Untitled" : transaction.name)
                    .font(.system(size: 14, weight: .medium))
                if !Calendar.current.isDate(transaction.dueDate, inSameDayAs: transaction.date) {
                    Text("Due: \(Self.dateFormatter.string(from: transaction.dueDate))")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(transaction.type == .income ? "+\(formatAmount(transaction.amount))" : "-\(formatAmount(transaction.amount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(transaction.type == .income ? .green : .primary)

            Menu {
                Button("Edit") { onEdit() }
                Button("Delete", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Transaction Editor

private struct TransactionEditorView: View {
    @ObservedObject var viewModel: DominoViewModel
    let transaction: FinancialTransaction?
    let defaultMonth: Int
    let defaultYear: Int
    var prefilledEntryID: UUID?
    var prefilledDueDate: Date?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: FinancialEntryType = .expense
    @State private var amount: String = ""
    @State private var date: Date = Date()
    @State private var selectedDueDate: Date = Date()
    @State private var note: String = ""
    @State private var selectedEntryID: UUID?

    var isEditing: Bool { transaction != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                form.padding(16)
            }
        }
        .frame(width: 460, height: selectedEntryID != nil ? 480 : 400)
        .onAppear { loadTransaction() }
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit Transaction" : "New Transaction")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.borderless)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("From Entry") {
                Picker("", selection: $selectedEntryID) {
                    Text("None (one-off)").tag(nil as UUID?)
                    ForEach(Array(viewModel.financialEntries.values).sorted { $0.name < $1.name }) { entry in
                        Text(entry.name).tag(entry.id as UUID?)
                    }
                }
                .onChange(of: selectedEntryID) { _, id in
                    guard let id, let entry = viewModel.financialEntries[id] else {
                        selectedDueDate = date
                        return
                    }
                    name = entry.name
                    type = entry.type
                    amount = String(format: "%.2f", entry.amount)
                    if !entry.isRecurring {
                        selectedDueDate = entry.createdAt
                    } else {
                        selectedDueDate = nearestInstance(for: entry)
                    }
                }
            }

            LabeledContent("Name") {
                TextField("e.g. Rent March", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                LabeledContent("Type") {
                    Picker("", selection: $type) {
                        ForEach(FinancialEntryType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                LabeledContent("Amount") {
                    HStack(spacing: 2) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $amount)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if selectedEntryID != nil {
                instancePicker
            }

            DatePicker("Payment date", selection: $date, displayedComponents: .date)

            LabeledContent("Note") {
                TextField("Optional", text: $note)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Instance picker

    private var instancePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let id = selectedEntryID, let entry = viewModel.financialEntries[id] {
                if entry.isRecurring {
                    let instances = computeInstances(for: entry)
                    LabeledContent("For occurrence") {
                        Picker("", selection: $selectedDueDate) {
                            ForEach(instances, id: \.self) { d in
                                Text(Self.instanceDateFormatter.string(from: d)).tag(d)
                            }
                        }
                    }
                } else {
                    HStack {
                        Text("For occurrence")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Self.instanceDateFormatter.string(from: entry.createdAt))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            }
        }
    }

    private func computeInstances(for entry: FinancialEntry) -> [Date] {
        FinancialScheduling.recurrenceInstances(
            for: entry,
            centerMonth: defaultMonth,
            centerYear: defaultYear,
            calendar: Calendar.current
        )
    }

    private func nearestInstance(for entry: FinancialEntry) -> Date {
        let instances = computeInstances(for: entry)
        let cal = Calendar.current
        guard !instances.isEmpty else { return Date() }
        let anchor = cal.date(from: DateComponents(year: defaultYear, month: defaultMonth, day: 15)) ?? Date()
        return instances.min(by: { abs($0.timeIntervalSince(anchor)) < abs($1.timeIntervalSince(anchor)) }) ?? instances[0]
    }

    private static let instanceDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    // MARK: - Load / Save

    private func loadTransaction() {
        if let txn = transaction {
            name = txn.name
            type = txn.type
            amount = String(format: "%.2f", txn.amount)
            date = txn.date
            selectedDueDate = txn.dueDate
            note = txn.note ?? ""
            selectedEntryID = txn.entryID
            if let entryID = txn.entryID, let entry = viewModel.financialEntries[entryID], entry.isRecurring {
                let instances = computeInstances(for: entry)
                if let resolved = FinancialScheduling.matchingOccurrence(
                    in: instances,
                    forStoredDueDate: txn.dueDate,
                    calendar: Calendar.current
                ) {
                    selectedDueDate = resolved
                }
            }
        } else if let entryID = prefilledEntryID {
            selectedEntryID = entryID
            if let entry = viewModel.financialEntries[entryID] {
                name = entry.name
                type = entry.type
                amount = String(format: "%.2f", entry.amount)
            }
            if let prefilled = prefilledDueDate {
                selectedDueDate = prefilled
                if let entry = viewModel.financialEntries[entryID], entry.isRecurring {
                    let instances = computeInstances(for: entry)
                    if let resolved = FinancialScheduling.matchingOccurrence(
                        in: instances,
                        forStoredDueDate: prefilled,
                        calendar: Calendar.current
                    ) {
                        selectedDueDate = resolved
                    }
                }
            }
        }
    }

    private func save() {
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0

        let saved = FinancialTransaction(
            id: transaction?.id ?? UUID(),
            entryID: selectedEntryID,
            name: name.trimmingCharacters(in: .whitespaces),
            amount: amountValue,
            type: type,
            date: date,
            dueDate: selectedDueDate,
            note: note.trimmingCharacters(in: .whitespaces).nilIfEmpty
        )

        if isEditing {
            viewModel.updateFinancialTransaction(saved)
        } else {
            viewModel.addFinancialTransaction(saved)
        }
        dismiss()
    }
}

// MARK: - Monthly Summary

private struct MonthlySummaryView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var month: Int
    @State private var year: Int

    init(viewModel: DominoViewModel) {
        self.viewModel = viewModel
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        _month = State(initialValue: comps.month ?? 1)
        _year = State(initialValue: comps.year ?? 2026)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summaryContent
                .padding(20)
        }
    }

    private var header: some View {
        HStack {
            Text("Monthly Summary")
                .font(.system(size: 16, weight: .semibold))
            Spacer()

            HStack(spacing: 4) {
                Button {
                    previousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Text(monthYearLabel)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 120)

                Button {
                    nextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
    }

    private var monthYearLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let comps = DateComponents(year: year, month: month, day: 1)
        guard let date = Calendar.current.date(from: comps) else { return "" }
        return formatter.string(from: date)
    }

    private func previousMonth() {
        month -= 1
        if month < 1 { month = 12; year -= 1 }
    }

    private func nextMonth() {
        month += 1
        if month > 12 { month = 1; year += 1 }
    }

    private var summary: (income: Double, expenses: Double, net: Double) {
        viewModel.monthlySummary(month: month, year: year)
    }

    private var summaryContent: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                summaryCard(title: "Income", amount: summary.income, color: .green)
                summaryCard(title: "Expenses", amount: summary.expenses, color: .red)
                summaryCard(title: "Net", amount: summary.net, color: summary.net >= 0 ? .green : .red)
            }

            Divider()

            // Expected vs actual for entries
            let dues = viewModel.expectedDues(month: month, year: year)

            if !dues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Expected vs Actual")
                        .font(.system(size: 14, weight: .semibold))

                    ForEach(dues, id: \.entry.id) { due in
                        let paid = viewModel.financialTransactions.values.contains { txn in
                            txn.entryID == due.entry.id &&
                            Calendar.current.isDate(txn.dueDate, inSameDayAs: due.date)
                        }
                        HStack {
                            Image(systemName: paid ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(paid ? .green : .secondary)
                                .font(.system(size: 12))

                            Text(due.entry.name)
                                .font(.system(size: 13))
                            Spacer()
                            Text(due.date, style: .date)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(formatAmount(due.entry.amount))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(due.entry.type == .income ? .green : .primary)
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private func summaryCard(title: String, amount: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(formatAmount(amount))
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.08))
        }
    }

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let prefix = amount >= 0 ? "$" : "-$"
        return prefix + (formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))")
    }
}

// MARK: - Upcoming Dues

private struct UpcomingDuesView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var month: Int
    @State private var year: Int
    @State private var pendingCustomRecord: PendingCustomRecord?
    @State private var customRecordDate: Date = Date()

    init(viewModel: DominoViewModel) {
        self.viewModel = viewModel
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        _month = State(initialValue: comps.month ?? 1)
        _year = State(initialValue: comps.year ?? 2026)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            duesList
        }
        .sheet(item: $pendingCustomRecord) { pending in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker(
                        "Record date",
                        selection: $customRecordDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)

                    Spacer()
                }
                .padding()
                .navigationTitle("Custom Record Date")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            pendingCustomRecord = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Record") {
                            recordTransaction(
                                for: pending.entry,
                                dueDate: pending.dueDate,
                                recordedOn: customRecordDate
                            )
                            pendingCustomRecord = nil
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Upcoming Dues")
                .font(.system(size: 16, weight: .semibold))
            Spacer()

            HStack(spacing: 4) {
                Button {
                    previousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Text(monthYearLabel)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 120)

                Button {
                    nextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
    }

    private var monthYearLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let comps = DateComponents(year: year, month: month, day: 1)
        guard let date = Calendar.current.date(from: comps) else { return "" }
        return formatter.string(from: date)
    }

    private func previousMonth() {
        month -= 1
        if month < 1 { month = 12; year -= 1 }
    }

    private func nextMonth() {
        month += 1
        if month > 12 { month = 1; year += 1 }
    }

    private var dues: [(entry: FinancialEntry, date: Date)] {
        viewModel.expectedDues(month: month, year: year)
    }


    private var duesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if dues.isEmpty {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 60)
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No dues this month")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(dues, id: \.entry.id) { due in
                        DueRow(
                            entry: due.entry,
                            date: due.date,
                            isPaid: isPaid(entryID: due.entry.id, dueDate: due.date),
                            onRecordFirstWorkingDate: {
                                let recordDate = FinancialScheduling.firstWorkingDateOnOrAfter(due.date)
                                recordTransaction(for: due.entry, dueDate: due.date, recordedOn: recordDate)
                            },
                            onRecordDueDate: {
                                recordTransaction(for: due.entry, dueDate: due.date, recordedOn: due.date)
                            },
                            onRecordToday: {
                                recordTransaction(for: due.entry, dueDate: due.date, recordedOn: Date())
                            },
                            onRecordCustomDate: {
                                customRecordDate = due.date
                                pendingCustomRecord = PendingCustomRecord(entry: due.entry, dueDate: due.date)
                            }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private func isPaid(entryID: UUID, dueDate: Date) -> Bool {
        viewModel.financialTransactions.values.contains { txn in
            txn.entryID == entryID &&
            Calendar.current.isDate(txn.dueDate, inSameDayAs: dueDate)
        }
    }

    private func recordTransaction(for entry: FinancialEntry, dueDate: Date, recordedOn: Date) {
        let txn = FinancialTransaction(
            entryID: entry.id,
            name: entry.name,
            amount: entry.amount,
            type: entry.type,
            date: recordedOn,
            dueDate: dueDate
        )
        viewModel.addFinancialTransaction(txn)
    }

}

private struct PendingCustomRecord: Identifiable {
    let id = UUID()
    let entry: FinancialEntry
    let dueDate: Date
}

private struct DueRow: View {
    let entry: FinancialEntry
    let date: Date
    let isPaid: Bool
    let onRecordFirstWorkingDate: () -> Void
    let onRecordDueDate: () -> Void
    let onRecordToday: () -> Void
    let onRecordCustomDate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.dateFormatter.string(from: date))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name.isEmpty ? "Untitled" : entry.name)
                    .font(.system(size: 14, weight: .medium))
                Text(entry.recurrenceDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.type == .income ? "+\(formatAmount(entry.amount))" : "-\(formatAmount(entry.amount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(entry.type == .income ? .green : .primary)

            if isPaid {
                Label("Paid", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Menu("Record") {
                    Button("Record on first working day on or after the due date") {
                        onRecordFirstWorkingDate()
                    }
                    Button("Record on due date") {
                        onRecordDueDate()
                    }
                    Button("Record on Today") {
                        onRecordToday()
                    }
                    Button("Record on custom date") {
                        onRecordCustomDate()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
