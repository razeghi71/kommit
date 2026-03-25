import SwiftUI

// MARK: - Finances Sub-tabs

private enum FinancesTab: String, CaseIterable, Identifiable {
    case scheduledTransactions
    case transactions
    case budgets
    case summary
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduledTransactions: "Scheduled"
        case .transactions: "Transactions"
        case .budgets: "Budgets"
        case .summary: "Summary"
        case .upcoming: "Upcoming"
        }
    }

    var icon: String {
        switch self {
        case .scheduledTransactions: "list.bullet.rectangle"
        case .transactions: "arrow.left.arrow.right"
        case .budgets: "wallet.bifold"
        case .summary: "chart.pie"
        case .upcoming: "calendar"
        }
    }
}

// MARK: - Main Finances View

package struct FinancesView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var selectedTab: FinancesTab = .scheduledTransactions

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
                    .contentShape(Rectangle())
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
        case .scheduledTransactions:
            ScheduledTransactionsListView(viewModel: viewModel)
        case .transactions:
            TransactionsListView(viewModel: viewModel)
        case .budgets:
            BudgetsListView(viewModel: viewModel)
        case .summary:
            MonthlySummaryView(viewModel: viewModel)
        case .upcoming:
            UpcomingDuesView(viewModel: viewModel)
        }
    }
}

// MARK: - Scheduled transactions list

private struct ScheduledTransactionsListView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var showingAddScheduledTransaction = false
    @State private var editingScheduledTransaction: ScheduledTransaction?
    @State private var filterType: ScheduledTransactionType?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            entriesTable
        }
        .sheet(isPresented: $showingAddScheduledTransaction) {
            ScheduledTransactionEditorView(viewModel: viewModel, scheduledTransaction: nil)
        }
        .sheet(item: $editingScheduledTransaction) { scheduled in
            ScheduledTransactionEditorView(viewModel: viewModel, scheduledTransaction: scheduled)
        }
    }

    private var header: some View {
        HStack {
            Text("Scheduled transactions")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Picker("", selection: $filterType) {
                Text("All").tag(nil as ScheduledTransactionType?)
                Text("Income").tag(ScheduledTransactionType.income as ScheduledTransactionType?)
                Text("Expense").tag(ScheduledTransactionType.expense as ScheduledTransactionType?)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button {
                showingAddScheduledTransaction = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var filteredEntries: [ScheduledTransaction] {
        viewModel.scheduledTransactions.values
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
                    ScheduledTransactionRow(scheduled: entry, onEdit: { editingScheduledTransaction = entry }, onDelete: {
                        viewModel.deleteScheduledTransaction(entry.id)
                    })
                    Divider()
                }
            }
        }
    }
}

private struct ScheduledTransactionRow: View {
    let scheduled: ScheduledTransaction
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(scheduled.name.isEmpty ? "Untitled" : scheduled.name)
                        .font(.system(size: 14, weight: .medium))
                    if !scheduled.isActive {
                        Text("Paused")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }

