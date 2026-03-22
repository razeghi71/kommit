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
        // Automatic row heights + mixed AppKit/SwiftUI cells is a common source of constraint/baseline
        // exceptions inside `NSTableView` (seen when changing status from the table).
        table.usesAutomaticRowHeights = false
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
        table.addTableColumn(Self.makeColumn(id: "status", title: "Status", min: 140, width: 160))
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
            if let clipView, let preservedOrigin, viewModel.tableFocusRequest?.token == lastFocusToken,
                let scrollView = table.enclosingScrollView
            {
                clipView.scroll(to: preservedOrigin)
                scrollView.reflectScrolledClipView(clipView)
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
        if colId == "status" {
            let reuseId = NSUserInterfaceItemIdentifier("appkit.status")
            let cell: StatusPopupTableCellView
            if let existing = tableView.makeView(withIdentifier: reuseId, owner: nil) as? StatusPopupTableCellView {
                cell = existing
            } else {
                cell = StatusPopupTableCellView()
                cell.identifier = reuseId
            }
            cell.configure(nodeID: rowModel.node.id, viewModel: viewModel)
            return cell
        }

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

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        // Compact fixed height (automatic row heights were disabled for stability).
        44
    }
}

private enum NodesTableStatusDot {
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
private final class StatusPopupTableCellView: NSView {
    private enum MenuTag {
        static let none = -1
        static let settings = -2
    }

    private let popupButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private var nodeID: UUID?
    private weak var viewModel: DominoViewModel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        popupButton.controlSize = .small
        popupButton.lineBreakMode = .byTruncatingTail
        popupButton.target = self
        popupButton.action = #selector(handleSelectionChanged(_:))
        addSubview(popupButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(nodeID: UUID, viewModel: DominoViewModel) {
        self.nodeID = nodeID
        self.viewModel = viewModel
        rebuildMenu()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        popupButton.frame = bounds.insetBy(dx: 4, dy: 4)
    }

    private func rebuildMenu() {
        guard let viewModel, let nodeID else { return }

        popupButton.removeAllItems()

        let noneItem = NSMenuItem(title: "None", action: nil, keyEquivalent: "")
        noneItem.tag = MenuTag.none
        noneItem.image = NSImage(systemSymbolName: "circle.slash", accessibilityDescription: nil)
        popupButton.menu?.addItem(noneItem)

        for status in viewModel.activeStatusSettings.selectableStatuses {
            let item = NSMenuItem(title: status.name, action: nil, keyEquivalent: "")
            item.representedObject = status.id.uuidString
            if let hex = status.colorHex {
                item.image = NodesTableStatusDot.image(hex: hex)
            }
            popupButton.menu?.addItem(item)
        }

        popupButton.menu?.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Customized Statuses...", action: nil, keyEquivalent: "")
        settingsItem.tag = MenuTag.settings
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        popupButton.menu?.addItem(settingsItem)

        let currentStatus = viewModel.statusDefinition(for: viewModel.nodes[nodeID]?.statusID)
        if currentStatus.id == DominoStatusSettings.noneStatusID {
            popupButton.selectItem(withTag: MenuTag.none)
        } else {
            let selectedIndex = popupButton.itemArray.firstIndex {
                ($0.representedObject as? String) == currentStatus.id.uuidString
            }
            if let selectedIndex {
                popupButton.selectItem(at: selectedIndex)
            } else {
                popupButton.selectItem(withTag: MenuTag.none)
            }
        }
    }

    @objc private func handleSelectionChanged(_ sender: NSPopUpButton) {
        guard let viewModel, let nodeID, let selectedItem = sender.selectedItem else { return }

        switch selectedItem.tag {
        case MenuTag.settings:
            DispatchQueue.main.async { [weak self] in
                self?.rebuildMenu()
                viewModel.openSettingsWindow()
            }
        case MenuTag.none:
            DispatchQueue.main.async {
                viewModel.setNodeStatus(nodeID, statusID: nil)
            }
        default:
            guard
                let rawStatusID = selectedItem.representedObject as? String,
                let statusID = UUID(uuidString: rawStatusID)
            else {
                DispatchQueue.main.async { [weak self] in
                    self?.rebuildMenu()
                }
                return
            }

            DispatchQueue.main.async {
                viewModel.setNodeStatus(nodeID, statusID: statusID)
            }
        }
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
