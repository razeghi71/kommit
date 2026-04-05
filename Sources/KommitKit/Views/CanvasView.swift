import AppKit
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
    private struct ActiveNodeDrag {
        let nodeIDs: Set<UUID>
        var pointerInViewport: CGPoint
        var translation: CGSize
        var autoscrollAdjust: CGSize = .zero
    }

    @ObservedObject var viewModel: KommitViewModel

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
    @State private var activeNodeDrag: ActiveNodeDrag? = nil
    @State private var nodeDragEdgeEnteredAt: Date? = nil
    @State private var lastAppliedCanvasFocusToken: UUID?

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
                            from: effectiveNodeCenter(edge.parent.id),
                            to: effectiveNodeCenter(edge.child.id),
                            fromSize: edge.parent.frameSize,
                            toSize: edge.child.frameSize,
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
                            from: effectiveNodeCenter(drag.sourceNodeID),
                            to: drag.currentPoint,
                            fromSize: viewModel.nodes[drag.sourceNodeID]?.frameSize ?? NodeDefaults.size,
                            targetMode: .pointTip,
                            color: .accentColor.opacity(0.5),
                            dash: [6, 4]
                        )
                    }

                    // Nodes layer
                    ForEach(viewModel.visibleNodes) { node in
                        NodeView(
                            node: node,
                            viewModel: viewModel,
                            canvasScale: currentScale,
                            onNodeDragChanged: { nodeID, pointerInViewport, translation, useMultiSelection in
                                updateNodeDrag(
                                    nodeID: nodeID,
                                    pointerInViewport: pointerInViewport,
                                    translation: translation,
                                    useMultiSelection: useMultiSelection
                                )
                            },
                            onNodeDragEnded: {
                                commitActiveNodeDrag()
                            },
                            onNodeDragCancelled: {
                                cancelActiveNodeDrag()
                            }
                        )
                        .position(effectiveNodeCenter(node.id))
                    }
                }
                .coordinateSpace(name: "canvas")
                .scaleEffect(currentScale)
                .offset(totalOffset)

                // Invisible scroll wheel receiver (pan; ⌘-scroll zooms toward cursor)
                ScrollWheelHandler(panOffset: $panOffset, scale: $scale, viewportSize: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .coordinateSpace(name: KommitCanvasCoordinateSpace.viewportName)

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
                applyCanvasFocusIfNeeded(viewportSize: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                viewportSize = newSize
                applyCanvasFocusIfNeeded(viewportSize: newSize)
            }
            .onReceive(Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect()) { _ in
                let sz = viewportSize
                guard sz.width > 1, sz.height > 1 else { return }
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let liveScale = scale * gestureScale

                if let end = selectionEnd, let anchor = selectionAnchorCanvas {
                    let edgeDelta = selectionEdgePanDelta(point: end, in: sz)
                    guard edgeDelta != .zero,
                        let entered = selectionEdgeEnteredAt,
                        Date().timeIntervalSince(entered) >= SelectionMarqueeAutoScroll.dwellSeconds
                    else { return }

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
                    return
                }

                guard var drag = activeNodeDrag else {
                    nodeDragEdgeEnteredAt = nil
                    return
                }

                let edgeDelta = selectionEdgePanDelta(point: drag.pointerInViewport, in: sz)
                if edgeDelta != .zero {
                    if nodeDragEdgeEnteredAt == nil {
                        nodeDragEdgeEnteredAt = Date()
                    }
                } else {
                    nodeDragEdgeEnteredAt = nil
                }
                guard edgeDelta != .zero,
                    let entered = nodeDragEdgeEnteredAt,
                    Date().timeIntervalSince(entered) >= SelectionMarqueeAutoScroll.dwellSeconds
                else { return }

                panOffset.width += edgeDelta.width
                panOffset.height += edgeDelta.height
                drag.autoscrollAdjust = CGSize(
                    width: drag.autoscrollAdjust.width - edgeDelta.width / liveScale,
                    height: drag.autoscrollAdjust.height - edgeDelta.height / liveScale
                )
                activeNodeDrag = drag
            }
            .onChange(of: currentScale) { _, newScale in
                viewModel.canvasScale = newScale
            }
            .onChange(of: viewModel.canvasFocusRequest) { _, request in
                guard let request else { return }
                applyCanvasFocusIfNeeded(request: request, viewportSize: geo.size)
            }
            .onChange(of: viewModel.canvasRecenterToken) { _, _ in
                applyCanvasRecenterIfPending(viewportSize: geo.size)
            }
            .onReceive(NotificationCenter.default.publisher(for: CanvasZoomController.commandNotification)) { notification in
                guard let command = CanvasZoomController.command(from: notification) else { return }
                applyKeyboardStepZoom(zoomIn: command == .zoomIn, viewportSize: geo.size)
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
            .onDisappear {
                cancelActiveNodeDrag()
            }
            .background(
                CanvasSelectAllKeyMonitor(viewModel: viewModel)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .clipped()
        }
        .onChange(of: viewModel.fileLoadID) {
            cancelActiveNodeDrag()
            centerOnNodes(viewportSize: NSApplication.shared.windows.first?.frame.size ?? CGSize(width: 1200, height: 800))
        }
    }

    private func effectiveNodeCenter(_ nodeID: UUID) -> CGPoint {
        guard let node = viewModel.nodes[nodeID] else { return .zero }
        guard let drag = activeNodeDrag, drag.nodeIDs.contains(nodeID) else { return node.center }
        let translation = CGSize(
            width: drag.translation.width + drag.autoscrollAdjust.width,
            height: drag.translation.height + drag.autoscrollAdjust.height
        )
        let (nx, ny) = CanvasIntegerGeometry.snappedOrigin(nodeX: node.x, nodeY: node.y, translation: translation)
        return CanvasIntegerGeometry.center(x: nx, y: ny, width: node.width, height: node.height)
    }

    private func updateNodeDrag(
        nodeID: UUID,
        pointerInViewport: CGPoint,
        translation: CGSize,
        useMultiSelection: Bool
    ) {
        let nodeIDs: Set<UUID>
        let autoscrollAdjust: CGSize

        if let drag = activeNodeDrag, drag.nodeIDs.contains(nodeID) {
            nodeIDs = drag.nodeIDs
            autoscrollAdjust = drag.autoscrollAdjust
        } else {
            nodeIDs = dragTargetNodeIDs(for: nodeID, useMultiSelection: useMultiSelection)
            autoscrollAdjust = .zero
            nodeDragEdgeEnteredAt = nil
        }

        activeNodeDrag = ActiveNodeDrag(
            nodeIDs: nodeIDs,
            pointerInViewport: pointerInViewport,
            translation: translation,
            autoscrollAdjust: autoscrollAdjust
        )
    }

    private func dragTargetNodeIDs(for nodeID: UUID, useMultiSelection: Bool) -> Set<UUID> {
        if useMultiSelection, !viewModel.selectedNodeIDs.isEmpty {
            return viewModel.selectedNodeIDs
        }
        return [nodeID]
    }

    private func commitActiveNodeDrag() {
        guard let drag = activeNodeDrag else { return }
        let totalOffset = CGSize(
            width: drag.translation.width + drag.autoscrollAdjust.width,
            height: drag.translation.height + drag.autoscrollAdjust.height
        )

        if drag.nodeIDs.count > 1 {
            viewModel.commitNodesMove(drag.nodeIDs, by: totalOffset)
        } else if let nodeID = drag.nodeIDs.first, let node = viewModel.nodes[nodeID] {
            let (nx, ny) = CanvasIntegerGeometry.snappedOrigin(
                nodeX: node.x,
                nodeY: node.y,
                translation: totalOffset
            )
            viewModel.moveNode(nodeID, x: nx, y: ny)
        }

        cancelActiveNodeDrag()
    }

    private func cancelActiveNodeDrag() {
        activeNodeDrag = nil
        nodeDragEdgeEnteredAt = nil
    }

    private func centerOnNodes(viewportSize: CGSize) {
        magnifyFocalCanvasPoint = nil
        scale = 1.0
        gestureScale = 1.0
        guard !viewModel.nodes.isEmpty else {
            panOffset = .zero
            return
        }
        let centers = viewModel.nodes.values.map(\.center)
        let avgX = centers.map(\.x).reduce(0, +) / CGFloat(centers.count)
        let avgY = centers.map(\.y).reduce(0, +) / CGFloat(centers.count)
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
        let c = node.center
        panOffset = CGSize(
            width: viewportSize.width / 2 - c.x,
            height: viewportSize.height / 2 - c.y
        )
    }

    private func applyCanvasFocusIfNeeded(viewportSize: CGSize) {
        guard let request = viewModel.canvasFocusRequest else { return }
        applyCanvasFocusIfNeeded(request: request, viewportSize: viewportSize)
    }

    private func applyCanvasFocusIfNeeded(request: NodeFocusRequest, viewportSize: CGSize) {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }
        guard request.token != lastAppliedCanvasFocusToken else { return }
        lastAppliedCanvasFocusToken = request.token
        centerOnNode(request.nodeID, viewportSize: viewportSize)
    }

    private func applyCanvasRecenterIfPending(viewportSize: CGSize) {
        guard viewModel.isCanvasRecenterPending else { return }
        centerOnNodes(viewportSize: viewportSize)
        viewModel.markCanvasRecenterApplied()
    }

    private func applyKeyboardStepZoom(zoomIn: Bool, viewportSize: CGSize) {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let combined = scale * gestureScale
        let next = CanvasZoomController.zoom(
            offset: panOffset,
            scale: combined,
            anchor: center,
            center: center,
            multiplier: CanvasZoomController.keyboardStepFactor(zoomingIn: zoomIn)
        )
        panOffset = next.offset
        scale = next.scale
        gestureScale = 1.0
        magnifyFocalCanvasPoint = nil
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
            let canvasRect = CGRect(
                x: CGFloat(node.x),
                y: CGFloat(node.y),
                width: CGFloat(node.width),
                height: CGFloat(node.height)
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
        CanvasZoomController.clampScale(s)
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

}

// MARK: - ⌘A (select all visible nodes)

private final class CanvasSelectAllMonitorHostView: NSView {
    var onSelectAll: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else {
            installMonitorIfNeeded()
        }
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Plain ⌘A only — do not consume ⌘⇧A, ⌘⌥A, ⌃⌘A, etc.
            guard flags.contains(.command) else { return event }
            let nonSelectAllModifiers = flags.subtracting([.command, .capsLock])
            guard nonSelectAllModifiers.isEmpty else { return event }
            let ch = event.charactersIgnoringModifiers ?? ""
            guard ch == "a" || ch == "A" else { return event }
            guard CanvasZoomController.canHandleKeyboardShortcut(in: window) else { return event }
            self.onSelectAll?()
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct CanvasSelectAllKeyMonitor: NSViewRepresentable {
    @ObservedObject var viewModel: KommitViewModel

    func makeNSView(context: Context) -> CanvasSelectAllMonitorHostView {
        CanvasSelectAllMonitorHostView()
    }

    func updateNSView(_ host: CanvasSelectAllMonitorHostView, context: Context) {
        host.onSelectAll = { [viewModel] in
            viewModel.selectAllVisibleNodes()
        }
    }
}
