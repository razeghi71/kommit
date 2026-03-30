import SwiftUI

private enum TopTab: String, CaseIterable, Identifiable {
    case tasks
    case finances

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .finances: "Finances"
        }
    }
}

private struct SegmentedTabs<T: RawRepresentable & CaseIterable & Identifiable & Equatable>: View where T.RawValue == String {
    @Binding var selection: T
    let titleFor: (T) -> String
    private let buttonCornerRadius: CGFloat = 7

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(T.allCases)) { mode in
                let isSelected = selection == mode

                Button {
                    selection = mode
                } label: {
                    Text(titleFor(mode))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.001))
                        }
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

package struct ContentView: View {
    @ObservedObject package var viewModel: KommitViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var topTab: TopTab = .tasks
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var currentSearchIndex = -1
    @State private var lastSearchedQuery = ""
    @FocusState private var searchFieldFocused: Bool

    package init(viewModel: KommitViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        Group {
            if viewModel.shouldShowStartHub {
                StartHubView(viewModel: viewModel)
            } else {
                VStack(spacing: 0) {
                    tabBar
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .zIndex(1)

                    Group {
                        switch topTab {
                        case .tasks:
                            tasksContent
                        case .finances:
                            FinancesView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(0)
                }
            }
        }
        .onAppear {
            viewModel.openSettingsWindowAction = { openWindow(id: "settings") }
        }
        .onChange(of: searchText) { _, _ in
            resetSearchCycle()
        }
        .onChange(of: viewModel.searchPresentationRequest) { _, request in
            guard request != nil else { return }
            showSearch()
        }
        .onExitCommand {
            guard isSearchPresented else { return }
            dismissSearch()
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ZStack {
            SegmentedTabs(selection: $topTab) { $0.title }

            HStack {
                Spacer()
                if topTab == .tasks, isSearchPresented {
                    searchField
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tasks Content

    private var tasksContent: some View {
        CanvasView(viewModel: viewModel)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search nodes", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .onSubmit { performSearch(step: 1) }

            if !trimmedSearchText.isEmpty {
                Text(searchProgressText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(searchMatches.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(searchMatches.isEmpty ? Color.primary.opacity(0.08) : Color.accentColor.opacity(0.14))
                    )
            }

            Button {
                performSearch(step: -1)
            } label: {
                Text("<")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(trimmedSearchText.isEmpty || searchMatches.isEmpty)

            Button {
                performSearch(step: 1)
            } label: {
                Text(">")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(trimmedSearchText.isEmpty || searchMatches.isEmpty)

            Button {
                dismissSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func performSearch(step: Int) {
        guard !searchMatches.isEmpty else { return }
        guard step != 0 else { return }

        let nextIndex: Int
        if lastSearchedQuery == trimmedSearchText {
            nextIndex = wrappedSearchIndex(currentSearchIndex + step, total: searchMatches.count)
        } else {
            nextIndex = step > 0 ? 0 : searchMatches.count - 1
        }

        let nodeID = searchMatches[nextIndex].id
        currentSearchIndex = nextIndex
        lastSearchedQuery = trimmedSearchText
        viewModel.selectSingleNode(nodeID)
        viewModel.requestCanvasFocus(on: nodeID)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchMatches: [KommitNode] {
        guard !trimmedSearchText.isEmpty else { return [] }
        let matches = viewModel.visibleNodes.filter {
            $0.text.localizedCaseInsensitiveContains(trimmedSearchText)
        }
        return matches.sorted { lhs, rhs in
            if lhs.position.y != rhs.position.y { return lhs.position.y < rhs.position.y }
            if lhs.position.x != rhs.position.x { return lhs.position.x < rhs.position.x }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var searchProgressText: String {
        guard !searchMatches.isEmpty else { return "0/0" }
        guard lastSearchedQuery == trimmedSearchText,
            currentSearchIndex >= 0,
            currentSearchIndex < searchMatches.count
        else {
            return "0/\(searchMatches.count)"
        }
        return "\(currentSearchIndex + 1)/\(searchMatches.count)"
    }

    private func resetSearchCycle() {
        currentSearchIndex = -1
        lastSearchedQuery = ""
    }

    private func wrappedSearchIndex(_ index: Int, total: Int) -> Int {
        let remainder = index % total
        return remainder >= 0 ? remainder : remainder + total
    }

    private func showSearch() {
        isSearchPresented = true
        DispatchQueue.main.async {
            searchFieldFocused = true
        }
    }

    private func dismissSearch() {
        isSearchPresented = false
        searchFieldFocused = false
        searchText = ""
        resetSearchCycle()
    }
}
