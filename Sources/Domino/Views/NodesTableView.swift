import AppKit
import SwiftUI

struct NodesTableView: View {
    @ObservedObject var viewModel: DominoViewModel

    private static func colorDot(hex: String) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let color = NSColor(Color(hex: hex))
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if viewModel.visibleNodes.isEmpty {
                    ContentUnavailableView(
                        "No nodes",
                        systemImage: "rectangle.on.rectangle.slash",
                        description: Text("Add nodes in the graph view, or show hidden items if they are filtered out.")
                    )
                } else {
                    // Two tables: conditional `TableColumn` requires macOS 14.4+ in SwiftUI.
                    Group {
                        if viewModel.showHiddenItems {
                            Table(viewModel.visibleNodes, selection: tableSelection) {
                                Self.sharedTableColumns(viewModel: viewModel)
                                TableColumn("Hidden") { node in
                                    Text(node.isHidden ? "Yes" : "No")
                                        .foregroundStyle(node.isHidden ? .secondary : .primary)
                                }
                                .width(min: 56, ideal: 72)
                            }
                        } else {
                            Table(viewModel.visibleNodes, selection: tableSelection) {
                                Self.sharedTableColumns(viewModel: viewModel)
                            }
                        }
                    }
                }
            }
            .onAppear {
                focusSelectedNode(using: proxy)
            }
            .onChange(of: viewModel.selectedNodeID) { _, _ in
                focusSelectedNode(using: proxy)
            }
            .onChange(of: viewModel.tableFocusRequest) { _, request in
                guard let request else { return }
                focusNode(request.nodeID, using: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tableSelection: Binding<UUID?> {
        Binding(
            get: {
                guard let selectedNodeID = viewModel.selectedNodeID,
                    viewModel.visibleNodes.contains(where: { $0.id == selectedNodeID })
                else {
                    return nil
                }
                return selectedNodeID
            },
            set: { newValue in
                guard let newValue else {
                    viewModel.clearSelection()
                    return
                }
                viewModel.selectSingleNode(newValue)
            }
        )
    }

    private func focusSelectedNode(using proxy: ScrollViewProxy) {
        guard let selectedNodeID = viewModel.selectedNodeID else { return }
        focusNode(selectedNodeID, using: proxy)
    }

    private func focusNode(_ nodeID: UUID, using proxy: ScrollViewProxy) {
        guard viewModel.visibleNodes.contains(where: { $0.id == nodeID }) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(nodeID, anchor: .center)
            }
        }
    }
}

extension NodesTableView {
    @TableColumnBuilder<DominoNode, Never>
    fileprivate static func sharedTableColumns(viewModel: DominoViewModel) -> some TableColumnContent<DominoNode, Never> {
        TableColumn("Text") { node in
            NodeTableTextField(nodeID: node.id, viewModel: viewModel)
        }
        .width(min: 160, ideal: 280)

        TableColumn("Color") { node in
            NodeTableColorMenu(nodeID: node.id, viewModel: viewModel, colorDot: Self.colorDot)
        }
        .width(min: 100, ideal: 120)

        TableColumn("Plan date") { node in
            NodeTablePlannedDateCell(nodeID: node.id, viewModel: viewModel)
        }
        .width(min: 120, ideal: 140)

        TableColumn("Budget") { node in
            NodeTableBudgetField(nodeID: node.id, viewModel: viewModel)
        }
        .width(min: 100, ideal: 120)
    }
}

// MARK: - Text (same as graph node label)

private struct NodeTableTextField: View {
    let nodeID: UUID
    @ObservedObject var viewModel: DominoViewModel
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(" "), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...8)
            .focused($focused)
            .onAppear { syncFromNode() }
            .onChange(of: viewModel.nodes[nodeID]?.text) { _, _ in
                if !focused { syncFromNode() }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func syncFromNode() {
        text = viewModel.nodes[nodeID]?.text ?? ""
    }

    private func commit() {
        viewModel.commitNodeTextIfChanged(nodeID, text: text)
    }
}

// MARK: - Color

/// Bitmap swatch for the menu label. SwiftUI `Menu` labels inside `Table` rows are often rendered as
/// monochrome template content, which washes out `Shape` fills; AppKit drawing preserves true color.
private enum ColorSwatchLabelImage {
    static let pixelSize = NSSize(width: 88, height: 26)

