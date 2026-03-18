import AppKit
import SwiftUI

struct NodeView: View {
    let node: DominoNode
    @ObservedObject var viewModel: DominoViewModel
    @AppStorage("showNodeRanks") private var showNodeRanks = true
    @State private var isHovering = false
    @State private var showsPlannedDateTooltip = false
    @State private var plannedDateTooltipTask: Task<Void, Never>?
    @State private var editText: String = ""
    @State private var dragOffset: CGSize = .zero
    @FocusState private var textFieldFocused: Bool

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

    private var highlighted: Bool {
        isSelected || isDropTarget
    }

    private var nodeColor: Color? {
        guard let hex = node.colorHex else { return nil }
        return Color(hex: hex)
    }

    private var contextMenuTargetNodeIDs: Set<UUID> {
        viewModel.contextMenuTargetNodeIDs(for: node.id)
    }

    private var hasColorInContextMenuTargets: Bool {
        contextMenuTargetNodeIDs.contains { id in
            viewModel.nodes[id]?.colorHex != nil
        }
    }

    private var areContextMenuTargetsHidden: Bool {
        viewModel.areAllNodesHidden(contextMenuTargetNodeIDs)
    }

    private let minWidth: CGFloat = 100
    private let cornerRadius: CGFloat = 8

    private var borderColor: Color {
        nodeColor ?? .primary
    }

    private var borderStroke: Color {
        highlighted ? borderColor : borderColor.opacity(0.2)
    }

