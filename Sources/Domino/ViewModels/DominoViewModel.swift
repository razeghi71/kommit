import AppKit
import SwiftUI

enum DragDirection: Sendable {
    case top, right, bottom, left
}

enum AlignmentAxis: Sendable {
    case horizontal  // a horizontal line (y value)
    case vertical  // a vertical line (x value)
}

struct GuideSegment: Equatable, Sendable {
    let from: CGPoint
    let to: CGPoint
}

struct SnapGuide: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case alignmentLine
        case gapIndicator
    }

    let kind: Kind
    let axis: AlignmentAxis
    let position: CGFloat?
    let segments: [GuideSegment]
    let targetNodeIDs: [UUID]

    static func alignmentLine(axis: AlignmentAxis, position: CGFloat, targetNodeIDs: [UUID]) -> SnapGuide {
        SnapGuide(
            kind: .alignmentLine,
            axis: axis,
            position: position,
            segments: [],
            targetNodeIDs: Array(Set(targetNodeIDs)).sorted { $0.uuidString < $1.uuidString }
        )
    }

    static func gapIndicator(axis: AlignmentAxis, segments: [GuideSegment], targetNodeIDs: [UUID]) -> SnapGuide {
        SnapGuide(
            kind: .gapIndicator,
            axis: axis,
            position: nil,
            segments: segments,
            targetNodeIDs: Array(Set(targetNodeIDs)).sorted { $0.uuidString < $1.uuidString }
        )
    }
}

struct SnapResult: Sendable {
    var snappedOffset: CGSize  // the adjusted offset after snapping
    var guides: [SnapGuide]  // active guide lines to display
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
    @Published var activeGuides: [SnapGuide] = []
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

    private struct GapCandidate {
        let axis: AlignmentAxis
        let leading: SnapCandidate
        let trailing: SnapCandidate
        let gap: CGFloat
        let crossRange: ClosedRange<CGFloat>
        let targetDistance: CGFloat
    }

    private struct AxisSnap {
        let delta: CGFloat
        let distance: CGFloat
        let targetDistance: CGFloat
        let priority: Int
        let guides: [SnapGuide]
    }

    private let snapScreenThreshold: CGFloat = 8
    private let snapProximityPadding: CGFloat = 120
    private let snapEpsilon: CGFloat = 0.0001
    private let gapCrossAxisScreenTolerance: CGFloat = 32
    private let gapSnapScreenBonus: CGFloat = 4

    private var snapThresholdInCanvas: CGFloat {
        snapScreenThreshold / max(canvasScale, 0.01)
    }

    private var gapCrossAxisToleranceInCanvas: CGFloat {
        gapCrossAxisScreenTolerance / max(canvasScale, 0.01)
    }

