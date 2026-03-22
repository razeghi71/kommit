import AppKit
import SwiftUI

struct NodesTableView: View {
    @ObservedObject var viewModel: DominoViewModel

    var body: some View {
        Group {
            if viewModel.tableRows.isEmpty {
                ContentUnavailableView(
                    "No nodes",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("Add nodes in the graph view, or show hidden items if they are filtered out.")
                )
            } else {
                DominoNodesAppKitTableView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AppKit table (full-row striping, resizable columns, native selection)

@MainActor
private struct DominoNodesAppKitTableView: NSViewRepresentable {
    @ObservedObject var viewModel: DominoViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.viewModel = viewModel
        coordinator.rows = viewModel.tableRows
        coordinator.lastRenderedRows = viewModel.tableRows
        coordinator.showHidden = viewModel.showHiddenItems
        coordinator.lastShowHidden = viewModel.showHiddenItems

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        let table = NSTableView()
        coordinator.tableView = table
        coordinator.configureTable(table)

        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.applyUpdate(viewModel: viewModel)
    }
}

@MainActor
private final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var viewModel: DominoViewModel
    var rows: [DominoTableRow] = []
    var showHidden: Bool = false
    var lastShowHidden: Bool?
    var lastRenderedRows: [DominoTableRow] = []
    weak var tableView: NSTableView?

    private var isSyncingSelection = false
    private var lastFocusToken: UUID?

    init(viewModel: DominoViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func configureTable(_ table: NSTableView) {
        table.delegate = self
        table.dataSource = self
        table.headerView = NSTableHeaderView()
        table.rowSizeStyle = .default
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.backgroundColor = .clear
        table.usesAutomaticRowHeights = true
        if #available(macOS 11.0, *) {
            table.style = .fullWidth
        }
        rebuildColumns(on: table)
    }

    func rebuildColumns(on table: NSTableView) {
        while let col = table.tableColumns.last {
            table.removeTableColumn(col)
        }
        table.addTableColumn(Self.makeColumn(id: "text", title: "Text", min: 160, width: 280))
        table.addTableColumn(Self.makeColumn(id: "color", title: "Color", min: 100, width: 120))
        table.addTableColumn(Self.makeColumn(id: "date", title: "Plan date", min: 120, width: 140))
        table.addTableColumn(Self.makeColumn(id: "budget", title: "Budget", min: 100, width: 120))
        if showHidden {
            table.addTableColumn(Self.makeColumn(id: "hidden", title: "Hidden", min: 56, width: 72))
        }
    }

    private static func makeColumn(id: String, title: String, min: CGFloat, width: CGFloat) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        col.title = title
        col.minWidth = min
        col.maxWidth = 10_000
        col.width = width
        col.resizingMask = [.autoresizingMask, .userResizingMask]
        return col
    }

    func applyUpdate(viewModel: DominoViewModel) {
        self.viewModel = viewModel
        rows = viewModel.tableRows
        showHidden = viewModel.showHiddenItems

        guard let table = tableView else { return }

        let hiddenChanged = lastShowHidden != viewModel.showHiddenItems
        lastShowHidden = viewModel.showHiddenItems
        let rowsChanged = lastRenderedRows != rows

        if hiddenChanged {
            rebuildColumns(on: table)
        }
        if hiddenChanged || rowsChanged {
            let clipView = table.enclosingScrollView?.contentView
            let preservedOrigin = clipView?.documentVisibleRect.origin
            table.reloadData()
            if let clipView, let preservedOrigin, viewModel.tableFocusRequest?.token == lastFocusToken {
                clipView.scroll(to: preservedOrigin)
                table.reflectScrolledClipView(clipView)
            }
            lastRenderedRows = rows
        }

        syncSelection()

        if let req = viewModel.tableFocusRequest, req.token != lastFocusToken {
            lastFocusToken = req.token
            if let idx = rows.firstIndex(where: { $0.id == req.nodeID }) {
                table.scrollRowToVisible(idx)
                DispatchQueue.main.async { [weak table] in
                    guard let table else { return }
                    table.window?.makeFirstResponder(table)
                }
            }
        }
    }

    func syncSelection() {
        guard let table = tableView else { return }
        isSyncingSelection = true
        defer { isSyncingSelection = false }

        if let sel = viewModel.selectedNodeID, let idx = rows.firstIndex(where: { $0.id == sel }) {
            if table.selectedRowIndexes != IndexSet(integer: idx) {
                table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            }
        } else {
            table.deselectAll(nil)
        }
    }

    // MARK: DataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let rowModel = rows[row]
        let colId = tableColumn?.identifier.rawValue ?? "text"
        let reuseId = NSUserInterfaceItemIdentifier("swiftui.\(colId)")

        let cell: HostingTableCellView
        if let existing = tableView.makeView(withIdentifier: reuseId, owner: nil) as? HostingTableCellView {
            cell = existing
        } else {
            cell = HostingTableCellView()
            cell.identifier = reuseId
        }

        let padded: (AnyView) -> AnyView = { view in
            AnyView(view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading))
        }

        switch colId {
        case "text":
            cell.setRoot(padded(AnyView(NodeTableTextField(nodeID: rowModel.node.id, viewModel: viewModel))))
        case "color":
            cell.setRoot(
                padded(AnyView(NodeTableColorMenu(nodeID: rowModel.node.id, viewModel: viewModel, colorDot: NodesTableColorDot.image)))
            )
        case "date":
            cell.setRoot(padded(AnyView(NodeTablePlannedDateCell(nodeID: rowModel.node.id, viewModel: viewModel))))
        case "budget":
            cell.setRoot(padded(AnyView(NodeTableBudgetField(nodeID: rowModel.node.id, viewModel: viewModel))))
        case "hidden":
            cell.setRoot(
                padded(
                    AnyView(
                        Text(rowModel.node.isHidden ? "Yes" : "No")
                            .foregroundStyle(rowModel.node.isHidden ? .secondary : .primary)
                    )
                )
            )
        default:
            break
        }
        return cell
    }

    // MARK: Delegate

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = GroupStripedNSTableRowView()
        rv.configureStripe(stripeGroupIndex: rows.indices.contains(row) ? rows[row].stripeGroupIndex : 0)
        return rv
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        guard let table = tableView else { return }
        let row = table.selectedRow
        if row >= 0, row < rows.count {
            viewModel.selectSingleNode(rows[row].id)
        } else {
            viewModel.clearSelection()
        }
    }
}

private enum NodesTableColorDot {
    static func image(hex: String) -> NSImage {
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
}

private final class HostingTableCellView: NSTableCellView {
    private var hosting: NSHostingView<AnyView>!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let hv = NSHostingView(rootView: AnyView(EmptyView()))
        hosting = hv
        hv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hv)
        NSLayoutConstraint.activate([
            hv.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            hv.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            hv.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            hv.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRoot(_ view: AnyView) {
        hosting.rootView = view
    }
}

@MainActor
private final class GroupStripedNSTableRowView: NSTableRowView {
    private var stripeColor: NSColor = .controlBackgroundColor

    func configureStripe(stripeGroupIndex: Int) {
        let colors = NSColor.alternatingContentBackgroundColors
        stripeColor =
            colors.isEmpty
            ? .controlBackgroundColor
            : colors[stripeGroupIndex % max(colors.count, 1)]
        needsDisplay = true
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isSelected {
            super.drawBackground(in: dirtyRect)
        } else {
            stripeColor.setFill()
            bounds.fill()
        }
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

/// Bitmap swatch for the menu label. SwiftUI `Menu` labels inside table rows are often rendered as
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
