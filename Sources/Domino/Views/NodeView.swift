import SwiftUI

struct NodeView: View {
    let node: DominoNode
    @ObservedObject var viewModel: DominoViewModel
    @State private var isHovering = false
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

    private let minWidth: CGFloat = 100
    private let cornerRadius: CGFloat = 8

    private var borderColor: Color {
        nodeColor ?? .primary
    }

    private var borderStroke: Color {
        highlighted ? borderColor : borderColor.opacity(0.2)
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
                    if let degree = viewModel.nodeDegrees[node.id] {
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
                    Menu("Set Color") {
                        ForEach(Self.presetColors, id: \.hex) { preset in
                            Button {
                                viewModel.setNodeColor(node.id, hex: preset.hex)
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
                            let nodeID = node.id
                            let vm = viewModel
                            let panel = NSColorPanel.shared
                            panel.setTarget(nil)
                            panel.setAction(nil)
                            panel.color = NSColor(nodeColor ?? .white)
                            panel.orderFront(nil)
                            ColorPanelObserver.shared.observe(panel: panel) { nsColor in
                                vm.setNodeColor(nodeID, hex: Color(nsColor: nsColor).toHex())
                            }
                        }
                        if node.colorHex != nil {
                            Divider()
                            Button("Remove Color") {
                                viewModel.setNodeColor(node.id, hex: nil)
                            }
                        }
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
                        // Move entire selection
                        viewModel.moveSelectedNodes(by: value.translation)
                    } else {
                        dragOffset = value.translation
                        viewModel.nodeDragOffset[node.id] = value.translation
                    }
                }
                .onEnded { value in
                    if isMultiSelected && viewModel.selectedNodeIDs.count > 1 {
                        viewModel.commitSelectedNodesMove(by: value.translation)
                    } else {
                        let newPosition = CGPoint(
                            x: node.position.x + value.translation.width,
                            y: node.position.y + value.translation.height
                        )
                        dragOffset = .zero
                        viewModel.nodeDragOffset.removeValue(forKey: node.id)
                        viewModel.moveNode(node.id, to: newPosition)
                    }
                }
        )
        .onHover { hovering in
            isHovering = hovering
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
                            .stroke(borderStroke, lineWidth: highlighted ? 1.5 : 1)
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
