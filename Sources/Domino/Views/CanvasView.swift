import SwiftUI

private enum CanvasRecenter {
    /// Below this scale (too zoomed out) or above `maxScale` (too zoomed in), show the recenter control.
    static let minComfortScale: CGFloat = 0.45
    static let maxComfortScale: CGFloat = 2.75
}

private enum SelectionMarqueeAutoScroll {
    static let edgeMargin: CGFloat = 56
    static let maxStep: CGFloat = 14
    /// Require the pointer to stay in an edge band this long before panning (avoids accidental nudges).
    static let dwellSeconds: TimeInterval = 0.35
}

struct CanvasView: View {
    @ObservedObject var viewModel: DominoViewModel

    @State private var panOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var gestureScale: CGFloat = 1.0
    /// Canvas-space point pinned under the pinch location while a magnify gesture is active.
    @State private var magnifyFocalCanvasPoint: CGPoint?

    // Rectangle selection: fixed canvas anchor + current pointer in screen space (overlay maps anchor→screen each frame)
    @State private var selectionEnd: CGPoint? = nil
    @State private var selectionAnchorCanvas: CGPoint? = nil
    @State private var viewportSize: CGSize = .zero
    @State private var selectionEdgeEnteredAt: Date? = nil

    var body: some View {
        GeometryReader { geo in
            let totalOffset = panOffset
            let currentScale = scale * gestureScale
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let showRecenterAffordance = shouldShowRecenterAffordance(
                viewportSize: geo.size,
                viewportCenter: center,
                offset: totalOffset,
                scale: currentScale
            )

            ZStack(alignment: .topTrailing) {
                ZStack {
                // Background - drag to select, tap to deselect, double-click to create
                AppColors.canvasBackgroundSwiftUI
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                if selectionAnchorCanvas == nil {
                                    selectionAnchorCanvas = screenPointToCanvas(
                                        value.startLocation,
                                        offset: totalOffset,
                                        scale: currentScale,
                                        center: center
                                    )
                                }
                                selectionEnd = value.location

                                let edgeDelta = selectionEdgePanDelta(point: value.location, in: geo.size)
                                if edgeDelta != .zero {
                                    if selectionEdgeEnteredAt == nil {
                                        selectionEdgeEnteredAt = Date()
                                    }
                                } else {
                                    selectionEdgeEnteredAt = nil
                                }

                                if let anchor = selectionAnchorCanvas {
                                    let canvasRect = marqueeCanvasRect(
                                        anchorCanvas: anchor,
                                        endScreen: value.location,
                                        offset: totalOffset,
                                        scale: currentScale,
                                        center: center
                                    )
                                    viewModel.selectNodesInRect(canvasRect)
                                }
                            }
                            .onEnded { value in
                                if let anchor = selectionAnchorCanvas {
                                    let canvasRect = marqueeCanvasRect(
                                        anchorCanvas: anchor,
                                        endScreen: value.location,
                                        offset: totalOffset,
                                        scale: currentScale,
                                        center: center
                                    )
                                    viewModel.selectNodesInRect(canvasRect)
                                }
                                selectionEnd = nil
                                selectionAnchorCanvas = nil
                                selectionEdgeEnteredAt = nil
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
                if let anchor = selectionAnchorCanvas, let end = selectionEnd {
                    let startScreen = canvasPointToScreen(
                        anchor,
                        offset: totalOffset,
                        scale: currentScale,
                        center: center
                    )
                    let rect = normalizedRect(from: startScreen, to: end)
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
                if viewModel.visibleNodes.isEmpty {
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

                    // Snap guide overlays + target node highlights
                    ForEach(Array(viewModel.activeGuides.enumerated()), id: \.offset) { entry in
                        let guide = entry.element
                        switch guide.kind {
                        case .alignmentLine:
                            if let position = guide.position {
                                alignmentGuideLinePath(
                                    guide: guide,
                                    position: position,
                                    viewModel: viewModel
                                )
                                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                .allowsHitTesting(false)
                            }
                        case .gapIndicator:
                            ForEach(Array(guide.segments.enumerated()), id: \.offset) { segmentEntry in
                                let segment = segmentEntry.element
                                let label = gapLabel(for: segment, axis: guide.axis)
                                Path { path in
                                    path.move(to: segment.from)
                                    path.addLine(to: segment.to)
                                }
                                .stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .allowsHitTesting(false)

                                Path { path in
                                    let tick: CGFloat = 5
                                    if guide.axis == .vertical {
                                        path.move(to: CGPoint(x: segment.from.x, y: segment.from.y - tick))
                                        path.addLine(to: CGPoint(x: segment.from.x, y: segment.from.y + tick))
                                        path.move(to: CGPoint(x: segment.to.x, y: segment.to.y - tick))
                                        path.addLine(to: CGPoint(x: segment.to.x, y: segment.to.y + tick))
                                    } else {
                                        path.move(to: CGPoint(x: segment.from.x - tick, y: segment.from.y))
                                        path.addLine(to: CGPoint(x: segment.from.x + tick, y: segment.from.y))
                                        path.move(to: CGPoint(x: segment.to.x - tick, y: segment.to.y))
                                        path.addLine(to: CGPoint(x: segment.to.x + tick, y: segment.to.y))
                                    }
                                }
                                .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                                .allowsHitTesting(false)

                                if !label.isEmpty {
                                    Text(label)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                                        )
                                        .position(gapLabelPosition(for: segment, axis: guide.axis))
                                        .allowsHitTesting(false)
                                }
                            }
                        }

                        ForEach(Array(guide.targetNodeIDs.enumerated()), id: \.offset) { targetEntry in
                            let targetID = targetEntry.element
                            let targetPos = viewModel.effectivePosition(targetID)
                            let targetSize = viewModel.nodeSizes[targetID] ?? NodeDefaults.size
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                                .frame(width: targetSize.width + 4, height: targetSize.height + 4)
                                .position(targetPos)
                                .allowsHitTesting(false)
                        }
                    }

                    // Nodes layer
                    ForEach(viewModel.visibleNodes) { node in
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

                if showRecenterAffordance {
                    Button {
                        viewModel.requestCanvasRecenter()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .semibold))
                                .imageScale(.medium)
                            Text("Recenter")
                                .font(.system(size: 13, weight: .semibold))
                            Text("⌘0")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                    .help("Recenter canvas and zoom (⌘0)")
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
            }
            .onAppear {
                viewportSize = geo.size
                viewModel.canvasScale = currentScale
                applyCanvasRecenterIfPending(viewportSize: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                viewportSize = newSize
            }
            .onReceive(Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect()) { _ in
                guard let end = selectionEnd,
                    let anchor = selectionAnchorCanvas
                else { return }
                let sz = viewportSize
                guard sz.width > 1, sz.height > 1 else { return }
                let edgeDelta = selectionEdgePanDelta(point: end, in: sz)
                guard edgeDelta != .zero,
                    let entered = selectionEdgeEnteredAt,
                    Date().timeIntervalSince(entered) >= SelectionMarqueeAutoScroll.dwellSeconds
                else { return }

                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let liveScale = scale * gestureScale
                panOffset.width += edgeDelta.width
                panOffset.height += edgeDelta.height
                let canvasRect = marqueeCanvasRect(
                    anchorCanvas: anchor,
                    endScreen: end,
                    offset: panOffset,
                    scale: liveScale,
                    center: c
                )
                viewModel.selectNodesInRect(canvasRect)
            }
            .onChange(of: currentScale) { _, newScale in
                viewModel.canvasScale = newScale
            }
            .onChange(of: viewModel.canvasFocusRequest) { _, request in
                guard let request else { return }
                centerOnNode(request.nodeID, viewportSize: geo.size)
            }
            .onChange(of: viewModel.canvasRecenterToken) { _, _ in
                applyCanvasRecenterIfPending(viewportSize: geo.size)
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let previousCombined = scale * gestureScale
                        if magnifyFocalCanvasPoint == nil {
                            magnifyFocalCanvasPoint = screenPointToCanvas(
                                value.startLocation,
                                offset: panOffset,
                                scale: previousCombined,
                                center: center
                            )
                        }
                        guard let focal = magnifyFocalCanvasPoint else { return }
                        let nextScale = clampScale(scale * value.magnification)
                        panOffset = panOffsetKeepingCanvasPointAtScreen(
                            canvasPoint: focal,
                            screenAnchor: value.startLocation,
                            scale: nextScale,
                            center: center
                        )
                        gestureScale = nextScale / scale
                    }
                    .onEnded { value in
                        let nextScale = clampScale(scale * value.magnification)
                        if let focal = magnifyFocalCanvasPoint {
                            panOffset = panOffsetKeepingCanvasPointAtScreen(
                                canvasPoint: focal,
                                screenAnchor: value.startLocation,
                                scale: nextScale,
                                center: center
                            )
                        }
                        scale = nextScale
                        gestureScale = 1.0
                        magnifyFocalCanvasPoint = nil
                    }
            )
            .contentShape(Rectangle())
            .clipped()
        }
        .onChange(of: viewModel.fileLoadID) {
            centerOnNodes(viewportSize: NSApplication.shared.windows.first?.frame.size ?? CGSize(width: 1200, height: 800))
        }
    }

    private func centerOnNodes(viewportSize: CGSize) {
        magnifyFocalCanvasPoint = nil
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

    private func centerOnNode(_ nodeID: UUID, viewportSize: CGSize) {
        guard let node = viewModel.nodes[nodeID], viewModel.visibleNodes.contains(where: { $0.id == nodeID }) else {
            return
        }

        magnifyFocalCanvasPoint = nil
        scale = 1.0
        gestureScale = 1.0
        panOffset = CGSize(
            width: viewportSize.width / 2 - node.position.x,
            height: viewportSize.height / 2 - node.position.y
        )
    }

    private func applyCanvasRecenterIfPending(viewportSize: CGSize) {
        guard viewModel.isCanvasRecenterPending else { return }
        centerOnNodes(viewportSize: viewportSize)
        viewModel.markCanvasRecenterApplied()
    }

    private func shouldShowRecenterAffordance(
        viewportSize: CGSize,
        viewportCenter: CGPoint,
        offset: CGSize,
        scale: CGFloat
    ) -> Bool {
        if viewModel.visibleNodes.isEmpty {
            return false
        }
        if scale < CanvasRecenter.minComfortScale || scale > CanvasRecenter.maxComfortScale {
            return true
        }
        return !viewportIntersectsAnyVisibleNode(
            viewportSize: viewportSize,
            viewportCenter: viewportCenter,
            offset: offset,
            scale: scale
        )
    }

    private func viewportIntersectsAnyVisibleNode(
        viewportSize: CGSize,
        viewportCenter: CGPoint,
        offset: CGSize,
        scale: CGFloat
    ) -> Bool {
        let viewportBounds = CGRect(origin: .zero, size: viewportSize)
        for node in viewModel.visibleNodes {
            let size = viewModel.nodeSizes[node.id] ?? NodeDefaults.size
            let halfW = size.width / 2
            let halfH = size.height / 2
            let canvasRect = CGRect(
                x: node.position.x - halfW,
                y: node.position.y - halfH,
                width: size.width,
                height: size.height
            )
            let screenRect = canvasBoundsToViewportRect(
                canvasRect: canvasRect,
                viewportCenter: viewportCenter,
                offset: offset,
                scale: scale
            )
            if screenRect.intersects(viewportBounds) {
                return true
            }
        }
        return false
    }

    /// Canvas-space bounds mapped into view coordinates (same transform as scaled canvas content).
    private func canvasBoundsToViewportRect(
        canvasRect: CGRect,
        viewportCenter: CGPoint,
        offset: CGSize,
        scale: CGFloat
    ) -> CGRect {
        let c = viewportCenter
        func toScreen(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: (p.x - c.x) * scale + c.x + offset.width,
                y: (p.y - c.y) * scale + c.y + offset.height
            )
        }
        let pMin = toScreen(CGPoint(x: canvasRect.minX, y: canvasRect.minY))
        let pMax = toScreen(CGPoint(x: canvasRect.maxX, y: canvasRect.maxY))
        return CGRect(
            x: min(pMin.x, pMax.x),
            y: min(pMin.y, pMax.y),
            width: abs(pMax.x - pMin.x),
            height: abs(pMax.y - pMin.y)
        )
    }

    private func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, 0.2), 5.0)
    }

