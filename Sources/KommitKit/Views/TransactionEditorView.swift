import SwiftUI

// MARK: - Transaction Editor

private struct FinancialTransactionDraftBaseline: Equatable {
    var planningMode: TransactionPlanningMode
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

private enum TransactionPlanningMode: String, CaseIterable, Identifiable {
    case none
    case forecast
    case closesCommitment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .forecast: "Part of a forecast"
        case .closesCommitment: "Closes a commitment"
        }
    }
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

    @State private var planningMode: TransactionPlanningMode = .none
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
        FinancialCurrencyFormatting.parseDecimalInput(amount) ?? 0
    }

    private var savedKind: FinancialTransactionKind {
        planningMode == .closesCommitment ? .settlement : .recorded
    }

    private var usesDeferredCommitmentAmount: Bool {
        showsDeferredCommitmentSection && deferredCommitmentID != nil
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
        planningMode == .forecast && type == .expense && recordedPaymentMode == .deferredToCommitment
    }

    private var planningIsValid: Bool {
        switch planningMode {
        case .none:
            return true
        case .forecast:
            guard selectedForecastID != nil else { return false }
            if showsDeferredCommitmentSection {
                return deferredCommitmentID != nil
            }
            return true
        case .closesCommitment:
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
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520, minHeight: 650, idealHeight: 650, maxHeight: 650)
        .interactiveDismissDisabled(hasUnsavedDraft)
        .onAppear { loadTransaction() }
        .onChange(of: type) { _, newType in
            guard planningMode != .closesCommitment, newType == .income else { return }
            recordedPaymentMode = .payNow
            deferredCommitmentID = nil
            deferredDueDate = date
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
            planningMode: planningMode,
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            amount: resolvedAmountValue,
            date: date,
            tags: tags,
            note: note.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            forecastID: planningMode == .forecast ? selectedForecastID : nil,
            deferredTo: planningMode == .forecast ? currentDeferredRef : nil,
            settles: planningMode == .closesCommitment ? currentSettlementRef : nil
        )
    }

    private var currentDeferredRef: CommitmentOccurrenceRef? {
        guard showsDeferredCommitmentSection, let deferredCommitmentID else { return nil }
        return CommitmentOccurrenceRef(commitmentID: deferredCommitmentID, dueDate: deferredDueDate)
    }

    private var currentSettlementRef: CommitmentOccurrenceRef? {
        guard planningMode == .closesCommitment, let settlementCommitmentID else { return nil }
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
            planningSection

            if planningMode == .forecast {
                forecastSection
            } else if planningMode == .closesCommitment {
                commitmentLinkSection
            }

            detailsSection
            paymentSection
        }
    }

    private var planningSection: some View {
        FieldGroup("Planning") {
            KommitRadioGroup(
                selection: $planningMode,
                options: Array(TransactionPlanningMode.allCases),
                titleFor: { $0.title }
            )
        }
    }

    private var detailsSection: some View {
        FieldGroup("Details") {
            VStack(alignment: .leading, spacing: 3) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                KommitTextField("e.g. Groceries, Rent payment", text: $name)
            }

            SelectableCalendarDateRow(title: "Date", date: $date)

            TagInputField(
                tags: $tags,
                input: $tagInput,
                suggestions: tagSuggestions
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                KommitTextField("Optional", text: $note)
            }
        }
    }

    private var forecastSection: some View {
        FieldGroup("Forecast") {
            linkedPickerRow(title: "Forecast") {
                Picker("", selection: $selectedForecastID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(Array(viewModel.forecasts.values).sorted { $0.name < $1.name }) { item in
                        Text(item.name.isEmpty ? "Untitled" : item.name).tag(item.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedForecastID) { _, id in
                    applyForecastSelection(id)
                }
            }
        }
    }

    private var commitmentLinkSection: some View {
        FieldGroup("Commitment") {
            commitmentPicker(
                title: "Commitment",
                selection: $settlementCommitmentID,
                onChange: { _, id in applyCommitmentSelection(id, role: .settlement) },
                items: Array(viewModel.commitments.values).sorted { $0.name < $1.name },
                onNew: nil
            )

            commitmentOccurrencePicker(
                commitmentID: settlementCommitmentID,
                dueDate: $settlementDueDate
            )
        }
    }

    private var paymentSection: some View {
        FieldGroup("Payment") {
            typePicker

            switch planningMode {
            case .none:
                amountField
            case .forecast:
                if type == .expense {
                    KommitRadioGroup(
                        selection: $recordedPaymentMode,
                        options: Array(RecordedTransactionPaymentMode.allCases),
                        titleFor: { $0.title }
                    )
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
                    amountField
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
                        Text("Transaction amount will be taken from the deferred commitment.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            case .closesCommitment:
                amountField
            }
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Type")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TypeSegmentedControl(selection: $type)
        }
    }

    private var amountField: some View {
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
    }

    private func commitmentPicker(
        title: String,
        selection: Binding<UUID?>,
        onChange: @escaping (UUID?, UUID?) -> Void,
        items: [Commitment],
        onNew: (() -> Void)?
    ) -> some View {
        linkedPickerRow(title: title) {
            Picker("", selection: selection) {
                Text("Choose…").tag(nil as UUID?)
                ForEach(items) { item in
                    Text(commitmentPickerLabel(for: item)).tag(item.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selection.wrappedValue, onChange)
        } trailing: {
            if let onNew {
                Button("New…", action: onNew)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func linkedPickerRow<PickerContent: View, TrailingContent: View>(
        title: String,
        @ViewBuilder picker: () -> PickerContent,
        @ViewBuilder trailing: () -> TrailingContent = { EmptyView() }
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            picker()
                .labelsHidden()
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(1)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deferEligibleCommitments: [Commitment] {
        viewModel.commitments.values
            .filter { !$0.isRecurring && $0.type == .expense }
            .sorted { $0.name < $1.name }
    }

    private func commitmentPickerLabel(for commitment: Commitment) -> String {
        let name = commitment.name.isEmpty ? "Untitled" : commitment.name
        let formatted = viewModel.formatFinancialCurrencyUnsigned(commitment.amount)
        let sign = commitment.type == .income ? "+" : "-"
        return "\(name) - \(sign)\(formatted)"
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
            let due = commitment.isRecurring ? nearestInstance(for: commitment) : commitment.createdAt
            settlementDueDate = due
            if !isEditing {
                name = commitment.name
                type = commitment.type
                tags = commitment.tags
            amount = FinancialCurrencyFormatting.editorAmountString(
                viewModel.expectedCommitmentAmount(for: commitment.id, dueDate: due)
            )
            }
        }
    }

    private func applyForecastSelection(_ id: UUID?) {
        guard let id, let forecast = viewModel.forecasts[id] else { return }
        if !isEditing {
            name = forecast.name
            type = forecast.type
            amount = FinancialCurrencyFormatting.editorAmountString(forecast.amount)
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
            planningMode = planningMode(for: txn)
            name = txn.name
            type = txn.type
            amount = FinancialCurrencyFormatting.editorAmountString(viewModel.resolvedTransactionAmount(txn))
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
            planningMode = .closesCommitment
            recordedPaymentMode = .payNow
            settlementCommitmentID = prefilledCommitmentID
            if let commitment = viewModel.commitments[prefilledCommitmentID] {
                let due = prefilledDueDate.map { resolveOccurrence(for: commitment, storedDate: $0) }
                    ?? (commitment.isRecurring ? nearestInstance(for: commitment) : commitment.createdAt)
                settlementDueDate = due
                name = commitment.name
                type = commitment.type
                amount = FinancialCurrencyFormatting.editorAmountString(
                    viewModel.expectedCommitmentAmount(for: commitment.id, dueDate: due)
                )
                tags = commitment.tags
            }
        } else if let prefilledForecastID {
            planningMode = .forecast
            recordedPaymentMode = .payNow
            selectedForecastID = prefilledForecastID
            applyForecastSelection(prefilledForecastID)
            if let prefilledPaymentDate {
                date = prefilledPaymentDate
                deferredDueDate = prefilledPaymentDate
                settlementDueDate = prefilledPaymentDate
            }
        } else if let prefilledPaymentDate {
            date = prefilledPaymentDate
            deferredDueDate = prefilledPaymentDate
            settlementDueDate = prefilledPaymentDate
        }

        captureDraftBaseline()
    }

    private func save() {
        let saved = FinancialTransaction(
            id: transaction?.id ?? UUID(),
            kind: savedKind,
            forecastID: planningMode == .forecast ? selectedForecastID : nil,
            deferredTo: planningMode == .forecast ? currentDeferredRef : nil,
            settles: planningMode == .closesCommitment ? currentSettlementRef : nil,
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
        let existingTags = viewModel.allFinanceTags()
        let selected = Set(tags.map { normalizedTagKey($0) })
        let query = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sort after Set so order is stable on every body pass (Set order is undefined).
        let base = Array(Set(existingTags))
            .filter { !selected.contains(normalizedTagKey($0)) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        guard !query.isEmpty else { return Array(base.prefix(8)) }

        return base
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .prefix(8)
            .map { $0 }
    }

    private func normalizedTagKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func planningMode(for transaction: FinancialTransaction) -> TransactionPlanningMode {
        if transaction.kind == .settlement || transaction.settles != nil {
            return .closesCommitment
        }
        if transaction.forecastID != nil || transaction.deferredTo != nil {
            return .forecast
        }
        return .none
    }
}
