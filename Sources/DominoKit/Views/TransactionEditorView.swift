import SwiftUI

// MARK: - Transaction Editor

struct FinancialTransactionDraftBaseline: Equatable {
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

enum TransactionPlanningLinkKind: String, CaseIterable, Identifiable {
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

struct TransactionEditorView: View {
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
                form.padding(20)
            }
        }
        .frame(width: 500, height: 580)
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
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button("Cancel") { cancelEditing() }
                .buttonStyle(.borderless)
            Button(isEditing ? "Update" : "Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || planningLinkIncomplete)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
        VStack(alignment: .leading, spacing: 16) {
            FieldGroup("Planning Link") {
                LabeledContent("Link to") {
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

                if planningLinkKind != .none {
                    instancePicker
                }
            }

            FieldGroup("Details") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Name")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Rent March", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Type")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $type) {
                            ForEach(FinancialFlowType.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Amount")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Text("$").foregroundStyle(.tertiary)
                            TextField("0.00", text: $amount)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(width: 130)
                }

                DatePicker("Payment date", selection: $date, displayedComponents: .date)
            }

            FieldGroup("Tags & Notes") {
                TagInputField(
                    tags: $tags,
                    input: $tagInput,
                    suggestions: tagSuggestions
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Note")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Optional", text: $note)
                        .textFieldStyle(.roundedBorder)
                }
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