    static func make(hex: String?) -> NSImage {
        let image = NSImage(size: pixelSize, flipped: false) { bounds in
            let rect = bounds.insetBy(dx: 1, dy: 1)
            let corner: CGFloat = 6
            let rounded = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

            let trimmed = hex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                let fill = NSColor(Color(hex: trimmed)).usingColorSpace(.sRGB) ?? .systemGray
                fill.setFill()
                rounded.fill()
                NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
                rounded.lineWidth = 1
                rounded.stroke()

                if let preset = NodeColorPresets.preset(matchingStoredHex: trimmed) {
                    let text = preset.name as NSString
                    let lum =
                        0.2126 * fill.redComponent + 0.7152 * fill.greenComponent
                        + 0.0722 * fill.blueComponent
                    let labelColor =
                        lum > 0.55
                        ? NSColor.black.withAlphaComponent(0.88)
                        : NSColor.white.withAlphaComponent(0.95)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: labelColor,
                    ]
                    let ts = text.size(withAttributes: attrs)
                    let origin = CGPoint(x: bounds.midX - ts.width / 2, y: bounds.midY - ts.height / 2)
                    text.draw(at: origin, withAttributes: attrs)
                }
            } else {
                NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
                rounded.lineWidth = 1
                let dashes: [CGFloat] = [4, 3]
                rounded.setLineDash(dashes, count: dashes.count, phase: 0)
                rounded.stroke()

                let text = "None" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                let ts = text.size(withAttributes: attrs)
                let origin = CGPoint(x: bounds.midX - ts.width / 2, y: bounds.midY - ts.height / 2)
                text.draw(at: origin, withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct NodeTableColorMenu: View {
    let nodeID: UUID
    @ObservedObject var viewModel: DominoViewModel
    let colorDot: (String) -> NSImage

    private var hex: String? {
        viewModel.nodes[nodeID]?.colorHex
    }

    private var menuBaseColor: Color {
        guard let hex else { return .white }
        return Color(hex: hex)
    }

    var body: some View {
        Menu {
            Button("None") {
                viewModel.setNodeColor(nodeID, hex: nil)
            }
            ForEach(NodeColorPresets.presets, id: \.hex) { preset in
                Button {
                    viewModel.setNodeColor(nodeID, hex: preset.hex)
                } label: {
                    Label {
                        Text(preset.name)
                    } icon: {
                        Image(nsImage: colorDot(preset.hex))
                    }
                }
            }
            Divider()
            Button("Custom…") {
                let vm = viewModel
                let id = nodeID
                let panel = NSColorPanel.shared
                panel.setTarget(nil)
                panel.setAction(nil)
                panel.color = NSColor(menuBaseColor)
                panel.orderFront(nil)
                ColorPanelObserver.shared.observe(panel: panel) { nsColor in
                    vm.setNodeColor(id, hex: Color(nsColor: nsColor).toHex())
                }
            }
        } label: {
            Image(nsImage: ColorSwatchLabelImage.make(hex: hex))
                .interpolation(.high)
                .frame(width: ColorSwatchLabelImage.pixelSize.width, height: ColorSwatchLabelImage.pixelSize.height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let hex, !hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Color: none"
        }
        if let preset = NodeColorPresets.preset(matchingStoredHex: hex) {
            return "Color: \(preset.name)"
        }
        return "Color: custom"
    }
}

// MARK: - Planned date

private struct NodeTablePlannedDateCell: View {
    let nodeID: UUID
    @ObservedObject var viewModel: DominoViewModel

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        if let date = viewModel.nodes[nodeID]?.plannedDate {
            Button(Self.displayFormatter.string(from: date)) {
                openChangePicker()
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Remove Planned Date", role: .destructive) {
                    viewModel.setNodePlannedDate(nodeID, date: nil)
                }
            }
        } else {
            Button("Set date") {
                openSetPicker()
            }
            .buttonStyle(.plain)
        }
    }

    private func openSetPicker() {
        guard let picked = promptForPlannedDate(initialDate: nil) else { return }
        viewModel.setNodePlannedDate(nodeID, date: Calendar.current.startOfDay(for: picked))
    }

    private func openChangePicker() {
        let initial = viewModel.nodes[nodeID]?.plannedDate
        guard let picked = promptForPlannedDate(initialDate: initial) else { return }
        viewModel.setNodePlannedDate(nodeID, date: Calendar.current.startOfDay(for: picked))
    }
}

// MARK: - Budget

private struct NodeTableBudgetField: View {
    let nodeID: UUID
    @ObservedObject var viewModel: DominoViewModel
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { syncFromNode() }
            .onChange(of: viewModel.nodes[nodeID]?.budget) { _, _ in
                if !focused { syncFromNode() }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func syncFromNode() {
        if let budget = viewModel.nodes[nodeID]?.budget {
            text = plainBudgetString(budget)
        } else {
            text = ""
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if viewModel.nodes[nodeID]?.budget != nil {
                viewModel.setNodeBudget(nodeID, budget: nil)
            }
            return
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value.isFinite, value >= 0 else {
            syncFromNode()
            return
        }
        viewModel.setNodeBudget(nodeID, budget: value)
    }

    private func plainBudgetString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
