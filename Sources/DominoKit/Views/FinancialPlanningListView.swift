import SwiftUI

// MARK: - Financial planning list (commitments + forecasts)

struct FinancialPlanningListView: View {
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

struct CommitmentRow: View {
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

            FinancialMetadataStrip(items: commitment.tags)

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

struct ForecastRow: View {
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

            FinancialMetadataStrip(items: forecast.tags)

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
