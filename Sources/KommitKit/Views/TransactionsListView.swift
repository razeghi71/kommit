import SwiftUI

// MARK: - Transactions List

struct TransactionsListView: View {
    @ObservedObject var viewModel: KommitViewModel
    @State private var showingAddTransaction = false
    @Binding var filterMonth: Int
    @Binding var filterYear: Int
    @State private var editingTransaction: FinancialTransaction?

    init(viewModel: KommitViewModel, filterMonth: Binding<Int>, filterYear: Binding<Int>) {
        self.viewModel = viewModel
        _filterMonth = filterMonth
        _filterYear = filterYear
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
            .buttonStyle(KommitIconButtonStyle())
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

    private func forecastName(for transaction: FinancialTransaction) -> String? {
        guard let forecastID = transaction.forecastID,
              let forecast = viewModel.forecasts[forecastID]
        else { return nil }
        return forecast.name.isEmpty ? "Untitled" : forecast.name
    }

    private func deferredCommitmentName(for transaction: FinancialTransaction) -> String? {
        guard let deferredTo = transaction.deferredTo,
              let commitment = viewModel.commitments[deferredTo.commitmentID]
        else { return nil }
        return commitment.name.isEmpty ? "Untitled" : commitment.name
    }

    private func settlementCommitmentName(for transaction: FinancialTransaction) -> String? {
        guard let settles = transaction.settles,
              let commitment = viewModel.commitments[settles.commitmentID]
        else { return nil }
        return commitment.name.isEmpty ? "Untitled" : commitment.name
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
                            displayAmount: viewModel.resolvedTransactionAmount(txn),
                            forecastName: forecastName(for: txn),
                            deferredCommitmentName: deferredCommitmentName(for: txn),
                            settlementCommitmentName: settlementCommitmentName(for: txn),
                            viewModel: viewModel,
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

struct TransactionRow: View {
    let transaction: FinancialTransaction
    let displayAmount: Double
    let forecastName: String?
    let deferredCommitmentName: String?
    let settlementCommitmentName: String?
    @ObservedObject var viewModel: KommitViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var metadataLines: [String] {
        var lines: [String] = []
        if let forecastName {
            lines.append("Forecast: \(forecastName)")
        }
        if let deferredTo = transaction.deferredTo {
            let due = Self.dateFormatter.string(from: deferredTo.dueDate)
            let title = deferredCommitmentName ?? "Commitment"
            lines.append("Deferred to \(title) · due \(due)")
        }
        if let settles = transaction.settles {
            let due = Self.dateFormatter.string(from: settles.dueDate)
            let title = settlementCommitmentName ?? "Commitment"
            lines.append("Closes \(title) · \(due) occurrence")
        }
        return lines
    }

    private var metadataItems: [String] { transaction.tags }

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.dateFormatter.string(from: transaction.date))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.name.isEmpty ? "Untitled" : transaction.name)
                    .font(.system(size: 14, weight: .medium))
                if !metadataLines.isEmpty {
                    ForEach(metadataLines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 10, weight: .medium))
                            Text(line)
                                .lineLimit(2)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(transaction.type == .income ? "+\(viewModel.formatFinancialCurrencyUnsigned(displayAmount))" : "-\(viewModel.formatFinancialCurrencyUnsigned(displayAmount))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(transaction.type == .income ? .green : .primary)

            FinancialMetadataStrip(items: metadataItems, width: 180)

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

}