    private var gapSnapBonusInCanvas: CGFloat {
        gapSnapScreenBonus / max(canvasScale, 0.01)
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

    private func overlapRange(
        startA: CGFloat,
        endA: CGFloat,
        startB: CGFloat,
        endB: CGFloat
    ) -> ClosedRange<CGFloat>? {
        let lower = max(startA, startB)
        let upper = min(endA, endB)
        guard lower <= upper else { return nil }
        return lower...upper
    }

    private func relaxedOverlapRange(
        startA: CGFloat,
        endA: CGFloat,
        startB: CGFloat,
        endB: CGFloat,
        tolerance: CGFloat
    ) -> ClosedRange<CGFloat>? {
        overlapRange(
            startA: startA - tolerance,
            endA: endA + tolerance,
            startB: startB - tolerance,
            endB: endB + tolerance
        )
    }

    private func mergeGuide(_ guide: SnapGuide, into guides: inout [SnapGuide]) {
        if let index = guides.firstIndex(where: {
            $0.kind == guide.kind
                && $0.axis == guide.axis
                && $0.position == guide.position
                && $0.segments == guide.segments
        }) {
            let mergedTargets = Array(Set(guides[index].targetNodeIDs + guide.targetNodeIDs))
                .sorted { $0.uuidString < $1.uuidString }
            let existing = guides[index]
            guides[index] = SnapGuide(
                kind: existing.kind,
                axis: existing.axis,
                position: existing.position,
                segments: existing.segments,
                targetNodeIDs: mergedTargets
            )
        } else {
            guides.append(guide)
        }
    }

    private func mergedGuides(_ guides: [SnapGuide]) -> [SnapGuide] {
        var merged: [SnapGuide] = []
        for guide in guides {
            mergeGuide(guide, into: &merged)
        }
        return merged.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .alignmentLine
            }
            if lhs.axis != rhs.axis {
                return lhs.axis == .vertical
            }
            if lhs.position != rhs.position {
                return (lhs.position ?? 0) < (rhs.position ?? 0)
            }
            return lhs.targetNodeIDs.map(\.uuidString).joined() < rhs.targetNodeIDs.map(\.uuidString).joined()
        }
    }

    private func sortedSnapCandidates(excluding: Set<UUID>) -> [SnapCandidate] {
        nodes.keys
            .filter { !excluding.contains($0) }
            .map { id in
                let bounds = boundsForNode(id)
                return SnapCandidate(
                    id: id,
                    bounds: bounds,
                    center: CGPoint(x: bounds.midX, y: bounds.midY)
                )
            }
            .sorted { lhs, rhs in
                if lhs.center.x != rhs.center.x { return lhs.center.x < rhs.center.x }
                if lhs.center.y != rhs.center.y { return lhs.center.y < rhs.center.y }
                return lhs.id.uuidString < rhs.id.uuidString
            }
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

        for candidate in sortedSnapCandidates(excluding: excluding) {
            let isNearByRect = expanded.intersects(candidate.bounds)
            let isNearByAxis = abs(candidate.center.x - draggedCenter.x) <= axisReach
                || abs(candidate.center.y - draggedCenter.y) <= axisReach
            if isNearByRect || isNearByAxis {
                candidates.append(candidate)
            }
        }
        return candidates
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

    private func buildGapCandidates(
        from candidates: [SnapCandidate],
        draggedCenter: CGPoint
    ) -> (x: [GapCandidate], y: [GapCandidate]) {
        let byX = candidates.sorted {
            if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
            return $0.id.uuidString < $1.id.uuidString
        }
        let byY = candidates.sorted {
            if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
            return $0.id.uuidString < $1.id.uuidString
        }

        var xGaps: [GapCandidate] = []
        var yGaps: [GapCandidate] = []

        if byX.count >= 2 {
            for leadingIndex in 0..<(byX.count - 1) {
                for trailingIndex in (leadingIndex + 1)..<byX.count {
                    let leading = byX[leadingIndex]
                    let trailing = byX[trailingIndex]
                let gap = trailing.bounds.minX - leading.bounds.maxX
                guard gap > snapEpsilon,
                    let crossRange = relaxedOverlapRange(
                        startA: leading.bounds.minY,
                        endA: leading.bounds.maxY,
                        startB: trailing.bounds.minY,
                        endB: trailing.bounds.maxY,
                        tolerance: gapCrossAxisToleranceInCanvas
                    )
                else { continue }

                    let hasBlockingCandidate = byX[(leadingIndex + 1)..<trailingIndex].contains { candidate in
                        candidate.bounds.minX < trailing.bounds.minX
                            && candidate.bounds.maxX > leading.bounds.maxX
                            && relaxedOverlapRange(
                                startA: candidate.bounds.minY,
                                endA: candidate.bounds.maxY,
                                startB: crossRange.lowerBound,
                                endB: crossRange.upperBound,
                                tolerance: gapCrossAxisToleranceInCanvas / 2
                            ) != nil
                    }
                    guard !hasBlockingCandidate else { continue }

                let targetDistance = min(
                    hypot(leading.center.x - draggedCenter.x, leading.center.y - draggedCenter.y),
                    hypot(trailing.center.x - draggedCenter.x, trailing.center.y - draggedCenter.y)
                )
                xGaps.append(
                    GapCandidate(
                        axis: .vertical,
                        leading: leading,
                        trailing: trailing,
                        gap: gap,
                        crossRange: crossRange,
                        targetDistance: targetDistance
                    )
                )
                }
            }
        }

        if byY.count >= 2 {
            for leadingIndex in 0..<(byY.count - 1) {
                for trailingIndex in (leadingIndex + 1)..<byY.count {
                    let leading = byY[leadingIndex]
                    let trailing = byY[trailingIndex]
                let gap = trailing.bounds.minY - leading.bounds.maxY
                guard gap > snapEpsilon,
                    let crossRange = relaxedOverlapRange(
                        startA: leading.bounds.minX,
                        endA: leading.bounds.maxX,
                        startB: trailing.bounds.minX,
                        endB: trailing.bounds.maxX,
                        tolerance: gapCrossAxisToleranceInCanvas
                    )
                else { continue }

                    let hasBlockingCandidate = byY[(leadingIndex + 1)..<trailingIndex].contains { candidate in
                        candidate.bounds.minY < trailing.bounds.minY
                            && candidate.bounds.maxY > leading.bounds.maxY
                            && relaxedOverlapRange(
                                startA: candidate.bounds.minX,
                                endA: candidate.bounds.maxX,
                                startB: crossRange.lowerBound,
                                endB: crossRange.upperBound,
                                tolerance: gapCrossAxisToleranceInCanvas / 2
                            ) != nil
                    }
                    guard !hasBlockingCandidate else { continue }

                let targetDistance = min(
                    hypot(leading.center.x - draggedCenter.x, leading.center.y - draggedCenter.y),
                    hypot(trailing.center.x - draggedCenter.x, trailing.center.y - draggedCenter.y)
                )
                yGaps.append(
                    GapCandidate(
                        axis: .horizontal,
                        leading: leading,
                        trailing: trailing,
                        gap: gap,
                        crossRange: crossRange,
                        targetDistance: targetDistance
                    )
                )
                }
            }
        }

        return (xGaps, yGaps)
    }

    /// Find best per-axis alignment snap, keeping deterministic tie-breaking and collecting equivalent guide lines.
    private func bestAlignmentSnap(
        for draggedValues: [CGFloat],
        against stops: [SnapStop],
        axis: AlignmentAxis,
        threshold: CGFloat
    ) -> AxisSnap? {
        var bestDelta: CGFloat?
        var bestDistance = CGFloat.infinity
        var bestStop: SnapStop?
        var bestGuides: [SnapGuide] = []

        for draggedValue in draggedValues {
            for stop in stops {
                let delta = stop.value - draggedValue
                let distance = abs(delta)
                guard distance <= threshold else { continue }

                let guide = SnapGuide.alignmentLine(
                    axis: axis,
                    position: stop.value,
                    targetNodeIDs: [stop.targetNodeID]
                )

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
                    mergeGuide(guide, into: &bestGuides)
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
        return AxisSnap(
            delta: finalDelta,
            distance: abs(finalDelta),
            targetDistance: bestStop?.targetDistance ?? .infinity,
            priority: 1,
            guides: mergedGuides(bestGuides)
        )
    }

    private func gapGuideSegments(
        for candidate: GapCandidate,
        snappedBounds: CGRect,
        placement: GapPlacement
    ) -> [GuideSegment] {
        switch candidate.axis {
        case .vertical:
            let indicator = min(
                max(snappedBounds.midY, candidate.crossRange.lowerBound),
                candidate.crossRange.upperBound
            )
            let existing = GuideSegment(
                from: CGPoint(x: candidate.leading.bounds.maxX, y: indicator),
                to: CGPoint(x: candidate.trailing.bounds.minX, y: indicator)
            )

            switch placement {
            case .before:
                return [
                    existing,
                    GuideSegment(
                        from: CGPoint(x: snappedBounds.maxX, y: indicator),
                        to: CGPoint(x: candidate.leading.bounds.minX, y: indicator)
                    ),
                ]
            case .after:
                return [
                    existing,
                    GuideSegment(
                        from: CGPoint(x: candidate.trailing.bounds.maxX, y: indicator),
                        to: CGPoint(x: snappedBounds.minX, y: indicator)
                    ),
                ]
            case .between:
                return [
                    GuideSegment(
                        from: CGPoint(x: candidate.leading.bounds.maxX, y: indicator),
                        to: CGPoint(x: snappedBounds.minX, y: indicator)
                    ),
                    GuideSegment(
                        from: CGPoint(x: snappedBounds.maxX, y: indicator),
                        to: CGPoint(x: candidate.trailing.bounds.minX, y: indicator)
                    ),
                ]
            }
        case .horizontal:
            let indicator = min(
                max(snappedBounds.midX, candidate.crossRange.lowerBound),
                candidate.crossRange.upperBound
            )
            let existing = GuideSegment(
                from: CGPoint(x: indicator, y: candidate.leading.bounds.maxY),
                to: CGPoint(x: indicator, y: candidate.trailing.bounds.minY)
            )

            switch placement {
            case .before:
                return [
                    existing,
                    GuideSegment(
                        from: CGPoint(x: indicator, y: snappedBounds.maxY),
                        to: CGPoint(x: indicator, y: candidate.leading.bounds.minY)
                    ),
                ]
            case .after:
                return [
                    existing,
                    GuideSegment(
                        from: CGPoint(x: indicator, y: candidate.trailing.bounds.maxY),
                        to: CGPoint(x: indicator, y: snappedBounds.minY)
                    ),
                ]
            case .between:
                return [
                    GuideSegment(
                        from: CGPoint(x: indicator, y: candidate.leading.bounds.maxY),
                        to: CGPoint(x: indicator, y: snappedBounds.minY)
                    ),
                    GuideSegment(
                        from: CGPoint(x: indicator, y: snappedBounds.maxY),
                        to: CGPoint(x: indicator, y: candidate.trailing.bounds.minY)
                    ),
                ]
            }
        }
    }

    private enum GapPlacement {
        case before
        case after
        case between
    }

    private func bestGapSnap(
        for draggedBounds: CGRect,
        against candidates: [GapCandidate],
        threshold: CGFloat
    ) -> AxisSnap? {
        var best: AxisSnap?
        let crossTolerance = gapCrossAxisToleranceInCanvas
        let gapThreshold = threshold + gapSnapBonusInCanvas

        for candidate in candidates {
            let isCrossAxisCompatible: Bool
            switch candidate.axis {
            case .vertical:
                isCrossAxisCompatible =
                    draggedBounds.maxY >= candidate.crossRange.lowerBound - crossTolerance
                    && draggedBounds.minY <= candidate.crossRange.upperBound + crossTolerance
            case .horizontal:
                isCrossAxisCompatible =
                    draggedBounds.maxX >= candidate.crossRange.lowerBound - crossTolerance
                    && draggedBounds.minX <= candidate.crossRange.upperBound + crossTolerance
            }

            guard isCrossAxisCompatible else { continue }

            var proposals: [(delta: CGFloat, placement: GapPlacement)] = []
            switch candidate.axis {
            case .vertical:
                proposals.append((
                    delta: (candidate.leading.bounds.minX - candidate.gap) - draggedBounds.maxX,
                    placement: .before
                ))
                proposals.append((
                    delta: (candidate.trailing.bounds.maxX + candidate.gap) - draggedBounds.minX,
                    placement: .after
                ))

                let available = candidate.trailing.bounds.minX - candidate.leading.bounds.maxX
                let centeredGap = (available - draggedBounds.width) / 2
                if centeredGap >= 0 {
                    proposals.append((
                        delta: (candidate.leading.bounds.maxX + centeredGap) - draggedBounds.minX,
                        placement: .between
                    ))
                }
            case .horizontal:
                proposals.append((
                    delta: (candidate.leading.bounds.minY - candidate.gap) - draggedBounds.maxY,
                    placement: .before
                ))
                proposals.append((
                    delta: (candidate.trailing.bounds.maxY + candidate.gap) - draggedBounds.minY,
                    placement: .after
                ))

                let available = candidate.trailing.bounds.minY - candidate.leading.bounds.maxY
                let centeredGap = (available - draggedBounds.height) / 2
                if centeredGap >= 0 {
                    proposals.append((
                        delta: (candidate.leading.bounds.maxY + centeredGap) - draggedBounds.minY,
                        placement: .between
                    ))
                }
            }

            for proposal in proposals {
                let distance = abs(proposal.delta)
                guard distance <= gapThreshold else { continue }

                let snappedBounds: CGRect
                switch candidate.axis {
                case .vertical:
                    snappedBounds = draggedBounds.offsetBy(dx: proposal.delta, dy: 0)
                case .horizontal:
                    snappedBounds = draggedBounds.offsetBy(dx: 0, dy: proposal.delta)
                }

                let snap = AxisSnap(
                    delta: proposal.delta,
                    distance: distance,
                    targetDistance: candidate.targetDistance,
                    priority: 0,
                    guides: [
                        .gapIndicator(
                            axis: candidate.axis,
                            segments: gapGuideSegments(
                                for: candidate,
                                snappedBounds: snappedBounds,
                                placement: proposal.placement
                            ),
                            targetNodeIDs: [candidate.leading.id, candidate.trailing.id]
                        )
                    ]
                )

                if shouldPrefer(snap, over: best) {
                    best = snap
                } else if let current = best,
                    abs(snap.distance - current.distance) <= snapEpsilon,
                    abs(snap.delta - current.delta) <= snapEpsilon
                {
                    var merged = current.guides
                    for guide in snap.guides {
                        mergeGuide(guide, into: &merged)
                    }
                    best = AxisSnap(
                        delta: current.delta,
                        distance: current.distance,
                        targetDistance: min(current.targetDistance, snap.targetDistance),
                        priority: min(current.priority, snap.priority),
                        guides: mergedGuides(merged)
                    )
                }
            }
        }

        return best.map {
            AxisSnap(
                delta: $0.delta,
                distance: $0.distance,
                targetDistance: $0.targetDistance,
                priority: $0.priority,
                guides: mergedGuides($0.guides)
            )
        }
    }

    private func shouldPrefer(_ candidate: AxisSnap, over current: AxisSnap?) -> Bool {
        guard let current else { return true }
        if candidate.distance < current.distance - snapEpsilon { return true }
        if abs(candidate.distance - current.distance) > snapEpsilon { return false }

        if candidate.priority != current.priority {
            return candidate.priority < current.priority
        }

        if abs(candidate.delta - current.delta) <= snapEpsilon {
            return candidate.targetDistance < current.targetDistance - snapEpsilon
        }

        if candidate.targetDistance < current.targetDistance - snapEpsilon { return true }
        if abs(candidate.targetDistance - current.targetDistance) > snapEpsilon { return false }
        return candidate.delta < current.delta
    }

    private func chooseBestSnap(_ snaps: [AxisSnap?]) -> AxisSnap? {
        var best: AxisSnap?

        for snap in snaps.compactMap({ $0 }) {
            if shouldPrefer(snap, over: best) {
                best = snap
            } else if let current = best,
                abs(snap.distance - current.distance) <= snapEpsilon,
                abs(snap.delta - current.delta) <= snapEpsilon
            {
                var merged = current.guides
                for guide in snap.guides {
                    mergeGuide(guide, into: &merged)
                }
                best = AxisSnap(
                    delta: current.delta,
                    distance: current.distance,
                    targetDistance: min(current.targetDistance, snap.targetDistance),
                    priority: min(current.priority, snap.priority),
                    guides: mergedGuides(merged)
                )
            }
        }

        return best
    }

    private func calculateSnapResult(
        for draggedBounds: CGRect,
        excluding excludeIDs: Set<UUID>,
        rawOffset: CGSize,
        threshold: CGFloat
    ) -> SnapResult {
        let alignmentCandidates = collectSnapCandidates(
            around: draggedBounds,
            excluding: excludeIDs,
            threshold: threshold
        )
        let gapReferenceCandidates = sortedSnapCandidates(excluding: excludeIDs)
        guard !alignmentCandidates.isEmpty || !gapReferenceCandidates.isEmpty else {
            return SnapResult(snappedOffset: rawOffset, guides: [])
        }

        let draggedCenter = CGPoint(x: draggedBounds.midX, y: draggedBounds.midY)
        let stops = buildSnapStops(from: alignmentCandidates, draggedCenter: draggedCenter)
        let gapCandidates = buildGapCandidates(from: gapReferenceCandidates, draggedCenter: draggedCenter)
        let xValues = [draggedBounds.minX, draggedBounds.midX, draggedBounds.maxX]
        let yValues = [draggedBounds.minY, draggedBounds.midY, draggedBounds.maxY]

        let alignmentX = bestAlignmentSnap(
            for: xValues,
            against: stops.vertical,
            axis: .vertical,
            threshold: threshold
        )
        let alignmentY = bestAlignmentSnap(
            for: yValues,
            against: stops.horizontal,
            axis: .horizontal,
            threshold: threshold
        )
        let gapX = bestGapSnap(
            for: draggedBounds,
            against: gapCandidates.x,
            threshold: threshold
        )
        let gapY = bestGapSnap(
            for: draggedBounds,
            against: gapCandidates.y,
            threshold: threshold
        )

        let snapX = chooseBestSnap([alignmentX, gapX])
        let snapY = chooseBestSnap([alignmentY, gapY])

        var adjustedOffset = rawOffset
        var guides: [SnapGuide] = []

        if let snapX {
            adjustedOffset.width += snapX.delta
            guides.append(contentsOf: snapX.guides)
        }
        if let snapY {
            adjustedOffset.height += snapY.delta
            guides.append(contentsOf: snapY.guides)
        }

        return SnapResult(snappedOffset: adjustedOffset, guides: mergedGuides(guides))
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
