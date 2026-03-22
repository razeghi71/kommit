import SwiftUI

private enum CanvasWorkspace: String, CaseIterable, Identifiable {
    case graph
    case table

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graph: "Graph"
        case .table: "Table"
        }
    }
}

private struct CanvasWorkspaceTabs: View {
    @Binding var selection: CanvasWorkspace
    private let buttonCornerRadius: CGFloat = 7

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CanvasWorkspace.allCases) { mode in
                let isSelected = selection == mode

                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
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

struct ContentView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var workspace: CanvasWorkspace = .graph
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var currentSearchIndex = -1
    @State private var lastSearchedQuery = ""
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CanvasWorkspaceTabs(selection: $workspace)

                HStack {
                    Spacer(minLength: 0)
                    if isSearchPresented {
                        searchField
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .zIndex(1)

            Group {
                switch workspace {
                case .graph:
                    CanvasView(viewModel: viewModel)
                case .table:
                    NodesTableView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(0)
        }
        .onChange(of: workspace) { _, newWorkspace in
            guard let selectedNodeID = viewModel.selectedNodeID else { return }
            switch newWorkspace {
            case .graph:
                viewModel.selectSingleNode(selectedNodeID)
                DispatchQueue.main.async {
                    viewModel.requestCanvasFocus(on: selectedNodeID)
                }
            case .table:
                DispatchQueue.main.async {
                    viewModel.requestTableFocus(on: selectedNodeID)
                }
            }
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

        switch workspace {
        case .graph:
            viewModel.requestCanvasFocus(on: nodeID)
        case .table:
            viewModel.requestTableFocus(on: nodeID)
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchMatches: [DominoNode] {
        guard !trimmedSearchText.isEmpty else { return [] }
        let matches = viewModel.visibleNodes.filter {
            $0.text.localizedCaseInsensitiveContains(trimmedSearchText)
        }
        switch workspace {
        case .graph:
            return matches.sorted { lhs, rhs in
                if lhs.position.y != rhs.position.y { return lhs.position.y < rhs.position.y }
                if lhs.position.x != rhs.position.x { return lhs.position.x < rhs.position.x }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        case .table:
            return matches
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