                Text(scheduled.recurrenceDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(scheduled.type == .income ? "+\(formatAmount(scheduled.amount))" : "-\(formatAmount(scheduled.amount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(scheduled.type == .income ? .green : .primary)

            if !scheduled.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(scheduled.tags, id: \.self) { tag in
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

// MARK: - Scheduled transaction editor

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

private struct ScheduledTransactionEditorView: View {
    @ObservedObject var viewModel: DominoViewModel
    let scheduledTransaction: ScheduledTransaction?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: ScheduledTransactionType = .expense
    @State private var amount: String = ""
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var isActive: Bool = true
    @State private var eventDate: Date = Date()

    @State private var selectedPreset: RecurrencePreset = .doesNotRepeat
    @State private var customRecurrence: Recurrence?
    @State private var showCustomRecurrence = false
    @State private var previousPreset: RecurrencePreset = .doesNotRepeat

    var isEditing: Bool { scheduledTransaction != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
                .padding(16)
        }
        .frame(width: 480, height: 440)
        .onAppear { loadScheduledTransaction() }
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
            Text(isEditing ? "Edit scheduled transaction" : "New scheduled transaction")
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
                            ForEach(ScheduledTransactionType.allCases, id: \.self) { t in
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

    private func loadScheduledTransaction() {
        guard let scheduledTransaction else { return }
        name = scheduledTransaction.name
        type = scheduledTransaction.type
        amount = String(format: "%.2f", scheduledTransaction.amount)
        tags = scheduledTransaction.tags
        isActive = scheduledTransaction.isActive
        eventDate = scheduledTransaction.createdAt

        let preset = presetForRecurrence(scheduledTransaction.recurrence)
        selectedPreset = preset
        if preset == .custom {
            customRecurrence = scheduledTransaction.recurrence
        }
    }

    private func save() {
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        var recurrence = buildRecurrence()
        recurrence?.startDate = eventDate

        let saved = ScheduledTransaction(
            id: scheduledTransaction?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: amountValue,
            recurrence: recurrence,
            tags: tags,
            isActive: isActive,
            createdAt: eventDate
        )

        if isEditing {
            viewModel.updateScheduledTransaction(saved)
        } else {
            viewModel.addScheduledTransaction(saved)
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

            HStack(spacing: 8) {
                Button("Add Tag") {
                    addTag(input)
                }
                .buttonStyle(.bordered)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("You can create new tags here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
    var prefilledScheduledTransactionID: UUID?
    var prefilledDueDate: Date?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: ScheduledTransactionType = .expense
    @State private var amount: String = ""
    @State private var date: Date = Date()
    @State private var selectedDueDate: Date = Date()
    @State private var note: String = ""
    @State private var selectedScheduledTransactionID: UUID?
    @State private var tags: [String] = []
    @State private var tagInput: String = ""

    var isEditing: Bool { transaction != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                form.padding(16)
            }
        }
        .frame(width: 460, height: selectedScheduledTransactionID != nil ? 560 : 500)
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
            LabeledContent("From scheduled transaction") {
                Picker("", selection: $selectedScheduledTransactionID) {
                    Text("None (one-off)").tag(nil as UUID?)
                    ForEach(Array(viewModel.scheduledTransactions.values).sorted { $0.name < $1.name }) { scheduled in
                        Text(scheduled.name).tag(scheduled.id as UUID?)
                    }
                }
                .onChange(of: selectedScheduledTransactionID) { _, id in
                    guard let id, let scheduled = viewModel.scheduledTransactions[id] else {
                        selectedDueDate = date
                        return
                    }
                    name = scheduled.name
                    type = scheduled.type
                    amount = String(format: "%.2f", scheduled.amount)
                    tags = scheduled.tags
                    if !scheduled.isRecurring {
                        selectedDueDate = scheduled.createdAt
                    } else {
                        selectedDueDate = nearestInstance(for: scheduled)
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
                        ForEach(ScheduledTransactionType.allCases, id: \.self) { t in
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

            if selectedScheduledTransactionID != nil {
                instancePicker
            }

            DatePicker("Payment date", selection: $date, displayedComponents: .date)

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

            budgetImpactView

            LabeledContent("Note") {
                TextField("Optional", text: $note)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var budgetImpactView: some View {
        let matching = viewModel.matchingBudgets(forTransactionTags: tags)
        let overNames = projectedOverBudgetNames
        return VStack(alignment: .leading, spacing: 4) {
            if matching.isEmpty {
                Text("No matching budget")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Counts toward: \(matching.map(\.name).joined(separator: ", "))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if !overNames.isEmpty {
                Text("This transaction would exceed: \(overNames.joined(separator: ", "))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Instance picker

    private var instancePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let id = selectedScheduledTransactionID, let scheduled = viewModel.scheduledTransactions[id] {
                if scheduled.isRecurring {
                    let instances = computeInstances(for: scheduled)
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
                        Text(Self.instanceDateFormatter.string(from: scheduled.createdAt))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            }
        }
    }

    private func computeInstances(for scheduled: ScheduledTransaction) -> [Date] {
        FinancialScheduling.recurrenceInstances(
            for: scheduled,
            centerMonth: defaultMonth,
            centerYear: defaultYear,
            calendar: Calendar.current
        )
    }

    private func nearestInstance(for scheduled: ScheduledTransaction) -> Date {
        let instances = computeInstances(for: scheduled)
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
            tags = txn.tags
            note = txn.note ?? ""
            selectedScheduledTransactionID = txn.scheduledTransactionID
            if let stID = txn.scheduledTransactionID,
                let scheduled = viewModel.scheduledTransactions[stID],
                scheduled.isRecurring {
                let instances = computeInstances(for: scheduled)
                if let resolved = FinancialScheduling.matchingOccurrence(
                    in: instances,
                    forStoredDueDate: txn.dueDate,
                    calendar: Calendar.current
                ) {
                    selectedDueDate = resolved
                }
            }
        } else if let stID = prefilledScheduledTransactionID {
            selectedScheduledTransactionID = stID
            if let scheduled = viewModel.scheduledTransactions[stID] {
                name = scheduled.name
                type = scheduled.type
                amount = String(format: "%.2f", scheduled.amount)
                tags = scheduled.tags
            }
            if let prefilled = prefilledDueDate {
                selectedDueDate = prefilled
                if let scheduled = viewModel.scheduledTransactions[stID], scheduled.isRecurring {
                    let instances = computeInstances(for: scheduled)
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
            scheduledTransactionID: selectedScheduledTransactionID,
            name: name.trimmingCharacters(in: .whitespaces),
            amount: amountValue,
            type: type,
            date: date,
            dueDate: selectedDueDate,
            tags: tags,
            note: note.trimmingCharacters(in: .whitespaces).nilIfEmpty
        )

        if isEditing {
            viewModel.updateFinancialTransaction(saved)
        } else {
            viewModel.addFinancialTransaction(saved)
        }
        dismiss()
    }

    private var tagSuggestions: [String] {
        let existingTags = (viewModel.allFinancialTags() + viewModel.allTransactionTags() + viewModel.allBudgetTags())
        let selected = Set(tags.map { normalizedTagKey($0) })
        let query = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = Array(Set(existingTags)).filter { !selected.contains(normalizedTagKey($0)) }
        guard !query.isEmpty else { return Array(base.prefix(8)) }

        return base
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(8)
            .map { $0 }
    }

    private var projectedOverBudgetNames: [String] {
        guard type == .expense else { return [] }
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        guard amountValue > 0 else { return [] }
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        let month = comps.month ?? defaultMonth
        let year = comps.year ?? defaultYear
        let breakdown = Dictionary(uniqueKeysWithValues: viewModel
            .budgetBreakdownForMonth(month: month, year: year)
            .map { ($0.budget.id, $0) })
        return viewModel.matchingBudgets(forTransactionTags: tags).compactMap { budget in
            guard let row = breakdown[budget.id] else { return nil }
            return row.spent + amountValue > budget.amount ? budget.name : nil
        }
    }

    private func normalizedTagKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

// MARK: - Budgets

private struct BudgetsListView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var showingAddBudget = false
    @State private var editingBudget: FinancialBudget?
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
            budgetsList
        }
        .sheet(isPresented: $showingAddBudget) {
            BudgetEditorView(viewModel: viewModel, budget: nil)
        }
        .sheet(item: $editingBudget) { budget in
            BudgetEditorView(viewModel: viewModel, budget: budget)
        }
    }

    private var header: some View {
        HStack {
            Text("Budgets")
                .font(.system(size: 16, weight: .semibold))

            Spacer()
            monthPicker

            Button {
                showingAddBudget = true
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

    private var budgetsList: some View {
        let rows = viewModel.budgetBreakdownForMonth(month: month, year: year)
        let unbudgeted = viewModel.unbudgetedExpenseForMonth(month: month, year: year)
        return ScrollView {
            LazyVStack(spacing: 10) {
                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 60)
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No budgets yet")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(rows, id: \.budget.id) { row in
                        BudgetProgressRow(
                            row: row,
                            onEdit: { editingBudget = row.budget },
                            onDelete: { viewModel.deleteFinancialBudget(row.budget.id) }
                        )
                    }
                }

                if unbudgeted > 0 {
                    HStack {
                        Text("Unbudgeted spend")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatAmount(unbudgeted))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                }
            }
            .padding(12)
        }
    }

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
        return amount < 0 ? "-$\(value)" : "$\(value)"
    }
}

private struct BudgetProgressRow: View {
    let row: (budget: FinancialBudget, spent: Double, remaining: Double)
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var ratio: Double {
        guard row.budget.amount > 0 else { return 0 }
        return row.spent / row.budget.amount
    }

    private var barColor: Color {
        if ratio >= 1.0 { return .red }
        if ratio >= 0.8 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.budget.name.isEmpty ? "Untitled Budget" : row.budget.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(row.budget.tagKeys.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(formatAmount(row.spent)) / \(formatAmount(row.budget.amount))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("Remaining: \(formatAmount(row.remaining))")
                        .font(.system(size: 11))
                        .foregroundStyle(row.remaining < 0 ? .red : .secondary)
                }

                Menu {
                    Button("Edit") { onEdit() }
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let progress = max(0, min(1, ratio))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: width * progress)
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
        return amount < 0 ? "-$\(value)" : "$\(value)"
    }
}

private struct BudgetEditorView: View {
    @ObservedObject var viewModel: DominoViewModel
    let budget: FinancialBudget?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var tags: [String] = []
    @State private var tagInput = ""
    @State private var isActive = true
    @State private var validationMessage: String?

    private var isEditing: Bool { budget != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Budget" : "New Budget")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tags.isEmpty)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("Name") {
                        TextField("e.g. Groceries", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Amount") {
                        HStack(spacing: 2) {
                            Text("$").foregroundStyle(.secondary)
                            TextField("0.00", text: $amount)
                                .textFieldStyle(.roundedBorder)
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

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 360)
        .onAppear { loadBudget() }
    }

    private var tagSuggestions: [String] {
        let existingTags = (viewModel.allFinancialTags() + viewModel.allTransactionTags() + viewModel.allBudgetTags())
        let selected = Set(tags.map { normalizedTagKey($0) })
        let query = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = Array(Set(existingTags)).filter { !selected.contains(normalizedTagKey($0)) }
        guard !query.isEmpty else { return Array(base.prefix(8)) }
        return base
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(8)
            .map { $0 }
    }

    private func loadBudget() {
        guard let budget else { return }
        name = budget.name
        amount = String(format: "%.2f", budget.amount)
        tags = budget.tagKeys
        isActive = budget.isActive
    }

    private func save() {
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        let saved = FinancialBudget(
            id: budget?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amountValue,
            period: .monthly,
            tagKeys: tags,
            isActive: isActive,
            createdAt: budget?.createdAt ?? Date()
        )
        let conflicts = viewModel.conflictingBudgetNames(for: saved)
        if !conflicts.isEmpty {
            validationMessage = "Overlapping tags with: \(conflicts.joined(separator: ", "))"
            return
        }
        if isEditing {
            viewModel.updateFinancialBudget(saved)
        } else {
            viewModel.addFinancialBudget(saved)
        }
        dismiss()
    }

    private func normalizedTagKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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

    private var budgetRows: [(budget: FinancialBudget, spent: Double, remaining: Double)] {
        viewModel.budgetBreakdownForMonth(month: month, year: year)
    }

    private var unbudgetedSpend: Double {
        viewModel.unbudgetedExpenseForMonth(month: month, year: year)
    }

    private var summaryContent: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                summaryCard(title: "Income", amount: summary.income, color: .green)
                summaryCard(title: "Expenses", amount: summary.expenses, color: .red)
                summaryCard(title: "Net", amount: summary.net, color: summary.net >= 0 ? .green : .red)
            }

            Divider()

            // Expected vs actual for scheduled transactions
            let dues = viewModel.expectedDues(month: month, year: year)

            if !dues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Expected vs Actual")
                        .font(.system(size: 14, weight: .semibold))

                    ForEach(dues, id: \.scheduled.id) { due in
                        let paid = viewModel.financialTransactions.values.contains { txn in
                            txn.scheduledTransactionID == due.scheduled.id &&
                            Calendar.current.isDate(txn.dueDate, inSameDayAs: due.date)
                        }
                        HStack {
                            Image(systemName: paid ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(paid ? .green : .secondary)
                                .font(.system(size: 12))

                            Text(due.scheduled.name)
                                .font(.system(size: 13))
                            Spacer()
                            Text(due.date, style: .date)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(formatAmount(due.scheduled.amount))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(due.scheduled.type == .income ? .green : .primary)
                        }
                    }
                }
            }

            if !budgetRows.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Budget Health")
                        .font(.system(size: 14, weight: .semibold))

                    ForEach(budgetRows, id: \.budget.id) { row in
                        HStack {
                            Text(row.budget.name)
                                .font(.system(size: 13))
                            Spacer()
                            Text("\(formatAmount(row.spent)) / \(formatAmount(row.budget.amount))")
                                .font(.system(size: 12, design: .monospaced))
                            Text("Remaining \(formatAmount(row.remaining))")
                                .font(.system(size: 11))
                                .foregroundStyle(row.remaining < 0 ? .red : .secondary)
                        }
                    }

                    if unbudgetedSpend > 0 {
                        HStack {
                            Text("Unbudgeted spend")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatAmount(unbudgetedSpend))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.orange)
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
                                for: pending.scheduled,
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

    private var dues: [(scheduled: ScheduledTransaction, date: Date)] {
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
                    ForEach(dues, id: \.scheduled.id) { due in
                        DueRow(
                            scheduled: due.scheduled,
                            date: due.date,
                            isPaid: isPaid(scheduledTransactionID: due.scheduled.id, dueDate: due.date),
                            onRecordFirstWorkingDate: {
                                let recordDate = FinancialScheduling.firstWorkingDateOnOrAfter(due.date)
                                recordTransaction(for: due.scheduled, dueDate: due.date, recordedOn: recordDate)
                            },
                            onRecordDueDate: {
                                recordTransaction(for: due.scheduled, dueDate: due.date, recordedOn: due.date)
                            },
                            onRecordToday: {
                                recordTransaction(for: due.scheduled, dueDate: due.date, recordedOn: Date())
                            },
                            onRecordCustomDate: {
                                customRecordDate = due.date
                                pendingCustomRecord = PendingCustomRecord(scheduled: due.scheduled, dueDate: due.date)
                            }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private func isPaid(scheduledTransactionID: UUID, dueDate: Date) -> Bool {
        viewModel.financialTransactions.values.contains { txn in
            txn.scheduledTransactionID == scheduledTransactionID &&
            Calendar.current.isDate(txn.dueDate, inSameDayAs: dueDate)
        }
    }

    private func recordTransaction(for scheduled: ScheduledTransaction, dueDate: Date, recordedOn: Date) {
        let txn = FinancialTransaction(
            scheduledTransactionID: scheduled.id,
            name: scheduled.name,
            amount: scheduled.amount,
            type: scheduled.type,
            date: recordedOn,
            dueDate: dueDate
        )
        viewModel.addFinancialTransaction(txn)
    }

}

private struct PendingCustomRecord: Identifiable {
    let id = UUID()
    let scheduled: ScheduledTransaction
    let dueDate: Date
}

private struct DueRow: View {
    let scheduled: ScheduledTransaction
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
                Text(scheduled.name.isEmpty ? "Untitled" : scheduled.name)
                    .font(.system(size: 14, weight: .medium))
                Text(scheduled.recurrenceDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(scheduled.type == .income ? "+\(formatAmount(scheduled.amount))" : "-\(formatAmount(scheduled.amount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(scheduled.type == .income ? .green : .primary)

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
