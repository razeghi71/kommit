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

struct ContentView: View {
    @ObservedObject var viewModel: DominoViewModel
    @State private var workspace: CanvasWorkspace = .graph

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Picker("View", selection: $workspace) {
                    ForEach(CanvasWorkspace.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch workspace {
                case .graph:
                    CanvasView(viewModel: viewModel)
                case .table:
                    NodesTableView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
