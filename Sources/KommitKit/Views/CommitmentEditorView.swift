import SwiftUI

// MARK: - Recurrence Preset (Google Calendar-style)

enum RecurrencePreset: Hashable {
    case doesNotRepeat
    case daily
    case weeklyOnDay
    case monthlyOnDay
    case annuallyOnDate
    case everyWeekday
    case custom
}

struct CommitmentDraftBaseline: Equatable {
    var name: String
    var type: FinancialFlowType
    var amount: Double
    var tags: [String]
    var isActive: Bool
    var eventDate: Date
    var recurrence: Recurrence?
}

struct CommitmentEditorSeed {
    var name: String
    var type: FinancialFlowType
    var amount: Double
    var eventDate: Date
    var tags: [String]
}

// MARK: - Commitment editor

struct CommitmentEditorView: View {
    @ObservedObject var viewModel: KommitViewModel
    let commitment: Commitment?
    var seed: CommitmentEditorSeed?
    var onSaveCommitment: ((Commitment) -> Void)?
    var allowsRecurrence: Bool = true

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
            ScrollView {
                form.padding(20)
            }
        }
        .frame(minWidth: 500, idealWidth: 500, maxWidth: 500, minHeight: 500, idealHeight: 500, maxHeight: 500)
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
            Text(isEditing ? "Edit Commitment" : "New Commitment")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button("Cancel") { cancelEditing() }
                .buttonStyle(.borderless)
            Button(isEditing ? "Update" : "Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func normalizedRecurrenceForDraft() -> Recurrence? {
        guard allowsRecurrence else { return nil }
        var r = buildRecurrence()
        r?.startDate = eventDate
        return r
    }

    private func currentDraftSnapshot() -> CommitmentDraftBaseline {
        CommitmentDraftBaseline(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: FinancialCurrencyFormatting.parseDecimalInput(amount) ?? 0,
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
        if KommitViewModel.showDiscardConfirmation(
            messageText: "Discard changes?",
            informativeText: "Your edits to this commitment will be lost."
        ) {
            dismiss()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldGroup("Details") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Name")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    KommitTextField("e.g. Rent, Salary", text: $name)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Type")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TypeSegmentedControl(selection: $type)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Amount")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(viewModel.effectiveFinancialCurrencySymbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            KommitTextField("0.00", text: $amount)
                        }
                    }
                    .frame(width: 130)
                }

                Toggle(isOn: $isActive) {
                    Text("Active")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            FieldGroup("Schedule") {
                SelectableCalendarDateRow(title: "Date", date: $eventDate)

                if allowsRecurrence {
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
                } else {
                    Text("This commitment will be created as a one-off due item.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            FieldGroup("Tags") {
                TagInputField(
                    tags: $tags,
                    input: $tagInput,
                    suggestions: tagSuggestions
                )
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
            amount = FinancialCurrencyFormatting.editorAmountString(existing.amount)
            tags = existing.tags
            isActive = existing.isActive
            eventDate = existing.createdAt

            if allowsRecurrence {
                let preset = presetForRecurrence(existing.recurrence)
                selectedPreset = preset
                if preset == .custom {
                    customRecurrence = existing.recurrence
                }
            } else {
                selectedPreset = .doesNotRepeat
                customRecurrence = nil
            }
        } else if let seed {
            name = seed.name
            type = seed.type
            amount = FinancialCurrencyFormatting.editorAmountString(seed.amount)
            tags = seed.tags
            isActive = true
            eventDate = seed.eventDate
            selectedPreset = .doesNotRepeat
            customRecurrence = nil
        }
        captureDraftBaseline()
    }

    private func save() {
        let amountValue = FinancialCurrencyFormatting.parseDecimalInput(amount) ?? 0
        var recurrence = allowsRecurrence ? buildRecurrence() : nil
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
        onSaveCommitment?(saved)
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
