import SwiftUI

// MARK: - Transaction Editor

struct FinancialTransactionDraftBaseline: Equatable {
    var kind: FinancialTransactionKind
    var name: String
    var type: FinancialFlowType
    var amount: Double
    var date: Date
    var tags: [String]
    var note: String?
    var forecastID: UUID?
    var deferredTo: CommitmentOccurrenceRef?
    var settles: CommitmentOccurrenceRef?
}

private enum TransactionCommitmentLinkRole {
    case deferred
    case settlement
}

private enum RecordedTransactionPaymentMode: String, CaseIterable, Identifiable {
    case payNow
    case deferredToCommitment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payNow: "Pay on recorded date"
        case .deferredToCommitment: "Pay later by a commitment"
        }
    }
}

struct TransactionEditorView: View {
    @ObservedObject var viewModel: KommitViewModel
    let transaction: FinancialTransaction?
    let defaultMonth: Int
    let defaultYear: Int
    var prefilledCommitmentID: UUID?
    var prefilledDueDate: Date?
    var prefilledForecastID: UUID?
    var prefilledPaymentDate: Date?

    @Environment(\.dismiss) private var dismiss

    @State private var kind: FinancialTransactionKind = .recorded
    @State private var name: String = ""
    @State private var type: FinancialFlowType = .expense
    @State private var amount: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var selectedForecastID: UUID?
    @State private var recordedPaymentMode: RecordedTransactionPaymentMode = .payNow
    @State private var deferredCommitmentID: UUID?
    @State private var deferredDueDate: Date = Date()
    @State private var settlementCommitmentID: UUID?
    @State private var settlementDueDate: Date = Date()
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var draftBaseline: FinancialTransactionDraftBaseline?
    @State private var showingCommitmentSheet = false
    @State private var commitmentSheetRole: TransactionCommitmentLinkRole = .deferred

    var isEditing: Bool { transaction != nil }

    private var hasUnsavedDraft: Bool {
        guard let draftBaseline else { return false }
        return currentDraftSnapshot() != draftBaseline
    }

