import SwiftUI

// MARK: - Finances Sub-tabs

private enum FinancesTab: String, CaseIterable, Identifiable {
    case financialPlanning
    case transactions
    case calendar
    case summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .financialPlanning: "Financial Planning"
        case .transactions: "Transactions"
        case .calendar: "Calendar"
        case .summary: "Summary"
        }
    }

    var icon: String {
        switch self {
        case .financialPlanning: "calendar.badge.clock"
        case .transactions: "arrow.left.arrow.right"
        case .calendar: "calendar"
        case .summary: "chart.bar.xaxis"
        }
    }
}

// MARK: - Main Finances View

package struct FinancesView: View {
    @ObservedObject var viewModel: KommitViewModel
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
        case .summary:
            FinanceSummaryView(viewModel: viewModel)
        }
    }
}
