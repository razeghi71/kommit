import SwiftUI

struct CanvasView: View {
    @ObservedObject var viewModel: DominoViewModel

    @State private var panOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var gestureScale: CGFloat = 1.0

    // Rectangle selection state
    @State private var selectionStart: CGPoint? = nil
    @State private var selectionEnd: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            let totalOffset = panOffset
            let currentScale = scale * gestureScale
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Background - drag to select, tap to deselect, double-click to create
                Color(nsColor: .windowBackgroundColor)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                if selectionStart == nil {
                                    selectionStart = value.startLocation
                                }
                                selectionEnd = value.location

                                // Convert screen rect to canvas coordinates for live selection
                                if let start = selectionStart {
                                    let canvasRect = screenRectToCanvas(
                                        from: start, to: value.location,
                                        offset: totalOffset, scale: currentScale, center: center
                                    )
                                    viewModel.selectNodesInRect(canvasRect)
                                }
                            }
                            .onEnded { value in
                                if let start = selectionStart {
                                    let canvasRect = screenRectToCanvas(
                                        from: start, to: value.location,
                                        offset: totalOffset, scale: currentScale, center: center
                                    )
                                    viewModel.selectNodesInRect(canvasRect)
                                }
                                selectionStart = nil
                                selectionEnd = nil
                            }
                    )
                    .onTapGesture(count: 2) { location in
                        // Convert screen location to canvas coordinates
                        let canvasPoint = screenPointToCanvas(
                            location, offset: totalOffset, scale: currentScale, center: center
                        )
                        viewModel.addNode(at: canvasPoint)
                    }
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded {
                                viewModel.commitEditing()
                                viewModel.clearSelection()
                            }
                    )

                // Selection rectangle overlay
                if let start = selectionStart, let end = selectionEnd {
                    let rect = normalizedRect(from: start, to: end)
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(
                            Rectangle()
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                // Empty state hint
                if viewModel.nodes.isEmpty {
                    VStack(spacing: 8) {
                        Text("Double-click to add a node")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .allowsHitTesting(false)
                }

                // Content layer, shifted by pan offset and scaled
                ZStack {
                    // Edges layer
                    ForEach(viewModel.edges) { edge in
                        EdgeShape(
                            from: viewModel.effectivePosition(edge.parent.id),
                            to: viewModel.effectivePosition(edge.child.id),
                            fromSize: viewModel.nodeSizes[edge.parent.id] ?? NodeDefaults.size,
                            toSize: viewModel.nodeSizes[edge.child.id] ?? NodeDefaults.size,
                            isSelected: viewModel.selectedEdgeID == edge.id,
                            onTap: {
                                viewModel.commitEditing()
                                viewModel.selectedNodeID = nil
                                viewModel.selectedNodeIDs.removeAll()
                                viewModel.selectedEdgeID = viewModel.selectedEdgeID == edge.id ? nil : edge.id
                            }
                        )
                    }

                    // Preview edge while dragging
                    if let drag = viewModel.edgeDrag {
                        EdgeShape(
                            from: viewModel.effectivePosition(drag.sourceNodeID),
                            to: drag.currentPoint,
                            fromSize: viewModel.nodeSizes[drag.sourceNodeID] ?? NodeDefaults.size,
                            color: .accentColor.opacity(0.5),
                            dash: [6, 4]
                        )
                    }

                    // Alignment guide lines + target node highlights
                    ForEach(Array(viewModel.activeGuides.enumerated()), id: \.offset) { _, guide in
                        // Guide line
                        switch guide.axis {
                        case .horizontal:
                            Path { path in
                                path.move(to: CGPoint(x: -50000, y: guide.position))
                                path.addLine(to: CGPoint(x: 50000, y: guide.position))
                            }
                            .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .allowsHitTesting(false)
                        case .vertical:
                            Path { path in
                                path.move(to: CGPoint(x: guide.position, y: -50000))
                                path.addLine(to: CGPoint(x: guide.position, y: 50000))
                            }
                            .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .allowsHitTesting(false)
                        }

                        // Highlight on the reference node
                        let targetPos = viewModel.effectivePosition(guide.targetNodeID)
                        let targetSize = viewModel.nodeSizes[guide.targetNodeID] ?? NodeDefaults.size
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                            .frame(width: targetSize.width + 4, height: targetSize.height + 4)
                            .position(targetPos)
                            .allowsHitTesting(false)
                    }

                    // Nodes layer
                    ForEach(viewModel.sortedNodes) { node in
                        NodeView(node: node, viewModel: viewModel)
                            .position(node.position)
                    }
                }
                .coordinateSpace(name: "canvas")
                .scaleEffect(currentScale)
                .offset(totalOffset)

                // Invisible scroll wheel receiver
                ScrollWheelHandler(panOffset: $panOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    gestureScale = value.magnification
                }
                .onEnded { value in
                    scale = clampScale(scale * value.magnification)
                    gestureScale = 1.0
                }
        )
        .clipped()
        .onChange(of: viewModel.fileLoadID) {
            centerOnNodes(viewportSize: NSApplication.shared.windows.first?.frame.size ?? CGSize(width: 1200, height: 800))
        }
    }

    private func centerOnNodes(viewportSize: CGSize) {
        scale = 1.0
        gestureScale = 1.0
        guard !viewModel.nodes.isEmpty else {
            panOffset = .zero
            return
        }
        let positions = viewModel.nodes.values.map(\.position)
        let avgX = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
        let avgY = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
        panOffset = CGSize(
            width: viewportSize.width / 2 - avgX,
            height: viewportSize.height / 2 - avgY
        )
    }

    private func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, 0.2), 5.0)
    }

    /// Convert a screen point to canvas coordinates accounting for scaleEffect anchor at center
    private func screenPointToCanvas(_ point: CGPoint, offset: CGSize, scale: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - center.x - offset.width) / scale + center.x,
            y: (point.y - center.y - offset.height) / scale + center.y
        )
    }

    /// Convert two screen points to a normalized CGRect in canvas coordinates
    private func screenRectToCanvas(from: CGPoint, to: CGPoint, offset: CGSize, scale: CGFloat, center: CGPoint) -> CGRect {
        let p1 = screenPointToCanvas(from, offset: offset, scale: scale, center: center)
        let p2 = screenPointToCanvas(to, offset: offset, scale: scale, center: center)
        return CGRect(
            x: min(p1.x, p2.x), y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x), height: abs(p2.y - p1.y)
        )
    }

    /// Normalize two points into a positive-sized rect (for screen overlay)
    private func normalizedRect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y)
        )
    }
}