    /// Pan offset so `canvasPoint` appears at `screenAnchor` after scaling about `center` (inverse of `screenPointToCanvas`).
    private func panOffsetKeepingCanvasPointAtScreen(
        canvasPoint: CGPoint,
        screenAnchor: CGPoint,
        scale: CGFloat,
        center: CGPoint
    ) -> CGSize {
        let c = center
        return CGSize(
            width: screenAnchor.x - c.x - (canvasPoint.x - c.x) * scale,
            height: screenAnchor.y - c.y - (canvasPoint.y - c.y) * scale
        )
    }

    /// Convert a screen point to canvas coordinates accounting for scaleEffect anchor at center
    private func screenPointToCanvas(_ point: CGPoint, offset: CGSize, scale: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - center.x - offset.width) / scale + center.x,
            y: (point.y - center.y - offset.height) / scale + center.y
        )
    }

    /// Inverse of `screenPointToCanvas` — for marquee overlay while panning / autoscrolling.
    private func canvasPointToScreen(_ point: CGPoint, offset: CGSize, scale: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - center.x) * scale + center.x + offset.width,
            y: (point.y - center.y) * scale + center.y + offset.height
        )
    }

    /// Marquee from a fixed canvas anchor to the current finger position (screen), so autoscroll extends the selection.
    private func marqueeCanvasRect(
        anchorCanvas: CGPoint,
        endScreen: CGPoint,
        offset: CGSize,
        scale: CGFloat,
        center: CGPoint
    ) -> CGRect {
        let endCanvas = screenPointToCanvas(endScreen, offset: offset, scale: scale, center: center)
        return CGRect(
            x: min(anchorCanvas.x, endCanvas.x),
            y: min(anchorCanvas.y, endCanvas.y),
            width: abs(endCanvas.x - anchorCanvas.x),
            height: abs(endCanvas.y - anchorCanvas.y)
        )
    }

    private func selectionEdgePanDelta(point: CGPoint, in size: CGSize) -> CGSize {
        let m = SelectionMarqueeAutoScroll.edgeMargin
        let maxStep = SelectionMarqueeAutoScroll.maxStep
        guard size.width > m * 2, size.height > m * 2 else { return .zero }

        var dx: CGFloat = 0
        var dy: CGFloat = 0

        if point.x < m {
            dx = maxStep * (m - point.x) / m
        } else if point.x > size.width - m {
            dx = -maxStep * (point.x - (size.width - m)) / m
        }

        if point.y < m {
            dy = maxStep * (m - point.y) / m
        } else if point.y > size.height - m {
            dy = -maxStep * (point.y - (size.height - m)) / m
        }

        return CGSize(width: dx, height: dy)
    }

    /// Normalize two points into a positive-sized rect (for screen overlay)
    private func normalizedRect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y)
        )
    }

    /// Clips alignment guides to the span of targets + current selection so the line reads as a fixed “rail”
    /// between those nodes instead of an infinite canvas-wide stroke that tracks the eye with the drag.
    private func alignmentGuideLinePath(guide: SnapGuide, position: CGFloat, viewModel: DominoViewModel) -> Path {
        let margin: CGFloat = 48
        var relevantIDs = Set(guide.targetNodeIDs)
        relevantIDs.formUnion(viewModel.selectedNodeIDs)

        guard let u = viewModel.canvasBoundsUnion(nodeIDs: relevantIDs), !u.isNull else {
            return alignmentGuideInfinitePath(axis: guide.axis, position: position)
        }

        var path = Path()
        switch guide.axis {
        case .horizontal:
            path.move(to: CGPoint(x: u.minX - margin, y: position))
            path.addLine(to: CGPoint(x: u.maxX + margin, y: position))
        case .vertical:
            path.move(to: CGPoint(x: position, y: u.minY - margin))
            path.addLine(to: CGPoint(x: position, y: u.maxY + margin))
        }
        return path
    }

    private func alignmentGuideInfinitePath(axis: AlignmentAxis, position: CGFloat) -> Path {
        let huge: CGFloat = 50_000
        var path = Path()
        switch axis {
        case .horizontal:
            path.move(to: CGPoint(x: -huge, y: position))
            path.addLine(to: CGPoint(x: huge, y: position))
        case .vertical:
            path.move(to: CGPoint(x: position, y: -huge))
            path.addLine(to: CGPoint(x: position, y: huge))
        }
        return path
    }

    private func gapLabel(for segment: GuideSegment, axis: AlignmentAxis) -> String {
        let length: CGFloat
        switch axis {
        case .vertical:
            length = abs(segment.to.x - segment.from.x)
        case .horizontal:
            length = abs(segment.to.y - segment.from.y)
        }

        guard length >= 1 else { return "" }
        return "\(Int(length.rounded()))"
    }

    private func gapLabelPosition(for segment: GuideSegment, axis: AlignmentAxis) -> CGPoint {
        let midX = (segment.from.x + segment.to.x) / 2
        let midY = (segment.from.y + segment.to.y) / 2
        let offset: CGFloat = 12

        switch axis {
        case .vertical:
            return CGPoint(x: midX, y: midY - offset)
        case .horizontal:
            return CGPoint(x: midX + offset, y: midY)
        }
    }
}