    private var borderStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: highlighted ? 1.5 : 1,
            dash: (viewModel.showHiddenItems && node.isHidden) ? [6, 4] : []
        )
    }

    private var fillColor: Color {
        if highlighted, let c = nodeColor {
            return c.opacity(0.12)
        }
        return (nodeColor ?? .white).opacity(0.08)
    }

    private var nodeSize: CGSize {
        viewModel.nodeSizes[node.id] ?? NodeDefaults.size
    }

    private static let presetColors: [(name: String, hex: String)] = [
        ("Green", "61BD4F"),
        ("Yellow", "F2D600"),
        ("Orange", "FF9F1A"),
        ("Red", "EB5A46"),
        ("Blue", "0079BF"),
    ]
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

    var body: some View {
        ZStack {
            nodeBody
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                viewModel.nodeSizes[node.id] = geo.size
                            }
                            .onChange(of: geo.size) { _, newSize in
                                viewModel.nodeSizes[node.id] = newSize
                            }
                    }
                )
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
                .overlay(alignment: .top) {
                    plannedDateTooltip
                }
                .contextMenu {
                    Menu("Set Color") {
                        ForEach(Self.presetColors, id: \.hex) { preset in
                            Button {
                                viewModel.setNodeColors(contextMenuTargetNodeIDs, hex: preset.hex)
                            } label: {
                                Label {
                                    Text(preset.name)
                                } icon: {
                                    Image(nsImage: Self.colorDot(hex: preset.hex))
                                }
                            }
                        }
                        Divider()
                        Button("Custom...") {
                            let nodeIDs = contextMenuTargetNodeIDs
                            let vm = viewModel
                            let panel = NSColorPanel.shared
                            panel.setTarget(nil)
                            panel.setAction(nil)
                            panel.color = NSColor(nodeColor ?? .white)
                            panel.orderFront(nil)
                            ColorPanelObserver.shared.observe(panel: panel) { nsColor in
                                vm.setNodeColors(nodeIDs, hex: Color(nsColor: nsColor).toHex())
                            }
                        }
                        if hasColorInContextMenuTargets {
                            Divider()
                            Button("Remove Color") {
                                viewModel.setNodeColors(contextMenuTargetNodeIDs, hex: nil)
                            }
                        }
                    }

                    Divider()

                    if let plannedDate = node.plannedDate {
                        Menu(Self.plannedDateFormatter.string(from: plannedDate)) {
                            Button("Change Date") {
                                setPlannedDate(initialDate: plannedDate)
                            }
                            Button("Remove Planned Date", role: .destructive) {
                                viewModel.setNodePlannedDates(contextMenuTargetNodeIDs, date: nil)
                            }
                        }
                    } else {
                        Button("Set Planned Date") {
                            setPlannedDate(initialDate: nil)
                        }
                    }

                    Divider()

                    Button(areContextMenuTargetsHidden ? "Unhide" : "Hide") {
                        viewModel.setNodesHidden(
                            contextMenuTargetNodeIDs,
                            isHidden: !areContextMenuTargetsHidden
                        )
                    }
                }
            if isHovering && !isEditing {
                plusButtons
            }
        }
        .offset(isMultiSelected ? (viewModel.nodeDragOffset[node.id] ?? .zero) : dragOffset)
        .gesture(
            isEditing ? nil :
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if isMultiSelected && viewModel.selectedNodeIDs.count > 1 {
                        let snap = viewModel.calculateGroupSnap(for: viewModel.selectedNodeIDs, rawOffset: value.translation)
                        viewModel.moveSelectedNodes(by: snap.snappedOffset)
                        viewModel.activeGuides = snap.guides
                    } else {
                        let snap = viewModel.calculateSnap(for: node.id, rawOffset: value.translation)
                        dragOffset = snap.snappedOffset
                        viewModel.nodeDragOffset[node.id] = snap.snappedOffset
                        viewModel.activeGuides = snap.guides
                    }
                }
                .onEnded { value in
                    if isMultiSelected && viewModel.selectedNodeIDs.count > 1 {
                        let snap = viewModel.calculateGroupSnap(for: viewModel.selectedNodeIDs, rawOffset: value.translation)
                        viewModel.activeGuides = []
                        viewModel.commitSelectedNodesMove(by: snap.snappedOffset)
                    } else {
                        let snap = viewModel.calculateSnap(for: node.id, rawOffset: value.translation)
                        let newPosition = CGPoint(
                            x: node.position.x + snap.snappedOffset.width,
                            y: node.position.y + snap.snappedOffset.height
                        )
                        dragOffset = .zero
                        viewModel.nodeDragOffset.removeValue(forKey: node.id)
                        viewModel.activeGuides = []
                        viewModel.moveNode(node.id, to: newPosition)
                    }
                }
        )
        .onHover { hovering in
            handleNodeHoverChange(hovering)
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                cancelPlannedDateTooltip()
            } else if isHovering {
                schedulePlannedDateTooltip()
            }
        }
        .onDisappear {
            cancelPlannedDateTooltip()
        }
    }

    @ViewBuilder
    private var nodeBody: some View {
        Group {
            if isEditing {
                TextField("Type here...", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .focused($textFieldFocused)
                    .frame(minWidth: minWidth)
                    .fixedSize()
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
            } else {
                Text(node.text.isEmpty ? " " : node.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(borderColor)
                    .frame(minWidth: minWidth)
                    .fixedSize()
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
                            viewModel.editingNodeID = node.id
                        } else {
                            viewModel.commitEditing()
                            viewModel.selectedNodeID = node.id
                            viewModel.selectedNodeIDs = [node.id]
                            viewModel.selectedEdgeID = nil
                        }
                    }
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

    @ViewBuilder
    private var plannedDateTooltip: some View {
        if showsPlannedDateTooltip, let plannedDate = node.plannedDate {
            Text("Planned: \(Self.plannedDateFormatter.string(from: plannedDate))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.primary.opacity(0.15), lineWidth: 1)
                )
                .offset(y: -34)
                .allowsHitTesting(false)
        }
    }

    private func handleNodeHoverChange(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            schedulePlannedDateTooltip()
        } else {
            cancelPlannedDateTooltip()
        }
    }

    private func schedulePlannedDateTooltip() {
        cancelPlannedDateTooltip()
        guard node.plannedDate != nil, !isEditing else { return }
        plannedDateTooltipTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isHovering, node.plannedDate != nil, !isEditing {
                    showsPlannedDateTooltip = true
                }
            }
        }
    }

    private func cancelPlannedDateTooltip() {
        plannedDateTooltipTask?.cancel()
        plannedDateTooltipTask = nil
        showsPlannedDateTooltip = false
    }

    private func setPlannedDate(initialDate: Date?) {
        guard let pickedDate = promptForPlannedDate(initialDate: initialDate) else { return }
        let normalized = Calendar.current.startOfDay(for: pickedDate)
        viewModel.setNodePlannedDates(contextMenuTargetNodeIDs, date: normalized)
    }

    private func promptForPlannedDate(initialDate: Date?) -> Date? {
        let datePicker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 220, height: 160))
        datePicker.datePickerElements = .yearMonthDay
        datePicker.datePickerStyle = .clockAndCalendar
        datePicker.dateValue = initialDate ?? Date()

        let alert = NSAlert()
        alert.messageText = initialDate == nil ? "Set Planned Date" : "Change Planned Date"
        alert.informativeText = "Choose a planned date for this node."
        alert.accessoryView = datePicker
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return datePicker.dateValue
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
