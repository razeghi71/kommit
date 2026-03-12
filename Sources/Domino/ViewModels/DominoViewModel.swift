import AppKit
import SwiftUI

enum DragDirection: Sendable {
    case top, right, bottom, left
}

enum AlignmentAxis: Sendable {
    case horizontal  // a horizontal line (y value)
    case vertical  // a vertical line (x value)
}

struct AlignmentGuide: Equatable, Sendable {
    let axis: AlignmentAxis
    let position: CGFloat  // canvas coordinate of the line
    let targetNodeID: UUID  // the reference node this guide snaps to
}

struct SnapResult: Sendable {
    var snappedOffset: CGSize  // the adjusted offset after snapping
    var guides: [AlignmentGuide]  // active guide lines to display
}

struct EdgeDragState: Equatable {
    var sourceNodeID: UUID
    var direction: DragDirection
    var currentPoint: CGPoint
}

@MainActor
final class DominoViewModel: ObservableObject {
    @Published var nodes: [UUID: DominoNode] = [:]
    @Published var editingNodeID: UUID?
    @Published var selectedNodeID: UUID?
    @Published var selectedNodeIDs: Set<UUID> = []
    @Published var edgeDrag: EdgeDragState?
    @Published var dropTargetNodeID: UUID?
    @Published var selectedEdgeID: String?
    @Published var nodeDragOffset: [UUID: CGSize] = [:]
    @Published var nodeSizes: [UUID: CGSize] = [:]
    @Published var currentFileURL: URL?
    @Published var fileLoadID: UUID = UUID()
    @Published var activeGuides: [AlignmentGuide] = []
    @Published var canvasScale: CGFloat = 1.0

    private var undoStack: [[UUID: DominoNode]] = []
    private var redoStack: [[UUID: DominoNode]] = []
    private let maxUndoLevels = 50
    private(set) var isDirty = false

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func saveSnapshot() {
        undoStack.append(nodes)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        isDirty = true
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(nodes)
        nodes = snapshot
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(nodes)
        nodes = snapshot
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
    }

