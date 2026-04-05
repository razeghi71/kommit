import AppKit
import SwiftUI

struct NodeView: View {
    let node: KommitNode
    @ObservedObject var viewModel: KommitViewModel
    let canvasScale: CGFloat
    let onNodeDragChanged: (UUID, CGPoint, CGSize, Bool) -> Void
    let onNodeDragEnded: () -> Void
    let onNodeDragCancelled: () -> Void
    @AppStorage("showNodeRanks") private var showNodeRanks = true
    @State private var isHovering = false
    @State private var editText: String = ""
    @State private var hasActiveNodeDrag = false
    @GestureState private var isNodeDragGestureActive = false
    @FocusState private var textFieldFocused: Bool
    @State private var plannedDateSheetToken: NodePlannedDateSheetToken?

    private var isEditing: Bool {
        viewModel.editingNodeID == node.id
    }

    private var isSelected: Bool {
        viewModel.selectedNodeID == node.id || viewModel.selectedNodeIDs.contains(node.id)
    }

    private var isMultiSelected: Bool {
        viewModel.selectedNodeIDs.contains(node.id)
    }

    private var isDropTarget: Bool {
        viewModel.dropTargetNodeID == node.id
    }

    private var showsSelectionOutline: Bool {
        isSelected
    }

    private var status: KommitStatusDefinition {
        viewModel.statusDefinition(for: node.statusID)
    }

    private var nodeColor: Color? {
        guard let hex = status.colorHex else { return nil }
        return Color(hex: hex)
    }

    private var contextMenuTargetNodeIDs: Set<UUID> {
        viewModel.contextMenuTargetNodeIDs(for: node.id)
    }

    private var areContextMenuTargetsHidden: Bool {
        viewModel.areAllNodesHidden(contextMenuTargetNodeIDs)
    }

    private let minWidth: CGFloat = 100
    private let cornerRadius: CGFloat = 8
    private let selectionOutlinePadding: CGFloat = 4

    private var borderColor: Color {
        nodeColor ?? .primary
    }

    private var borderStroke: Color {
        isDropTarget ? borderColor : borderColor.opacity(0.2)
    }

