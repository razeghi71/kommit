import SwiftUI

// MARK: - Financial planning list (commitments + forecasts)

enum FinancialPlanningUserDefaultsKey {
    /// When true (default), commitments that are fully paid and in the past are hidden from the planning list.
    static let hideFullyPaidCommitments = "kommit.financialPlanning.hideFullyPaidCommitments"
}

struct FinancialPlanningListView: View {
    /// Minimum width to show commitments and forecasts in two columns.
    private static let sideBySideBreakpoint: CGFloat = 960

    @ObservedObject var viewModel: KommitViewModel
    @AppStorage(FinancialPlanningUserDefaultsKey.hideFullyPaidCommitments) private var hideFullyPaidCommitments = true
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
        let base = viewModel.commitments.values.sorted { $0.name < $1.name }
        guard hideFullyPaidCommitments else { return base }
        return base.filter { !viewModel.commitmentIsFullyPaid($0) }
    }

    private var commitmentsEmptyHint: String {
        if viewModel.commitments.isEmpty {
            return "No commitments yet. Add rent, salary, subscriptions—items you mark paid when they happen."
        }
        return "Fully paid commitments are hidden. Turn off \"Hide fully paid commitments\" in Settings (Financial) to show them."
    }

    private var sortedForecasts: [Forecast] {
        viewModel.forecasts.values.sorted { $0.name < $1.name }
    }

    private var entriesTable: some View {
        GeometryReader { geo in
            ScrollView {
                if geo.size.width >= Self.sideBySideBreakpoint {
                    HStack(alignment: .top, spacing: 16) {
                        commitmentsSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                        planningColumnSeparator
                        forecastsSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                } else {
                    stackedPlanningList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Commitments on top, forecasts below (narrow widths).
    private var stackedPlanningList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            commitmentsSection
            forecastsSection
        }
    }

    private var commitmentsSection: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            sectionHeader("Commitments")
            if sortedCommitments.isEmpty {
                emptyHint(commitmentsEmptyHint)
            }
            ForEach(sortedCommitments) { entry in
                CommitmentRow(
                    commitment: entry,
                    viewModel: viewModel,
                    onEdit: { editingCommitment = entry },
                    onDelete: {
                        viewModel.deleteCommitment(entry.id)
                    }
                )
                Divider()
            }
        }
    }

    private var forecastsSection: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            sectionHeader("Forecasts")
            if sortedForecasts.isEmpty {
                emptyHint("No forecasts yet. Add typical spending like groceries or lunch—shown in the calendar as estimates, not due items.")
            }
            ForEach(sortedForecasts) { entry in
                ForecastRow(
                    forecast: entry,
                    viewModel: viewModel,
                    onEdit: { editingForecast = entry },
                    onDelete: {
                        viewModel.deleteForecast(entry.id)
                    }
                )
                Divider()
            }
        }
    }

    private var planningColumnSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 6)
            .accessibilityHidden(true)
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
    @ObservedObject var viewModel: KommitViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
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

            Text(commitment.type == .income ? "+\(viewModel.formatFinancialCurrencyUnsigned(commitment.amount))" : "-\(viewModel.formatFinancialCurrencyUnsigned(commitment.amount))")
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
}

struct ForecastRow: View {
    let forecast: Forecast
    @ObservedObject var viewModel: KommitViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(forecast.name.isEmpty ? "Untitled" : forecast.name)
                        .font(.system(size: 14, weight: .medium))
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

            Text(forecast.type == .income ? "+\(viewModel.formatFinancialCurrencyUnsigned(forecast.amount))" : "-\(viewModel.formatFinancialCurrencyUnsigned(forecast.amount))")
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
}
