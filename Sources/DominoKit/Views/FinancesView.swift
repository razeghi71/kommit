import SwiftUI

// MARK: - Finances Sub-tabs

private enum FinancesTab: String, CaseIterable, Identifiable {
    case financialPlanning
    case transactions
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .financialPlanning: "Financial Planning"
        case .transactions: "Transactions"
        case .calendar: "Calendar"
        }
    }

    var icon: String {
        switch self {
        case .financialPlanning: "calendar.badge.clock"
        case .transactions: "arrow.left.arrow.right"
        case .calendar: "calendar"
        }
    }
}

// MARK: - Main Finances View

package struct FinancesView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var selectedTab: FinancesTab = .financialPlanning

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
        case .financialPlanning:
            FinancialPlanningListView(viewModel: viewModel)
        case .transactions:
            TransactionsListView(viewModel: viewModel)
        case .calendar:
            FinanceCalendarView(viewModel: viewModel)
        }
    }
}

// MARK: - Financial planning list (commitments + forecasts)

private struct FinancialPlanningListView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var showingAddCommitment = false
    @State private var showingAddForecast = false
    @State private var editingCommitment: Commitment?
    @State private var editingForecast: Forecast?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            entriesTable
        }
        .sheet(isPresented: $showingAddCommitment) {
            CommitmentEditorView(viewModel: viewModel, commitment: nil)
        }
        .sheet(isPresented: $showingAddForecast) {
            ForecastEditorView(viewModel: viewModel, forecast: nil)
        }
        .sheet(item: $editingCommitment) { commitment in
            CommitmentEditorView(viewModel: viewModel, commitment: commitment)
        }
        .sheet(item: $editingForecast) { forecast in
            ForecastEditorView(viewModel: viewModel, forecast: forecast)
        }
    }

    private var header: some View {
        HStack {
            Text("Financial planning")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Menu {
                Button("New commitment…") {
                    showingAddCommitment = true
                }
                Button("New forecast…") {
                    showingAddForecast = true
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderedButton)
        }
        .padding(12)
    }

    private var sortedCommitments: [Commitment] {
        viewModel.commitments.values.sorted { $0.name < $1.name }
    }

    private var sortedForecasts: [Forecast] {
        viewModel.forecasts.values.sorted { $0.name < $1.name }
    }

    private var entriesTable: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                sectionHeader("Commitments")
                if sortedCommitments.isEmpty {
                    emptyHint("No commitments yet. Add rent, salary, subscriptions—items you mark paid when they happen.")
                }
                ForEach(sortedCommitments) { entry in
                    CommitmentRow(
                        commitment: entry,
                        onEdit: { editingCommitment = entry },
                        onDelete: {
                            viewModel.deleteCommitment(entry.id)
                        }
                    )
                    Divider()
                }

                sectionHeader("Forecasts")
                if sortedForecasts.isEmpty {
                    emptyHint("No forecasts yet. Add typical spending like groceries or lunch—shown in the calendar as estimates, not due items.")
                }
                ForEach(sortedForecasts) { entry in
                    ForecastRow(
                        forecast: entry,
                        onEdit: { editingForecast = entry },
                        onDelete: {
                            viewModel.deleteForecast(entry.id)
                        }
                    )
                    Divider()
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

private struct CommitmentRow: View {
    let commitment: Commitment
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(commitment.name.isEmpty ? "Untitled" : commitment.name)
                        .font(.system(size: 14, weight: .medium))
                    if !commitment.isActive {
                        Text("Paused")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }

                Text(commitment.recurrenceDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(commitment.type == .income ? "+\(formatAmount(commitment.amount))" : "-\(formatAmount(commitment.amount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(commitment.type == .income ? .green : .primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(commitment.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                }
            }
            .frame(width: 160, alignment: .leading)

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

private struct ForecastRow: View {
    let forecast: Forecast
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(forecast.name.isEmpty ? "Untitled" : forecast.name)
                        .font(.system(size: 14, weight: .medium))
                    Text("Forecast")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                    if !forecast.isActive {
                        Text("Paused")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }

                Text(forecast.recurrenceDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(forecast.type == .income ? "+\(formatAmount(forecast.amount))" : "-\(formatAmount(forecast.amount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(forecast.type == .income ? .green : .primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(forecast.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                }
            }
            .frame(width: 160, alignment: .leading)

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

// MARK: - Commitment editor

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

private struct CommitmentDraftBaseline: Equatable {
    var name: String
    var type: FinancialFlowType
    var amount: Double
    var tags: [String]
    var isActive: Bool
    var eventDate: Date
    var recurrence: Recurrence?
}

private struct CommitmentEditorView: View {
    @ObservedObject var viewModel: DominoViewModel
    let commitment: Commitment?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: FinancialFlowType = .expense
    @State private var amount: String = ""
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var isActive: Bool = true
    @State private var eventDate: Date = Date()

    @State private var selectedPreset: RecurrencePreset = .doesNotRepeat
    @State private var customRecurrence: Recurrence?
    @State private var showCustomRecurrence = false
    @State private var previousPreset: RecurrencePreset = .doesNotRepeat
    @State private var draftBaseline: CommitmentDraftBaseline?

    var isEditing: Bool { commitment != nil }

    private var hasUnsavedDraft: Bool {
        guard let draftBaseline else { return false }
        return currentDraftSnapshot() != draftBaseline
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
                .padding(16)
        }
        .frame(width: 480, height: 440)
        .interactiveDismissDisabled(hasUnsavedDraft)
        .onAppear { loadCommitment() }
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
            Text(isEditing ? "Edit commitment" : "New commitment")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Cancel") { cancelEditing() }
                .buttonStyle(.borderless)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private func normalizedRecurrenceForDraft() -> Recurrence? {
        var r = buildRecurrence()
        r?.startDate = eventDate
        return r
    }

    private func currentDraftSnapshot() -> CommitmentDraftBaseline {
        CommitmentDraftBaseline(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0,
            tags: tags,
            isActive: isActive,
            eventDate: eventDate,
            recurrence: normalizedRecurrenceForDraft()
        )
    }

    private func captureDraftBaseline() {
        draftBaseline = currentDraftSnapshot()
    }

    private func cancelEditing() {
        guard hasUnsavedDraft else {
            dismiss()
            return
        }
        if DominoViewModel.showDiscardConfirmation(
            messageText: "Discard changes?",
            informativeText: "Your edits to this commitment will be lost."
        ) {
            dismiss()
        }
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
                            ForEach(FinancialFlowType.allCases, id: \.self) { t in
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

    private func loadCommitment() {
        if let existing = commitment {
            name = existing.name
            type = existing.type
            amount = String(format: "%.2f", existing.amount)
            tags = existing.tags
            isActive = existing.isActive
            eventDate = existing.createdAt

            let preset = presetForRecurrence(existing.recurrence)
            selectedPreset = preset
            if preset == .custom {
                customRecurrence = existing.recurrence
            }
        }
        captureDraftBaseline()
    }

    private func save() {
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        var recurrence = buildRecurrence()
        recurrence?.startDate = eventDate

        let saved = Commitment(
            id: commitment?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: amountValue,
            recurrence: recurrence,
            tags: tags,
            isActive: isActive,
            createdAt: eventDate
        )

        if isEditing {
            viewModel.updateCommitment(saved)
        } else {
            viewModel.addCommitment(saved)
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

// MARK: - Forecast editor

private struct ForecastEditorView: View {
    @ObservedObject var viewModel: DominoViewModel
    let forecast: Forecast?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: FinancialFlowType = .expense
    @State private var amount: String = ""
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var isActive: Bool = true
    @State private var eventDate: Date = Date()

    @State private var selectedPreset: RecurrencePreset = .doesNotRepeat
    @State private var customRecurrence: Recurrence?
    @State private var showCustomRecurrence = false
    @State private var previousPreset: RecurrencePreset = .doesNotRepeat
    @State private var draftBaseline: CommitmentDraftBaseline?

    var isEditing: Bool { forecast != nil }

    private var hasUnsavedDraft: Bool {
        guard let draftBaseline else { return false }
        return currentDraftSnapshot() != draftBaseline
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
                .padding(16)
        }
        .frame(width: 480, height: 440)
        .interactiveDismissDisabled(hasUnsavedDraft)
        .onAppear { loadForecastForEditor() }
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
            Text(isEditing ? "Edit forecast" : "New forecast")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Cancel") { cancelEditing() }
                .buttonStyle(.borderless)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private func normalizedRecurrenceForDraft() -> Recurrence? {
        var r = buildRecurrence()
        r?.startDate = eventDate
        return r
    }

    private func currentDraftSnapshot() -> CommitmentDraftBaseline {
        CommitmentDraftBaseline(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0,
            tags: tags,
            isActive: isActive,
            eventDate: eventDate,
            recurrence: normalizedRecurrenceForDraft()
        )
    }

    private func captureDraftBaseline() {
        draftBaseline = currentDraftSnapshot()
    }

    private func cancelEditing() {
        guard hasUnsavedDraft else {
            dismiss()
            return
        }
        if DominoViewModel.showDiscardConfirmation(
            messageText: "Discard changes?",
            informativeText: "Your edits to this forecast will be lost."
        ) {
            dismiss()
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Shown on the calendar as a forecast. It is not a commitment you mark paid.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("Name") {
                    TextField("e.g. Lunch, Groceries", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    LabeledContent("Type") {
                        Picker("", selection: $type) {
                            ForEach(FinancialFlowType.allCases, id: \.self) { t in
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

                DatePicker("Starts", selection: $eventDate, displayedComponents: .date)

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

    private func loadForecastForEditor() {
        if let existing = forecast {
            name = existing.name
            type = existing.type
            amount = String(format: "%.2f", existing.amount)
            tags = existing.tags
            isActive = existing.isActive
            eventDate = existing.createdAt

            let preset = presetForRecurrence(existing.recurrence)
            selectedPreset = preset
            if preset == .custom {
                customRecurrence = existing.recurrence
            }
        }
        captureDraftBaseline()
    }

    private func save() {
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        var recurrence = buildRecurrence()
        recurrence?.startDate = eventDate

        let saved = Forecast(
            id: forecast?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: amountValue,
            recurrence: recurrence,
            tags: tags,
            isActive: isActive,
            createdAt: eventDate
        )

        if isEditing {
            viewModel.updateForecast(saved)
        } else {
            viewModel.addForecast(saved)
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
    @State private var recurrenceBaseline: Recurrence?

    private enum MonthDayMode: String, CaseIterable {
        case dayOfMonth
        case weekdayOfMonth
    }

    private var hasUnsavedCustomRecurrenceDraft: Bool {
        guard let recurrenceBaseline else { return false }
        return buildRecurrence() != recurrenceBaseline
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
                Button("Cancel") { cancelCustomRecurrence() }
                    .buttonStyle(.borderless)
                Button("Done") { onSave(buildRecurrence()) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 400, height: 420)
        .interactiveDismissDisabled(hasUnsavedCustomRecurrenceDraft)
        .onAppear { loadInitial() }
    }

    private func cancelCustomRecurrence() {
        guard hasUnsavedCustomRecurrenceDraft else {
            onCancel()
            return
        }
        if DominoViewModel.showDiscardConfirmation(
            messageText: "Discard changes?",
            informativeText: "Your custom recurrence settings will be lost."
        ) {
            onCancel()
        }
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
            recurrenceBaseline = buildRecurrence()
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

        recurrenceBaseline = buildRecurrence()
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

    private var showsOccurrenceNote: Bool {
        let linked = transaction.commitmentID != nil || transaction.forecastID != nil
        return linked && !Calendar.current.isDate(transaction.dueDate, inSameDayAs: transaction.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.dateFormatter.string(from: transaction.date))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.name.isEmpty ? "Untitled" : transaction.name)
                    .font(.system(size: 14, weight: .medium))
                if showsOccurrenceNote {
                    Text("Occurrence: \(Self.dateFormatter.string(from: transaction.dueDate))")
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

            HStack(spacing: 2) {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")
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

// MARK: - Transaction Editor

private struct FinancialTransactionDraftBaseline: Equatable {
    var name: String
    var type: FinancialFlowType
    var amount: Double
    var date: Date
    var dueDate: Date
    var tags: [String]
    var note: String?
    var commitmentID: UUID?
    var forecastID: UUID?
}

private enum TransactionPlanningLinkKind: String, CaseIterable, Identifiable {
    case none
    case commitment
    case forecast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None (one-off)"
        case .commitment: "Commitment"
        case .forecast: "Forecast"
        }
    }
}

private struct TransactionEditorView: View {
    @ObservedObject var viewModel: DominoViewModel
    let transaction: FinancialTransaction?
    let defaultMonth: Int
    let defaultYear: Int
    var prefilledCommitmentID: UUID?
    var prefilledDueDate: Date?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: FinancialFlowType = .expense
    @State private var amount: String = ""
    @State private var date: Date = Date()
    @State private var selectedDueDate: Date = Date()
    @State private var note: String = ""
    @State private var planningLinkKind: TransactionPlanningLinkKind = .none
    @State private var selectedCommitmentID: UUID?
    @State private var selectedForecastID: UUID?
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var draftBaseline: FinancialTransactionDraftBaseline?

    var isEditing: Bool { transaction != nil }

    private var hasUnsavedDraft: Bool {
        guard let draftBaseline else { return false }
        return currentDraftSnapshot() != draftBaseline
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                form.padding(16)
            }
        }
        .frame(width: 460, height: planningLinkKind == .none ? 500 : 580)
        .interactiveDismissDisabled(hasUnsavedDraft)
        .onAppear { loadTransaction() }
        .onChange(of: date) { _, newDate in
            guard planningLinkKind == .none else { return }
            selectedDueDate = newDate
        }
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit Transaction" : "New Transaction")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Cancel") { cancelEditing() }
                .buttonStyle(.borderless)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || planningLinkIncomplete)
        }
        .padding(12)
    }

    private var planningLinkIncomplete: Bool {
        switch planningLinkKind {
        case .none: false
        case .commitment: selectedCommitmentID == nil
        case .forecast: selectedForecastID == nil
        }
    }

    private func currentDraftSnapshot() -> FinancialTransactionDraftBaseline {
        FinancialTransactionDraftBaseline(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0,
            date: date,
            dueDate: selectedDueDate,
            tags: tags,
            note: note.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            commitmentID: planningLinkKind == .commitment ? selectedCommitmentID : nil,
            forecastID: planningLinkKind == .forecast ? selectedForecastID : nil
        )
    }

    private func captureDraftBaseline() {
        draftBaseline = currentDraftSnapshot()
    }

    private func cancelEditing() {
        guard hasUnsavedDraft else {
            dismiss()
            return
        }
        if DominoViewModel.showDiscardConfirmation(
            messageText: "Discard changes?",
            informativeText: "Your edits to this transaction will be lost."
        ) {
            dismiss()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Planning link") {
                Picker("", selection: $planningLinkKind) {
                    ForEach(TransactionPlanningLinkKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .onChange(of: planningLinkKind) { _, newKind in
                    switch newKind {
                    case .none:
                        selectedCommitmentID = nil
                        selectedForecastID = nil
                        selectedDueDate = date
                    case .commitment:
                        selectedForecastID = nil
                        if selectedCommitmentID == nil {
                            selectedDueDate = date
                        }
                    case .forecast:
                        selectedCommitmentID = nil
                        if selectedForecastID == nil {
                            selectedDueDate = date
                        }
                    }
                }
            }

            if planningLinkKind == .commitment {
                LabeledContent("Commitment") {
                    Picker("", selection: $selectedCommitmentID) {
                        Text("Choose…").tag(nil as UUID?)
                        ForEach(Array(viewModel.commitments.values).sorted { $0.name < $1.name }) { item in
                            Text(item.name.isEmpty ? "Untitled" : item.name).tag(item.id as UUID?)
                        }
                    }
                    .onChange(of: selectedCommitmentID) { _, id in
                        applyCommitmentSelection(id)
                    }
                }
            }

            if planningLinkKind == .forecast {
                LabeledContent("Forecast") {
                    Picker("", selection: $selectedForecastID) {
                        Text("Choose…").tag(nil as UUID?)
                        ForEach(Array(viewModel.forecasts.values).sorted { $0.name < $1.name }) { item in
                            Text(item.name.isEmpty ? "Untitled" : item.name).tag(item.id as UUID?)
                        }
                    }
                    .onChange(of: selectedForecastID) { _, id in
                        applyForecastSelection(id)
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
                        ForEach(FinancialFlowType.allCases, id: \.self) { t in
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

            if planningLinkKind != .none {
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

            LabeledContent("Note") {
                TextField("Optional", text: $note)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Instance picker

    private var instancePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if planningLinkKind == .commitment,
                let id = selectedCommitmentID,
                let commitmentItem = viewModel.commitments[id] {
                if commitmentItem.isRecurring {
                    let instances = computeInstances(for: commitmentItem)
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
                        Text(Self.instanceDateFormatter.string(from: commitmentItem.createdAt))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            } else if planningLinkKind == .forecast,
                let id = selectedForecastID,
                let forecastItem = viewModel.forecasts[id] {
                if forecastItem.isRecurring {
                    let instances = computeInstances(for: forecastItem)
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
                        Text(Self.instanceDateFormatter.string(from: forecastItem.createdAt))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            }
        }
    }

    private func computeInstances(for commitmentItem: Commitment) -> [Date] {
        FinancialRecurrence.recurrenceInstances(
            for: commitmentItem,
            centerMonth: defaultMonth,
            centerYear: defaultYear,
            calendar: Calendar.current
        )
    }

    private func computeInstances(for forecastItem: Forecast) -> [Date] {
        FinancialRecurrence.recurrenceInstances(
            for: forecastItem,
            centerMonth: defaultMonth,
            centerYear: defaultYear,
            calendar: Calendar.current
        )
    }

    private func nearestInstance(for commitmentItem: Commitment) -> Date {
        let instances = computeInstances(for: commitmentItem)
        let cal = Calendar.current
        guard !instances.isEmpty else { return Date() }
        let anchor = cal.date(from: DateComponents(year: defaultYear, month: defaultMonth, day: 15)) ?? Date()
        return instances.min(by: { abs($0.timeIntervalSince(anchor)) < abs($1.timeIntervalSince(anchor)) }) ?? instances[0]
    }

    private func nearestInstance(for forecastItem: Forecast) -> Date {
        let instances = computeInstances(for: forecastItem)
        let cal = Calendar.current
        guard !instances.isEmpty else { return Date() }
        let anchor = cal.date(from: DateComponents(year: defaultYear, month: defaultMonth, day: 15)) ?? Date()
        return instances.min(by: { abs($0.timeIntervalSince(anchor)) < abs($1.timeIntervalSince(anchor)) }) ?? instances[0]
    }

    private func applyCommitmentSelection(_ id: UUID?) {
        guard let id, let item = viewModel.commitments[id] else {
            selectedDueDate = date
            return
        }
        if !isEditing {
            name = item.name
            type = item.type
            amount = String(format: "%.2f", item.amount)
            tags = item.tags
        }
        if !item.isRecurring {
            selectedDueDate = item.createdAt
        } else {
            selectedDueDate = nearestInstance(for: item)
        }
    }

    private func applyForecastSelection(_ id: UUID?) {
        guard let id, let item = viewModel.forecasts[id] else {
            selectedDueDate = date
            return
        }
        if !isEditing {
            name = item.name
            type = item.type
            amount = String(format: "%.2f", item.amount)
            tags = item.tags
        }
        if !item.isRecurring {
            selectedDueDate = item.createdAt
        } else {
            selectedDueDate = nearestInstance(for: item)
        }
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
            if txn.commitmentID != nil {
                planningLinkKind = .commitment
                selectedCommitmentID = txn.commitmentID
                selectedForecastID = nil
            } else if txn.forecastID != nil {
                planningLinkKind = .forecast
                selectedForecastID = txn.forecastID
                selectedCommitmentID = nil
            } else {
                planningLinkKind = .none
                selectedCommitmentID = nil
                selectedForecastID = nil
                selectedDueDate = txn.date
            }
            if planningLinkKind == .commitment, let commitmentID = txn.commitmentID,
                let commitmentItem = viewModel.commitments[commitmentID], commitmentItem.isRecurring {
                let instances = computeInstances(for: commitmentItem)
                if let resolved = FinancialRecurrence.matchingOccurrence(
                    in: instances,
                    forStoredDueDate: txn.dueDate,
                    calendar: Calendar.current
                ) {
                    selectedDueDate = resolved
                }
            } else if planningLinkKind == .forecast, let forecastID = txn.forecastID,
                let forecastItem = viewModel.forecasts[forecastID], forecastItem.isRecurring {
                let instances = computeInstances(for: forecastItem)
                if let resolved = FinancialRecurrence.matchingOccurrence(
                    in: instances,
                    forStoredDueDate: txn.dueDate,
                    calendar: Calendar.current
                ) {
                    selectedDueDate = resolved
                }
            }
        } else if let prefilledCommitmentUUID = prefilledCommitmentID {
            planningLinkKind = .commitment
            selectedCommitmentID = prefilledCommitmentUUID
            selectedForecastID = nil
            applyCommitmentSelection(prefilledCommitmentUUID)
            if let prefilled = prefilledDueDate {
                selectedDueDate = prefilled
                if let commitmentItem = viewModel.commitments[prefilledCommitmentUUID], commitmentItem.isRecurring {
                    let instances = computeInstances(for: commitmentItem)
                    if let resolved = FinancialRecurrence.matchingOccurrence(
                        in: instances,
                        forStoredDueDate: prefilled,
                        calendar: Calendar.current
                    ) {
                        selectedDueDate = resolved
                    }
                }
            }
        }
        captureDraftBaseline()
    }

    private func save() {
        let amountValue = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0

        let savedCommitmentID = planningLinkKind == .commitment ? selectedCommitmentID : nil
        let savedForecastID = planningLinkKind == .forecast ? selectedForecastID : nil
        let effectiveDueDate = planningLinkKind == .none ? date : selectedDueDate
        let saved = FinancialTransaction(
            id: transaction?.id ?? UUID(),
            commitmentID: savedCommitmentID,
            forecastID: savedForecastID,
            name: name.trimmingCharacters(in: .whitespaces),
            amount: amountValue,
            type: type,
            date: date,
            dueDate: effectiveDueDate,
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
        let existingTags = (viewModel.allFinancialTags() + viewModel.allTransactionTags())
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

    private func normalizedTagKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
