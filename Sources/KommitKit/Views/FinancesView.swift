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
    @State private var transactionsFilterMonth: Int
    @State private var transactionsFilterYear: Int
    @State private var summaryFilterMonth: Int
    @State private var summaryFilterYear: Int

    package init(viewModel: KommitViewModel) {
        self.viewModel = viewModel
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let currentMonth = comps.month ?? 1
        let currentYear = comps.year ?? 2026
        _transactionsFilterMonth = State(initialValue: currentMonth)
        _transactionsFilterYear = State(initialValue: currentYear)
        _summaryFilterMonth = State(initialValue: currentMonth)
        _summaryFilterYear = State(initialValue: currentYear)
    }

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
        ZStack {
            tabContent(FinancialPlanningListView(viewModel: viewModel), for: .financialPlanning)
            tabContent(
                TransactionsListView(
                    viewModel: viewModel,
                    filterMonth: $transactionsFilterMonth,
                    filterYear: $transactionsFilterYear
                ),
                for: .transactions
            )
            tabContent(FinanceCalendarView(viewModel: viewModel), for: .calendar)
            tabContent(
                FinanceSummaryView(
                    viewModel: viewModel,
                    filterMonth: $summaryFilterMonth,
                    filterYear: $summaryFilterYear
                ),
                for: .summary
            )
        }
    }

    private func tabContent<Content: View>(_ view: Content, for tab: FinancesTab) -> some View {
        view
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
    }
}
