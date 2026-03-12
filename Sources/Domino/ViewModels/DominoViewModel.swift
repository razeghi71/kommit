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

    /// Find the closest node in each of 4 directions from a center point, excluding given IDs.
    private func closestNeighbors(from center: CGPoint, excluding: Set<UUID>) -> [UUID] {
        var closest: [DragDirection: (id: UUID, dist: CGFloat)] = [:]

        for (id, _) in nodes where !excluding.contains(id) {
            let pos = effectivePosition(id)
            let dx = pos.x - center.x
            let dy = pos.y - center.y
            let dist = sqrt(dx * dx + dy * dy)

            // Determine which side this node is on
            let direction: DragDirection
            if abs(dx) > abs(dy) {
                direction = dx > 0 ? .right : .left
            } else {
                direction = dy > 0 ? .bottom : .top
            }

            if closest[direction] == nil || dist < closest[direction]!.dist {
                closest[direction] = (id, dist)
            }
        }

        return closest.values.map(\.id)
    }

    /// Check alignment between dragged rect and a single target, returning best snap deltas.
    private func checkAlignment(
        draggedLeft: CGFloat, draggedRight: CGFloat, draggedCenterX: CGFloat,
        draggedTop: CGFloat, draggedBottom: CGFloat, draggedCenterY: CGFloat,
        targetID: UUID, threshold: CGFloat
    ) -> (snapX: (delta: CGFloat, guide: AlignmentGuide)?, snapY: (delta: CGFloat, guide: AlignmentGuide)?) {
        let targetPos = effectivePosition(targetID)
        let targetSize = nodeSizes[targetID] ?? NodeDefaults.size

        let targetLeft = targetPos.x - targetSize.width / 2
        let targetRight = targetPos.x + targetSize.width / 2
        let targetTop = targetPos.y - targetSize.height / 2
        let targetBottom = targetPos.y + targetSize.height / 2

        var snapX: (delta: CGFloat, guide: AlignmentGuide)? = nil
        var snapY: (delta: CGFloat, guide: AlignmentGuide)? = nil

        // X axis — edges match edges, center matches center
        for (draggedVal, targetVal) in [
            (draggedLeft, targetLeft), (draggedRight, targetRight), (draggedCenterX, targetPos.x),
        ] {
            let delta = targetVal - draggedVal
            if abs(delta) <= threshold && (snapX == nil || abs(delta) < abs(snapX!.delta)) {
                snapX = (delta, AlignmentGuide(axis: .vertical, position: targetVal, targetNodeID: targetID))
            }
        }

        // Y axis — edges match edges, center matches center
        for (draggedVal, targetVal) in [
            (draggedTop, targetTop), (draggedBottom, targetBottom), (draggedCenterY, targetPos.y),
        ] {
            let delta = targetVal - draggedVal
            if abs(delta) <= threshold && (snapY == nil || abs(delta) < abs(snapY!.delta)) {
                snapY = (delta, AlignmentGuide(axis: .horizontal, position: targetVal, targetNodeID: targetID))
            }
        }

        return (snapX, snapY)
    }

    /// Calculate snap result for a single dragged node.
    func calculateSnap(for nodeID: UUID, rawOffset: CGSize, threshold: CGFloat = 5) -> SnapResult {
        guard let node = nodes[nodeID] else {
            return SnapResult(snappedOffset: rawOffset, guides: [])
        }

        let draggedPos = CGPoint(
            x: node.position.x + rawOffset.width, y: node.position.y + rawOffset.height)
        let draggedSize = nodeSizes[nodeID] ?? NodeDefaults.size

        let draggedLeft = draggedPos.x - draggedSize.width / 2
        let draggedRight = draggedPos.x + draggedSize.width / 2
        let draggedTop = draggedPos.y - draggedSize.height / 2
        let draggedBottom = draggedPos.y + draggedSize.height / 2

        let excludeIDs: Set<UUID> = [nodeID]
        let neighbors = closestNeighbors(from: draggedPos, excluding: excludeIDs)

        var bestSnapX: (delta: CGFloat, guide: AlignmentGuide)? = nil
        var bestSnapY: (delta: CGFloat, guide: AlignmentGuide)? = nil

        for targetID in neighbors {
            let result = checkAlignment(
                draggedLeft: draggedLeft, draggedRight: draggedRight, draggedCenterX: draggedPos.x,
                draggedTop: draggedTop, draggedBottom: draggedBottom, draggedCenterY: draggedPos.y,
                targetID: targetID, threshold: threshold
            )
            if let sx = result.snapX, (bestSnapX == nil || abs(sx.delta) < abs(bestSnapX!.delta)) {
                bestSnapX = sx
            }
            if let sy = result.snapY, (bestSnapY == nil || abs(sy.delta) < abs(bestSnapY!.delta)) {
                bestSnapY = sy
            }
        }

        var adjustedOffset = rawOffset
        var guides: [AlignmentGuide] = []

        if let snapX = bestSnapX {
            adjustedOffset.width += snapX.delta
            guides.append(snapX.guide)
        }
        if let snapY = bestSnapY {
            adjustedOffset.height += snapY.delta
            guides.append(snapY.guide)
        }

        return SnapResult(snappedOffset: adjustedOffset, guides: guides)
    }

    /// Calculate snap result for a group of selected nodes.
    func calculateGroupSnap(for nodeIDs: Set<UUID>, rawOffset: CGSize, threshold: CGFloat = 5)
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

        let groupCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let neighbors = closestNeighbors(from: groupCenter, excluding: nodeIDs)

        var bestSnapX: (delta: CGFloat, guide: AlignmentGuide)? = nil
        var bestSnapY: (delta: CGFloat, guide: AlignmentGuide)? = nil

        for targetID in neighbors {
            let result = checkAlignment(
                draggedLeft: minX, draggedRight: maxX, draggedCenterX: groupCenter.x,
                draggedTop: minY, draggedBottom: maxY, draggedCenterY: groupCenter.y,
                targetID: targetID, threshold: threshold
            )
            if let sx = result.snapX, (bestSnapX == nil || abs(sx.delta) < abs(bestSnapX!.delta)) {
                bestSnapX = sx
            }
            if let sy = result.snapY, (bestSnapY == nil || abs(sy.delta) < abs(bestSnapY!.delta)) {
                bestSnapY = sy
            }
        }

        var adjustedOffset = rawOffset
        var guides: [AlignmentGuide] = []

        if let snapX = bestSnapX {
            adjustedOffset.width += snapX.delta
            guides.append(snapX.guide)
        }
        if let snapY = bestSnapY {
            adjustedOffset.height += snapY.delta
            guides.append(snapY.guide)
        }

        return SnapResult(snappedOffset: adjustedOffset, guides: guides)
    }
}