    private var borderStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: isDropTarget ? 1.5 : 1,
            dash: (viewModel.showHiddenItems && node.isHidden) ? [6, 4] : []
        )
    }

    private var fillColor: Color {
        if isDropTarget, let c = nodeColor {
            return c.opacity(0.12)
        }
        return (nodeColor ?? .white).opacity(0.08)
    }

    private var selectionOutlineOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius + selectionOutlinePadding)
            .stroke(Color.blue, lineWidth: 2)
            .padding(-selectionOutlinePadding)
            .opacity(showsSelectionOutline ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// Reports the card bounds (fill + border) to the model. Kept separate from `selectionOutlineOverlay`,
    /// whose negative padding still participates in layout even at 0 opacity and was inflating stored height.
    private var measuredFrameReporter: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    viewModel.updateNodeMeasuredFrame(id: node.id, size: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    viewModel.updateNodeMeasuredFrame(id: node.id, size: newSize)
                }
        }
    }

    private var nodeSize: CGSize {
        let size = viewModel.effectiveNodeSize(for: node.id)
        return size == .zero ? node.frameSize : size
    }

    private static let plannedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
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

    private static func statusMenuIcon(for status: KommitStatusDefinition) -> Image {
        if let hex = status.colorHex {
            return Image(nsImage: colorDot(hex: hex))
        }
        return Image(systemName: "circle.slash")
    }

    var body: some View {
        ZStack {
            nodeBody
                .overlay(alignment: .topLeading) {
                    if showNodeRanks, let degree = viewModel.nodeDegrees[node.id] {
                        Text("\(degree)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(.primary.opacity(0.08))
                            )
                            .offset(x: -6, y: -6)
                            .allowsHitTesting(false)
                    }
                }
                .contextMenu {
                    Menu {
                        Button {
                            viewModel.setNodeStatuses(contextMenuTargetNodeIDs, statusID: nil)
                        } label: {
                            Label("None", systemImage: "circle.slash")
                        }

                        ForEach(viewModel.activeStatusSettings.selectableStatuses) { status in
                            Button {
                                viewModel.setNodeStatuses(contextMenuTargetNodeIDs, statusID: status.id)
                            } label: {
                                Label {
                                    Text(status.name)
                                } icon: {
                                    Self.statusMenuIcon(for: status)
                                }
                            }
                        }

                        Divider()

                        Button {
                            viewModel.openSettingsWindow()
                        } label: {
                            Label("Edit Status Palette...", systemImage: "gearshape")
                        }
                    } label: {
                        Label("Set Status", systemImage: "flag")
                    }

                    if contextMenuTargetNodeIDs.count > 1 {
                        Menu {
                            Button {
                                viewModel.alignNodes(contextMenuTargetNodeIDs, alignment: .left)
                            } label: {
                                Label("Align Left", systemImage: "align.horizontal.left")
                            }
                            Button {
                                viewModel.alignNodes(contextMenuTargetNodeIDs, alignment: .right)
                            } label: {
                                Label("Align Right", systemImage: "align.horizontal.right")
                            }
                            Button {
                                viewModel.alignNodes(contextMenuTargetNodeIDs, alignment: .top)
                            } label: {
                                Label("Align Top", systemImage: "align.vertical.top")
                            }
                            Button {
                                viewModel.alignNodes(contextMenuTargetNodeIDs, alignment: .bottom)
                            } label: {
                                Label("Align Bottom", systemImage: "align.vertical.bottom")
                            }
                            Button {
                                viewModel.alignNodes(contextMenuTargetNodeIDs, alignment: .horizontalCenter)
                            } label: {
                                Label("Align Horizontal Center", systemImage: "align.horizontal.center")
                            }
                            Button {
                                viewModel.alignNodes(contextMenuTargetNodeIDs, alignment: .verticalCenter)
                            } label: {
                                Label("Align Vertical Center", systemImage: "align.vertical.center")
                            }
                        } label: {
                            Label("Align", systemImage: "align.horizontal.center")
                        }
                    }

                    Divider()

                    if let plannedDate = node.plannedDate {
                        Menu {
                            Button {
                                setPlannedDate(initialDate: plannedDate)
                            } label: {
                                Label("Change Date", systemImage: "calendar.badge.clock")
                            }
                            Button(role: .destructive) {
                                viewModel.setNodePlannedDates(contextMenuTargetNodeIDs, date: nil)
                            } label: {
                                Label("Remove Planned Date", systemImage: "calendar.badge.minus")
                            }
                        } label: {
                            Label(Self.plannedDateFormatter.string(from: plannedDate), systemImage: "calendar")
                        }
                    } else {
                        Button {
                            setPlannedDate(initialDate: nil)
                        } label: {
                            Label("Set Planned Date", systemImage: "calendar.badge.plus")
                        }
                    }

                    if let budget = node.budget {
                        Menu {
                            Button {
                                setBudget(initialBudget: budget)
                            } label: {
                                Label("Change Cost", systemImage: "dollarsign.circle")
                            }
                            Button(role: .destructive) {
                                viewModel.setNodeBudgets(contextMenuTargetNodeIDs, budget: nil)
                            } label: {
                                Label("Remove Cost", systemImage: "dollarsign.circle.fill")
                            }
                        } label: {
                            Label("Cost: \(formattedBudget(budget))", systemImage: "dollarsign.circle")
                        }
                    } else {
                        Button {
                            setBudget(initialBudget: nil)
                        } label: {
                            Label("Set Cost", systemImage: "dollarsign.circle")
                        }
                    }

                    Divider()

                    Button {
                        viewModel.setNodesHidden(
                            contextMenuTargetNodeIDs,
                            isHidden: !areContextMenuTargetsHidden
                        )
                    } label: {
                        if areContextMenuTargetsHidden {
                            Label("Unhide", systemImage: "eye")
                        } else {
                            Label("Hide", systemImage: "eye.slash")
                        }
                    }
                }
            if isHovering && !isEditing {
                plusButtons
            }
        }
        .frame(
            minWidth: nodeSize.width,
            minHeight: nodeSize.height,
            alignment: .topLeading
        )
        .gesture(
            isEditing ? nil :
            DragGesture(minimumDistance: 3, coordinateSpace: .named(KommitCanvasCoordinateSpace.viewportName))
                .updating($isNodeDragGestureActive) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    hasActiveNodeDrag = true
                    let s = max(canvasScale, 0.000_1)
                    let canvasTranslation = CGSize(
                        width: value.translation.width / s,
                        height: value.translation.height / s
                    )
                    onNodeDragChanged(
                        node.id,
                        value.location,
                        canvasTranslation,
                        isMultiSelected && viewModel.selectedNodeIDs.count > 1
                    )
                }
                .onEnded { _ in
                    hasActiveNodeDrag = false
                    onNodeDragEnded()
                }
        )
        .onChange(of: isNodeDragGestureActive) { _, isActive in
            guard !isActive, hasActiveNodeDrag else { return }
            hasActiveNodeDrag = false
            onNodeDragCancelled()
        }
        .onDisappear {
            guard hasActiveNodeDrag else { return }
            hasActiveNodeDrag = false
            onNodeDragCancelled()
        }
        .onHover { isHovering = $0 }
        .sheet(item: $plannedDateSheetToken) { token in
            CalendarDatePickerSheet(
                initialDate: token.initialDate,
                calendar: Calendar.current,
                onDone: { picked in
                    let normalized = Calendar.current.startOfDay(for: picked)
                    viewModel.setNodePlannedDates(contextMenuTargetNodeIDs, date: normalized)
                    plannedDateSheetToken = nil
                },
                onCancel: { plannedDateSheetToken = nil }
            )
        }
    }

    private struct NodePlannedDateSheetToken: Identifiable {
        let id = UUID()
        let initialDate: Date
    }

    @ViewBuilder
    private var nodeBody: some View {
        Group {
            if isEditing {
                editingNodeBody
            } else {
                displayNodeBody
            }
        }
        .background(measuredFrameReporter)
        .overlay(selectionOutlineOverlay)
    }

    private var editingNodeBody: some View {
        TextField("Type here...", text: $editText)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .multilineTextAlignment(.leading)
            .focused($textFieldFocused)
            .frame(minWidth: minWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(nodeColor?.opacity(0.15) ?? .white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(nodeColor ?? Color.accentColor, lineWidth: 1.5)
            )
            .onChange(of: editText) { _, newValue in
                viewModel.updateNodeText(node.id, text: newValue)
            }
            .onSubmit {
                viewModel.commitEditing()
            }
            .onAppear {
                editText = node.text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    textFieldFocused = true
                }
            }
    }

    private var displayNodeBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(node.text.isEmpty ? " " : node.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(borderColor)
                .multilineTextAlignment(.leading)

            if let plannedDate = node.plannedDate {
                Text(Self.plannedDateFormatter.string(from: plannedDate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderStroke, style: borderStyle)
        )
        .onTapGesture(count: 1) {
            if NSEvent.modifierFlags.contains(.shift) {
                // Shift-click: toggle in multi-selection
                if viewModel.selectedNodeIDs.contains(node.id) {
                    viewModel.selectedNodeIDs.remove(node.id)
                    if viewModel.selectedNodeID == node.id {
                        viewModel.selectedNodeID = viewModel.selectedNodeIDs.first
                    }
                } else {
                    // If there's a single selected node, promote it to multi-selection
                    if let existing = viewModel.selectedNodeID, viewModel.selectedNodeIDs.isEmpty {
                        viewModel.selectedNodeIDs.insert(existing)
                    }
                    viewModel.selectedNodeIDs.insert(node.id)
                    viewModel.selectedNodeID = node.id
                }
                viewModel.selectedEdgeID = nil
            } else if isSelected && viewModel.selectedNodeIDs.count <= 1 {
                editText = node.text
                viewModel.selectedNodeID = nil
                viewModel.selectedNodeIDs.removeAll()
                viewModel.beginEditing(nodeID: node.id)
            } else {
                viewModel.commitEditing()
                viewModel.selectedNodeID = node.id
                viewModel.selectedNodeIDs = [node.id]
                viewModel.selectedEdgeID = nil
            }
        }
    }

    @ViewBuilder
    private var plusButtons: some View {
        let halfW = nodeSize.width / 2
        let halfH = nodeSize.height / 2
        let directions: [(DragDirection, CGFloat, CGFloat)] = [
            (.top, 0, -halfH),
            (.bottom, 0, halfH),
            (.left, -halfW, 0),
            (.right, halfW, 0),
        ]

        ForEach(directions, id: \.0) { direction, dx, dy in
            PlusButtonView(
                nodeID: node.id,
                direction: direction,
                viewModel: viewModel
            )
            .offset(x: dx, y: dy)
        }
    }

    private func setPlannedDate(initialDate: Date?) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: initialDate ?? Date())
        plannedDateSheetToken = NodePlannedDateSheetToken(initialDate: start)
    }

    private func setBudget(initialBudget: Double?) {
        guard let budget = promptForBudget(initialBudget: initialBudget) else { return }
        viewModel.setNodeBudgets(contextMenuTargetNodeIDs, budget: budget)
    }

    private func promptForBudget(initialBudget: Double?) -> Double? {
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        inputField.placeholderString = "0.00"
        if let initialBudget {
            inputField.stringValue = Self.plainBudgetString(initialBudget)
        }

        let alert = NSAlert()
        alert.messageText = initialBudget == nil ? "Set Cost" : "Change Cost"
        alert.informativeText = "Enter a planned cost for the selected node(s)."
        alert.accessoryView = inputField
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let trimmed = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let value = FinancialCurrencyFormatting.parseDecimalInput(trimmed),
            value.isFinite,
            value >= 0
        else { return nil }
        return value
    }

    private func formattedBudget(_ value: Double) -> String {
        viewModel.formatFinancialCurrencyUnsigned(value)
    }

    private static func plainBudgetString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

extension DragDirection: Hashable {}

// MARK: - Color hex helpers

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    func toHex() -> String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "FFFFFF" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - NSColorPanel observer

@MainActor
final class ColorPanelObserver: NSObject {
    static let shared = ColorPanelObserver()
    private var onChange: ((NSColor) -> Void)?

    func observe(panel: NSColorPanel, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}