    private var amountValue: Double {
        Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var usesDeferredCommitmentAmount: Bool {
        kind == .recorded && showsDeferredCommitmentSection && deferredCommitmentID != nil
    }

    private var resolvedAmountValue: Double {
        if let deferredCommitmentID, usesDeferredCommitmentAmount {
            return viewModel.expectedCommitmentAmount(for: deferredCommitmentID, dueDate: deferredDueDate)
        }
        return amountValue
    }

    private var storedAmountValue: Double {
        usesDeferredCommitmentAmount ? 0 : amountValue
    }

    private var showsDeferredCommitmentSection: Bool {
        kind == .recorded && recordedPaymentMode == .deferredToCommitment
    }

    private var planningIsValid: Bool {
        switch kind {
        case .recorded:
            return true
        case .settlement:
            return settlementCommitmentID != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                form.padding(20)
            }
        }
        .frame(width: 520, height: 650)
        .interactiveDismissDisabled(hasUnsavedDraft)
        .onAppear { loadTransaction() }
        .onChange(of: type) { _, newType in
            guard kind == .recorded, newType == .income else { return }
            recordedPaymentMode = .payNow
            deferredCommitmentID = nil
            deferredDueDate = date
        }
        .onChange(of: settlementDueDate) { _, newDate in
            guard kind == .settlement, let settlementCommitmentID else { return }
            amount = String(format: "%.2f", viewModel.expectedCommitmentAmount(for: settlementCommitmentID, dueDate: newDate))
        }
        .sheet(isPresented: $showingCommitmentSheet) {
            CommitmentEditorView(
                viewModel: viewModel,
                commitment: nil,
                seed: commitmentSeed(),
                onSaveCommitment: { commitment in
                    handleNewCommitment(commitment)
                },
                allowsRecurrence: false
            )
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
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !planningIsValid)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func currentDraftSnapshot() -> FinancialTransactionDraftBaseline {
        FinancialTransactionDraftBaseline(
            kind: kind,
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: resolvedAmountValue,
            date: date,
            tags: tags,
            note: note.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            forecastID: kind == .recorded ? selectedForecastID : nil,
            deferredTo: kind == .recorded ? currentDeferredRef : nil,
            settles: kind == .settlement ? currentSettlementRef : nil
        )
    }

    private var currentDeferredRef: CommitmentOccurrenceRef? {
        guard let deferredCommitmentID else { return nil }
        return CommitmentOccurrenceRef(commitmentID: deferredCommitmentID, dueDate: deferredDueDate)
    }

    private var currentSettlementRef: CommitmentOccurrenceRef? {
        guard let settlementCommitmentID else { return nil }
        return CommitmentOccurrenceRef(commitmentID: settlementCommitmentID, dueDate: settlementDueDate)
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
            informativeText: "Your edits to this transaction will be lost."
        ) {
            dismiss()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldGroup("Transaction Type") {
                Picker("", selection: $kind) {
                    Text("Recorded").tag(FinancialTransactionKind.recorded)
                    Text("Settlement").tag(FinancialTransactionKind.settlement)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: kind) { _, newKind in
                    switch newKind {
                    case .recorded:
                        settlementCommitmentID = nil
                        settlementDueDate = date
                    case .settlement:
                        selectedForecastID = nil
                        recordedPaymentMode = .payNow
                        deferredCommitmentID = nil
                        deferredDueDate = date
                    }
                }

                Text(kind == .recorded
                    ? "Recorded transactions capture the real-world purchase or income event. You can optionally attribute them to a forecast and defer them to a later bill."
                    : "Settlement transactions clear a commitment occurrence when you actually pay it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if kind == .recorded {
                forecastSection
                recordedDetailsSection
                paymentSection
            } else {
                settlementDetailsSection
                settlementSection
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

    private var recordedDetailsSection: some View {
        FieldGroup("Details") {
            VStack(alignment: .leading, spacing: 3) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. Groceries, Rent payment", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            DatePicker("Recorded on", selection: $date, displayedComponents: .date)
        }
    }

    private var settlementDetailsSection: some View {
        FieldGroup("Details") {
            VStack(alignment: .leading, spacing: 3) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. Rent payment", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Type")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $type) {
                        ForEach(FinancialFlowType.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
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
            }

            DatePicker("Settled on", selection: $date, displayedComponents: .date)
        }
    }

    private var forecastSection: some View {
        FieldGroup("Forecast") {
            LabeledContent("Forecast") {
                Picker("", selection: $selectedForecastID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(Array(viewModel.forecasts.values).sorted { $0.name < $1.name }) { item in
                        Text(item.name.isEmpty ? "Untitled" : item.name).tag(item.id as UUID?)
                    }
                }
                .onChange(of: selectedForecastID) { _, id in
                    applyForecastSelection(id)
                }
            }
        }
    }

    private var paymentSection: some View {
        FieldGroup("Payment") {
            VStack(alignment: .leading, spacing: 3) {
                Text("Type")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $type) {
                    ForEach(FinancialFlowType.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if type == .expense {
                Picker("", selection: $recordedPaymentMode) {
                    ForEach(RecordedTransactionPaymentMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: recordedPaymentMode) { _, newMode in
                    switch newMode {
                    case .payNow:
                        deferredCommitmentID = nil
                        deferredDueDate = date
                    case .deferredToCommitment:
                        if deferredCommitmentID == nil {
                            deferredDueDate = date
                        }
                    }
                }
            }

            if type == .income || recordedPaymentMode == .payNow {
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
            } else if showsDeferredCommitmentSection {
                Text("For forecast tracking in the Summary tab, this will still count on the recorded date.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.72, green: 0.48, blue: 0.02))
                    .fixedSize(horizontal: false, vertical: true)

                commitmentPicker(
                    title: "Commitment",
                    selection: $deferredCommitmentID,
                    onChange: { _, id in applyCommitmentSelection(id, role: .deferred) },
                    items: deferEligibleCommitments,
                    onNew: {
                        commitmentSheetRole = .deferred
                        showingCommitmentSheet = true
                    }
                )

                if deferredCommitmentID != nil {
                    Text("Recorded transaction amount will be taken from the deferred commitment.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var settlementSection: some View {
        FieldGroup("Commitment Settlement") {
            commitmentPicker(
                title: "Commitment",
                selection: $settlementCommitmentID,
                onChange: { _, id in applyCommitmentSelection(id, role: .settlement) },
                items: Array(viewModel.commitments.values).sorted { $0.name < $1.name },
                onNew: {
                    commitmentSheetRole = .settlement
                    showingCommitmentSheet = true
                }
            )

            commitmentOccurrencePicker(
                commitmentID: settlementCommitmentID,
                dueDate: $settlementDueDate
            )
        }
    }

    private func commitmentPicker(
        title: String,
        selection: Binding<UUID?>,
        onChange: @escaping (UUID?, UUID?) -> Void,
        items: [Commitment],
        onNew: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            LabeledContent(title) {
                Picker("", selection: selection) {
                    Text("Choose…").tag(nil as UUID?)
                    ForEach(items) { item in
                        Text(commitmentPickerLabel(for: item)).tag(item.id as UUID?)
                    }
                }
                .onChange(of: selection.wrappedValue, onChange)
            }

            Button("New…", action: onNew)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var deferEligibleCommitments: [Commitment] {
        viewModel.commitments.values
            .filter { !$0.isRecurring && $0.type == .expense }
            .sorted { $0.name < $1.name }
    }

    private func commitmentPickerLabel(for commitment: Commitment) -> String {
        let name = commitment.name.isEmpty ? "Untitled" : commitment.name
        let amountPrefix = commitment.type == .income ? "+$" : "-$"
        return "\(name) - \(amountPrefix)\(formatMoney(commitment.amount))"
    }

    @ViewBuilder
    private func commitmentOccurrencePicker(commitmentID: UUID?, dueDate: Binding<Date>) -> some View {
        if let commitmentID, let commitment = viewModel.commitments[commitmentID] {
            if commitment.isRecurring {
                let instances = computeInstances(for: commitment)
                LabeledContent("Occurrence") {
                    Picker("", selection: dueDate) {
                        ForEach(instances, id: \.self) { date in
                            Text(Self.instanceDateFormatter.string(from: date)).tag(date)
                        }
                    }
                }
            } else {
                HStack {
                    Text("Occurrence")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.instanceDateFormatter.string(from: commitment.createdAt))
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    private func computeInstances(for commitment: Commitment) -> [Date] {
        FinancialRecurrence.recurrenceInstances(
            for: commitment,
            centerMonth: defaultMonth,
            centerYear: defaultYear,
            calendar: Calendar.current
        )
    }

    private func nearestInstance(for commitment: Commitment) -> Date {
        let instances = computeInstances(for: commitment)
        let cal = Calendar.current
        guard !instances.isEmpty else { return commitment.createdAt }
        let anchor = cal.date(from: DateComponents(year: defaultYear, month: defaultMonth, day: 15)) ?? Date()
        return instances.min(by: { abs($0.timeIntervalSince(anchor)) < abs($1.timeIntervalSince(anchor)) }) ?? instances[0]
    }

    private func resolveOccurrence(for commitment: Commitment, storedDate: Date) -> Date {
        guard commitment.isRecurring else { return commitment.createdAt }
        let instances = computeInstances(for: commitment)
        return FinancialRecurrence.matchingOccurrence(
            in: instances,
            forStoredDueDate: storedDate,
            calendar: Calendar.current
        ) ?? nearestInstance(for: commitment)
    }

    private func applyCommitmentSelection(_ id: UUID?, role: TransactionCommitmentLinkRole) {
        guard let id, let commitment = viewModel.commitments[id] else {
            switch role {
            case .deferred:
                deferredDueDate = date
            case .settlement:
                settlementDueDate = date
            }
            return
        }

        switch role {
        case .deferred:
            deferredDueDate = commitment.createdAt
        case .settlement:
            if !isEditing {
                name = commitment.name
                type = commitment.type
                amount = String(format: "%.2f", viewModel.expectedCommitmentAmount(for: commitment.id, dueDate: commitment.createdAt))
                tags = commitment.tags
            }
            let due = commitment.isRecurring ? nearestInstance(for: commitment) : commitment.createdAt
            settlementDueDate = due
            amount = String(format: "%.2f", viewModel.expectedCommitmentAmount(for: commitment.id, dueDate: due))
        }
    }

    private func applyForecastSelection(_ id: UUID?) {
        guard let id, let forecast = viewModel.forecasts[id] else { return }
        if !isEditing {
            name = forecast.name
            type = forecast.type
            amount = String(format: "%.2f", forecast.amount)
            tags = forecast.tags
        }
    }

    private func commitmentSeed() -> CommitmentEditorSeed {
        let suggestedDate: Date
        switch commitmentSheetRole {
        case .deferred:
            suggestedDate = deferredDueDate
        case .settlement:
            suggestedDate = settlementDueDate
        }
        return CommitmentEditorSeed(
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "New commitment" : name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: usesDeferredCommitmentAmount ? resolvedAmountValue : amountValue,
            eventDate: suggestedDate,
            tags: tags
        )
    }

    private func handleNewCommitment(_ commitment: Commitment) {
        switch commitmentSheetRole {
        case .deferred:
            deferredCommitmentID = commitment.id
            deferredDueDate = commitment.createdAt
            applyCommitmentSelection(commitment.id, role: .deferred)
        case .settlement:
            settlementCommitmentID = commitment.id
            settlementDueDate = commitment.createdAt
            applyCommitmentSelection(commitment.id, role: .settlement)
        }
    }

    private static let instanceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private func loadTransaction() {
        if let txn = transaction {
            kind = txn.kind
            name = txn.name
            type = txn.type
            amount = String(format: "%.2f", viewModel.resolvedTransactionAmount(txn))
            date = txn.date
            tags = txn.tags
            note = txn.note ?? ""
            selectedForecastID = txn.forecastID
            recordedPaymentMode = txn.deferredTo == nil ? .payNow : .deferredToCommitment
            deferredCommitmentID = txn.deferredTo?.commitmentID
            settlementCommitmentID = txn.settles?.commitmentID

            if let deferredTo = txn.deferredTo,
               let commitment = viewModel.commitments[deferredTo.commitmentID] {
                deferredDueDate = resolveOccurrence(for: commitment, storedDate: deferredTo.dueDate)
            } else {
                deferredDueDate = txn.date
            }

            if let settles = txn.settles,
               let commitment = viewModel.commitments[settles.commitmentID] {
                settlementDueDate = resolveOccurrence(for: commitment, storedDate: settles.dueDate)
            } else {
                settlementDueDate = txn.date
            }
        } else if let prefilledCommitmentID {
            kind = .settlement
            recordedPaymentMode = .payNow
            settlementCommitmentID = prefilledCommitmentID
            if let commitment = viewModel.commitments[prefilledCommitmentID] {
                let due = prefilledDueDate.map { resolveOccurrence(for: commitment, storedDate: $0) }
                    ?? (commitment.isRecurring ? nearestInstance(for: commitment) : commitment.createdAt)
                settlementDueDate = due
                name = commitment.name
                type = commitment.type
                amount = String(format: "%.2f", viewModel.expectedCommitmentAmount(for: commitment.id, dueDate: due))
                tags = commitment.tags
            }
        } else if let prefilledForecastID {
            kind = .recorded
            recordedPaymentMode = .payNow
            selectedForecastID = prefilledForecastID
            applyForecastSelection(prefilledForecastID)
            if let prefilledPaymentDate {
                date = prefilledPaymentDate
                deferredDueDate = prefilledPaymentDate
                settlementDueDate = prefilledPaymentDate
            }
        }

        captureDraftBaseline()
    }

    private func save() {
        let saved = FinancialTransaction(
            id: transaction?.id ?? UUID(),
            kind: kind,
            forecastID: kind == .recorded ? selectedForecastID : nil,
            deferredTo: kind == .recorded ? currentDeferredRef : nil,
            settles: kind == .settlement ? currentSettlementRef : nil,
            name: name.trimmingCharacters(in: .whitespaces),
            amount: storedAmountValue,
            type: type,
            date: date,
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
        let existingTags = viewModel.allFinancialTags() + viewModel.allTransactionTags()
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

    private func formatMoney(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}