    var sortedNodes: [DominoNode] {
        Array(nodes.values).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var nodeDegrees: [UUID: Int] {
        var degrees: [UUID: Int] = [:]
        // Build children lookup
        var children: [UUID: [UUID]] = [:]
        for node in nodes.values {
            for pid in node.parentIDs where nodes[pid] != nil {
                children[pid, default: []].append(node.id)
            }
        }
        // BFS from all roots (degree 0)
        var queue: [UUID] = []
        for node in nodes.values
        where node.parentIDs.isEmpty || node.parentIDs.allSatisfy({ nodes[$0] == nil }) {
            degrees[node.id] = 0
            queue.append(node.id)
        }
        var idx = 0
        while idx < queue.count {
            let current = queue[idx]
            idx += 1
            let d = degrees[current]!
            for childID in children[current] ?? [] {
                if degrees[childID] == nil || d + 1 < degrees[childID]! {
                    degrees[childID] = d + 1
                    queue.append(childID)
                }
            }
        }
        return degrees
    }

    struct Edge: Identifiable {
        let id: String
        let parent: DominoNode
        let child: DominoNode
    }

    var edges: [Edge] {
        nodes.values.flatMap { child in
            child.parentIDs.compactMap { parentID in
                guard let parent = nodes[parentID] else { return nil }
                return Edge(id: "\(parentID)>\(child.id)", parent: parent, child: child)
            }
        }
    }

    func addNode(at position: CGPoint) {
        saveSnapshot()
        let node = DominoNode(position: position)
        nodes[node.id] = node
        editingNodeID = node.id
    }

    func addChildNode(parentID: UUID, direction: DragDirection, at dropPoint: CGPoint? = nil) {
        guard let parent = nodes[parentID] else { return }
        saveSnapshot()

        let offset: CGFloat = 180
        let position: CGPoint
        if let dropPoint {
            position = dropPoint
        } else {
            switch direction {
            case .top: position = CGPoint(x: parent.position.x, y: parent.position.y - offset)
            case .bottom: position = CGPoint(x: parent.position.x, y: parent.position.y + offset)
            case .left: position = CGPoint(x: parent.position.x - offset, y: parent.position.y)
            case .right: position = CGPoint(x: parent.position.x + offset, y: parent.position.y)
            }
        }

        let child = DominoNode(position: position, parentIDs: [parentID])
        nodes[child.id] = child
        editingNodeID = child.id
    }

    func effectivePosition(_ id: UUID) -> CGPoint {
        guard let node = nodes[id] else { return .zero }
        if let offset = nodeDragOffset[id] {
            return CGPoint(x: node.position.x + offset.width, y: node.position.y + offset.height)
        }
        return node.position
    }

    func moveNode(_ id: UUID, to position: CGPoint) {
        saveSnapshot()
        nodes[id]?.position = position
    }

    func setNodeColor(_ id: UUID, hex: String?) {
        saveSnapshot()
        nodes[id]?.colorHex = hex
    }

    func updateNodeText(_ id: UUID, text: String) {
        nodes[id]?.text = text
    }

    func deleteNode(_ id: UUID) {
        saveSnapshot()
        // Reparent children: replace this node with its parents in each child's parentIDs
        let deletedParentIDs = nodes[id]?.parentIDs ?? []
        for (childID, var child) in nodes where child.parentIDs.contains(id) {
            child.parentIDs.remove(id)
            child.parentIDs.formUnion(deletedParentIDs)
            nodes[childID] = child
        }
        nodes.removeValue(forKey: id)
        if editingNodeID == id {
            editingNodeID = nil
        }
    }

    func commitEditing() {
        editingNodeID = nil
    }

    /// Find a node at the given canvas point (excluding a specific node)
    func nodeAt(point: CGPoint, excluding: UUID) -> UUID? {
        for (id, _) in nodes where id != excluding {
            let pos = effectivePosition(id)
            let size = nodeSizes[id] ?? NodeDefaults.size
            if abs(point.x - pos.x) <= size.width / 2 && abs(point.y - pos.y) <= size.height / 2 {
                return id
            }
        }
        return nil
    }

    /// Toggle connection between source and target. Returns true if handled (landed on a node).
    func handleEdgeDrop(sourceID: UUID, dropPoint: CGPoint, direction: DragDirection) -> Bool {
        guard let targetID = nodeAt(point: dropPoint, excluding: sourceID) else {
            return false
        }

        saveSnapshot()
        // Toggle this specific parent-child connection
        if nodes[targetID]?.parentIDs.contains(sourceID) == true {
            // Disconnect
            nodes[targetID]?.parentIDs.remove(sourceID)
        } else {
            // Connect: add source as a parent of target
            nodes[targetID]?.parentIDs.insert(sourceID)
        }
        return true
    }

    func clearSelection() {
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
    }

    func selectNodesInRect(_ rect: CGRect) {
        var ids = Set<UUID>()
        for (id, node) in nodes {
            let size = nodeSizes[id] ?? NodeDefaults.size
            let nodeRect = CGRect(
                x: node.position.x - size.width / 2,
                y: node.position.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            if rect.intersects(nodeRect) {
                ids.insert(id)
            }
        }
        selectedNodeIDs = ids
        selectedNodeID = ids.first
    }

    func moveSelectedNodes(by offset: CGSize) {
        for id in selectedNodeIDs {
            nodeDragOffset[id] = offset
        }
    }

    func commitSelectedNodesMove(by offset: CGSize) {
        saveSnapshot()
        for id in selectedNodeIDs {
            if let node = nodes[id] {
                nodes[id]?.position = CGPoint(
                    x: node.position.x + offset.width,
                    y: node.position.y + offset.height
                )
            }
            nodeDragOffset.removeValue(forKey: id)
        }
    }

    func deleteSelectedNode() {
        guard let id = selectedNodeID else { return }
        selectedNodeID = nil
        selectedNodeIDs.remove(id)
        deleteNode(id)
    }

    func deleteSelectedEdge() {
        guard let edgeID = selectedEdgeID else { return }
        let parts = edgeID.split(separator: ">")
        guard parts.count == 2,
            let parentID = UUID(uuidString: String(parts[0])),
            let childID = UUID(uuidString: String(parts[1]))
        else { return }
        saveSnapshot()
        nodes[childID]?.parentIDs.remove(parentID)
        selectedEdgeID = nil
    }

    // MARK: - Unsaved changes guard

    func confirmDiscardIfNeeded(then action: @escaping () -> Void) {
        guard isDirty else {
            action()
            return
        }
        if Self.showDiscardAlert() {
            action()
        }
    }

    static func showDiscardAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Do you want to discard your current board?"
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - New / Save / Open

    func newBoard() {
        nodes.removeAll()
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
        currentFileURL = nil
        undoStack.removeAll()
        redoStack.removeAll()
        isDirty = false
        fileLoadID = UUID()
    }

    func save() {
        if let url = currentFileURL {
            writeToFile(url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Domino.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentFileURL = url
        writeToFile(url)
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        readFromFile(url)
    }

    private func writeToFile(_ url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(Array(nodes.values)) else { return }
        try? data.write(to: url)
        isDirty = false
    }

    private func readFromFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
            let loaded = try? JSONDecoder().decode([DominoNode].self, from: data)
        else { return }
        nodes = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        editingNodeID = nil
        currentFileURL = url
        isDirty = false
        fileLoadID = UUID()
    }

    // MARK: - Alignment / Snapping

    private struct SnapCandidate {
        let id: UUID
        let bounds: CGRect
        let center: CGPoint
    }

    private struct SnapStop {
        let value: CGFloat
        let targetNodeID: UUID
        let targetDistance: CGFloat
    }

    private let snapScreenThreshold: CGFloat = 8
    private let snapProximityPadding: CGFloat = 120
    private let snapEpsilon: CGFloat = 0.0001

    private var snapThresholdInCanvas: CGFloat {
        snapScreenThreshold / max(canvasScale, 0.01)
    }

    private func boundsForNode(_ id: UUID) -> CGRect {
        let pos = effectivePosition(id)
        let size = nodeSizes[id] ?? NodeDefaults.size
        return CGRect(
            x: pos.x - size.width / 2,
            y: pos.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Gather nearby snap candidates around dragged bounds (axis-aware proximity, no Euclidean direction bucketing).
    private func collectSnapCandidates(
        around draggedBounds: CGRect,
        excluding: Set<UUID>,
        threshold: CGFloat
    ) -> [SnapCandidate] {
        let expanded = draggedBounds.insetBy(
            dx: -(threshold + snapProximityPadding),
            dy: -(threshold + snapProximityPadding)
        )
        let axisReach = max(draggedBounds.width, draggedBounds.height) + snapProximityPadding
        let draggedCenter = CGPoint(x: draggedBounds.midX, y: draggedBounds.midY)

        var candidates: [SnapCandidate] = []
        candidates.reserveCapacity(nodes.count)

        for id in nodes.keys where !excluding.contains(id) {
            let bounds = boundsForNode(id)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)

            let isNearByRect = expanded.intersects(bounds)
            let isNearByAxis = abs(center.x - draggedCenter.x) <= axisReach
                || abs(center.y - draggedCenter.y) <= axisReach
            if isNearByRect || isNearByAxis {
                candidates.append(SnapCandidate(id: id, bounds: bounds, center: center))
            }
        }

        // Deterministic ordering to reduce frame-to-frame jitter.
        return candidates.sorted { lhs, rhs in
            if lhs.center.x != rhs.center.x { return lhs.center.x < rhs.center.x }
            if lhs.center.y != rhs.center.y { return lhs.center.y < rhs.center.y }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func buildSnapStops(
        from candidates: [SnapCandidate],
        draggedCenter: CGPoint
    ) -> (vertical: [SnapStop], horizontal: [SnapStop]) {
        var vertical: [SnapStop] = []
        var horizontal: [SnapStop] = []
        vertical.reserveCapacity(candidates.count * 3)
        horizontal.reserveCapacity(candidates.count * 3)

        for candidate in candidates {
            let distance = hypot(
                candidate.center.x - draggedCenter.x,
                candidate.center.y - draggedCenter.y
            )

            vertical.append(
                SnapStop(
                    value: candidate.bounds.minX,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
            vertical.append(
                SnapStop(
                    value: candidate.bounds.midX,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
            vertical.append(
                SnapStop(
                    value: candidate.bounds.maxX,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )

            horizontal.append(
                SnapStop(
                    value: candidate.bounds.minY,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
            horizontal.append(
                SnapStop(
                    value: candidate.bounds.midY,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
            horizontal.append(
                SnapStop(
                    value: candidate.bounds.maxY,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
        }

        return (vertical, horizontal)
    }

    /// Find best per-axis snap, keeping deterministic tie-breaking and collecting equivalent guide lines.
    private func bestSnap(
        for draggedValues: [CGFloat],
        against stops: [SnapStop],
        axis: AlignmentAxis,
        threshold: CGFloat
    ) -> (delta: CGFloat, guides: [AlignmentGuide])? {
        var bestDelta: CGFloat?
        var bestDistance = CGFloat.infinity
        var bestStop: SnapStop?
        var bestGuides: [AlignmentGuide] = []

        for draggedValue in draggedValues {
            for stop in stops {
                let delta = stop.value - draggedValue
                let distance = abs(delta)
                guard distance <= threshold else { continue }

                let guide = AlignmentGuide(axis: axis, position: stop.value, targetNodeID: stop.targetNodeID)

                if bestDelta == nil || distance < bestDistance - snapEpsilon {
                    bestDelta = delta
                    bestDistance = distance
                    bestStop = stop
                    bestGuides = [guide]
                    continue
                }

                guard let currentDelta = bestDelta, let currentStop = bestStop else { continue }
                if abs(distance - bestDistance) > snapEpsilon {
                    continue
                }

                // Same best distance. If delta is effectively identical, keep all equivalent guides.
                if abs(delta - currentDelta) <= snapEpsilon {
                    if !bestGuides.contains(guide) {
                        bestGuides.append(guide)
                    }
                    continue
                }

                // Deterministic tie-break: nearer candidate center, then UUID.
                if stop.targetDistance < currentStop.targetDistance - snapEpsilon
                    || (abs(stop.targetDistance - currentStop.targetDistance) <= snapEpsilon
                        && stop.targetNodeID.uuidString < currentStop.targetNodeID.uuidString)
                {
                    bestDelta = delta
                    bestStop = stop
                    bestGuides = [guide]
                }
            }
        }

        guard let finalDelta = bestDelta else { return nil }
        let sortedGuides = bestGuides.sorted { lhs, rhs in
            if lhs.position != rhs.position { return lhs.position < rhs.position }
            return lhs.targetNodeID.uuidString < rhs.targetNodeID.uuidString
        }
        return (finalDelta, sortedGuides)
    }

    private func calculateSnapResult(
        for draggedBounds: CGRect,
        excluding excludeIDs: Set<UUID>,
        rawOffset: CGSize,
        threshold: CGFloat
    ) -> SnapResult {
        let candidates = collectSnapCandidates(
            around: draggedBounds,
            excluding: excludeIDs,
            threshold: threshold
        )
        guard !candidates.isEmpty else {
            return SnapResult(snappedOffset: rawOffset, guides: [])
        }

        let draggedCenter = CGPoint(x: draggedBounds.midX, y: draggedBounds.midY)
        let stops = buildSnapStops(from: candidates, draggedCenter: draggedCenter)
        let xValues = [draggedBounds.minX, draggedBounds.midX, draggedBounds.maxX]
        let yValues = [draggedBounds.minY, draggedBounds.midY, draggedBounds.maxY]

        let snapX = bestSnap(
            for: xValues,
            against: stops.vertical,
            axis: .vertical,
            threshold: threshold
        )
        let snapY = bestSnap(
            for: yValues,
            against: stops.horizontal,
            axis: .horizontal,
            threshold: threshold
        )

        var adjustedOffset = rawOffset
        var guides: [AlignmentGuide] = []

        if let snapX {
            adjustedOffset.width += snapX.delta
            guides.append(contentsOf: snapX.guides)
        }
        if let snapY {
            adjustedOffset.height += snapY.delta
            guides.append(contentsOf: snapY.guides)
        }

        return SnapResult(snappedOffset: adjustedOffset, guides: guides)
    }

    /// Calculate snap result for a single dragged node.
    func calculateSnap(for nodeID: UUID, rawOffset: CGSize, threshold: CGFloat? = nil) -> SnapResult {
        guard let node = nodes[nodeID] else {
            return SnapResult(snappedOffset: rawOffset, guides: [])
        }

        let draggedPos = CGPoint(
            x: node.position.x + rawOffset.width,
            y: node.position.y + rawOffset.height
        )
        let draggedSize = nodeSizes[nodeID] ?? NodeDefaults.size
        let draggedBounds = CGRect(
            x: draggedPos.x - draggedSize.width / 2,
            y: draggedPos.y - draggedSize.height / 2,
            width: draggedSize.width,
            height: draggedSize.height
        )
        let resolvedThreshold = threshold ?? snapThresholdInCanvas
        return calculateSnapResult(
            for: draggedBounds,
            excluding: [nodeID],
            rawOffset: rawOffset,
            threshold: resolvedThreshold
        )
    }

    /// Calculate snap result for a group of selected nodes.
    func calculateGroupSnap(for nodeIDs: Set<UUID>, rawOffset: CGSize, threshold: CGFloat? = nil)
        -> SnapResult
    {
        guard !nodeIDs.isEmpty else {
            return SnapResult(snappedOffset: rawOffset, guides: [])
        }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for id in nodeIDs {
            guard let node = nodes[id] else { continue }
            let size = nodeSizes[id] ?? NodeDefaults.size
            let pos = CGPoint(
                x: node.position.x + rawOffset.width, y: node.position.y + rawOffset.height)
            minX = min(minX, pos.x - size.width / 2)
            maxX = max(maxX, pos.x + size.width / 2)
            minY = min(minY, pos.y - size.height / 2)
            maxY = max(maxY, pos.y + size.height / 2)
        }

        let draggedBounds = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        let resolvedThreshold = threshold ?? snapThresholdInCanvas
        return calculateSnapResult(
            for: draggedBounds,
            excluding: nodeIDs,
            rawOffset: rawOffset,
            threshold: resolvedThreshold
        )
    }
}
