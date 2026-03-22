import AppKit
import SwiftUI

enum DragDirection: Sendable {
    case top, right, bottom, left
}

enum AlignmentAxis: Sendable {
    case horizontal  // a horizontal line (y value)
    case vertical  // a vertical line (x value)
}

/// Distribute multi-selected nodes to a common edge using the extreme node on that axis.
enum NodeAlignment: Sendable {
    case left, right, top, bottom
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

struct NodeFocusRequest: Equatable {
    let nodeID: UUID
    let token = UUID()
}

struct SearchPresentationRequest: Equatable {
    let token = UUID()
}

/// One row in the table view: live `node` snapshot plus a stripe group for alternating backgrounds by connected component.
struct DominoTableRow: Identifiable, Equatable {
    let id: UUID
    let node: DominoNode
    let stripeGroupIndex: Int
}

@MainActor
package final class DominoViewModel: ObservableObject {
    @Published var nodes: [UUID: DominoNode] = [:]
    @Published var systemStatusSettings: DominoStatusSettings
    @Published var fileStatusSettings: DominoStatusSettings?
    @Published package var editingNodeID: UUID?
    @Published package var selectedNodeID: UUID?
    @Published package var selectedNodeIDs: Set<UUID> = []
    @Published var edgeDrag: EdgeDragState?
    @Published var dropTargetNodeID: UUID?
    @Published package var selectedEdgeID: String?
    @Published var nodeDragOffset: [UUID: CGSize] = [:]
    @Published var nodeSizes: [UUID: CGSize] = [:]
    @Published var currentFileURL: URL?
    @Published var fileLoadID: UUID = UUID()
    @Published var activeGuides: [SnapGuide] = []
    @Published var canvasScale: CGFloat = 1.0
    @Published package var showHiddenItems = false
    @Published var canvasFocusRequest: NodeFocusRequest?
    @Published var tableFocusRequest: NodeFocusRequest?
    @Published var searchPresentationRequest: SearchPresentationRequest?
    /// Incremented to request resetting canvas pan/zoom to the default framing; handled in `CanvasView`.
    @Published private(set) var canvasRecenterToken: UInt64 = 0

    private var lastAppliedCanvasRecenterToken: UInt64 = 0
    private let userDefaults = UserDefaults.standard
    private let systemStatusSettingsKey = "domino.systemStatusSettings"

    private var undoStack: [[UUID: DominoNode]] = []
    private var redoStack: [[UUID: DominoNode]] = []
    private let maxUndoLevels = 50
    package private(set) var isDirty = false

    package var canUndo: Bool { !undoStack.isEmpty }
    package var canRedo: Bool { !redoStack.isEmpty }
    var activeStatusSettings: DominoStatusSettings { fileStatusSettings ?? systemStatusSettings }
    var hasFileStatusSettings: Bool { fileStatusSettings != nil }

    /// Set from the main SwiftUI window (`ContentView`). AppKit-hosted cells (table rows) do not receive
    /// `EnvironmentValues.openWindow`, so they must call this instead of `@Environment(\.openWindow)`.
    var openSettingsWindowAction: (() -> Void)?

    func openSettingsWindow() {
        openSettingsWindowAction?()
    }

    package init() {
        systemStatusSettings = DominoViewModel.loadSystemStatusSettings(from: UserDefaults.standard, key: "domino.systemStatusSettings")
    }

    private func saveSnapshot() {
        undoStack.append(nodes)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        isDirty = true
    }

    package func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(nodes)
        nodes = snapshot
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
    }

    package func redo() {
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

    var visibleNodes: [DominoNode] {
        sortedNodes.filter { showHiddenItems || !$0.isHidden }
    }

    /// Table order: repeated “topmost rank‑0 root in what’s left” → whole undirected connected component, nodes sorted by visible rank then canvas position.
    var tableRows: [DominoTableRow] {
        let visible = visibleNodes
        let visibleIDs = Set(visible.map(\.id))
        guard !visibleIDs.isEmpty else { return [] }

        let ranks = nodeDegrees
        var children: [UUID: [UUID]] = [:]
        for id in visibleIDs {
            guard let node = nodes[id] else { continue }
            for pid in node.parentIDs where visibleIDs.contains(pid) {
                children[pid, default: []].append(id)
            }
        }

        func neighbors(of id: UUID) -> [UUID] {
            var n = Set<UUID>()
            n.formUnion(children[id] ?? [])
            if let node = nodes[id] {
                for pid in node.parentIDs where visibleIDs.contains(pid) {
                    n.insert(pid)
                }
            }
            return Array(n)
        }

        func component(startingAt start: UUID) -> Set<UUID> {
            var stack: [UUID] = [start]
            var seen = Set<UUID>()
            while let v = stack.popLast() {
                if seen.contains(v) { continue }
                seen.insert(v)
                for u in neighbors(of: v) {
                    if !seen.contains(u) { stack.append(u) }
                }
            }
            return seen
        }

        func topLeftFirst(_ a: UUID, _ b: UUID) -> Bool {
            let pa = effectivePosition(a)
            let pb = effectivePosition(b)
            if pa.y != pb.y { return pa.y < pb.y }
            if pa.x != pb.x { return pa.x < pb.x }
            return a.uuidString < b.uuidString
        }

        func rankSortFirst(_ a: UUID, _ b: UUID) -> Bool {
            let ra = ranks[a] ?? Int.max
            let rb = ranks[b] ?? Int.max
            if ra != rb { return ra < rb }
            return topLeftFirst(a, b)
        }

        var unlisted = visibleIDs
        var rows: [DominoTableRow] = []
        var group = 0

        while !unlisted.isEmpty {
            guard let nextRoot = pickNextTableRoot(unlisted: unlisted, ranks: ranks, topLeftFirst: topLeftFirst)
            else { break }
            let comp = component(startingAt: nextRoot)
            let orderedIDs = comp.sorted(by: rankSortFirst)
            let stripe = group
            for id in orderedIDs {
                guard let node = nodes[id] else { continue }
                rows.append(DominoTableRow(id: id, node: node, stripeGroupIndex: stripe))
            }
            unlisted.subtract(comp)
            group += 1
        }

        return rows
    }

    private func pickNextTableRoot(
        unlisted: Set<UUID>,
        ranks: [UUID: Int],
        topLeftFirst: (UUID, UUID) -> Bool
    ) -> UUID? {
        guard !unlisted.isEmpty else { return nil }
        let rank0 = unlisted.filter { ranks[$0] == 0 }
        if let best = rank0.min(by: topLeftFirst) {
            return best
        }
        return unlisted.min(by: topLeftFirst)
    }

    private func isNodeVisible(_ id: UUID) -> Bool {
        guard let node = nodes[id] else { return false }
        return showHiddenItems || !node.isHidden
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
                if !showHiddenItems, (child.isHidden || parent.isHidden) {
                    return nil
                }
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

    /// Axis-aligned bounds in canvas space (uses drag preview via `effectivePosition` and measured `nodeSizes`).
    func canvasBounds(forNode id: UUID) -> CGRect? {
        guard nodes[id] != nil else { return nil }
        let pos = effectivePosition(id)
        let size = nodeSizes[id] ?? NodeDefaults.size
        return CGRect(
            x: pos.x - size.width / 2,
            y: pos.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func canvasBoundsUnion<S: Sequence>(nodeIDs: S) -> CGRect? where S.Element == UUID {
        var union: CGRect?
        for id in nodeIDs {
            guard let rect = canvasBounds(forNode: id) else { continue }
            union = union.map { $0.union(rect) } ?? rect
        }
        return union
    }

    func moveNode(_ id: UUID, to position: CGPoint) {
        saveSnapshot()
        nodes[id]?.position = position
    }

    func setNodeStatus(_ id: UUID, statusID: UUID?) {
        saveSnapshot()
        nodes[id]?.statusID = normalizedStatusID(statusID, settings: activeStatusSettings)
        nodes[id]?.legacyColorHex = nil
    }

    func setNodeStatuses(_ ids: Set<UUID>, statusID: UUID?) {
        guard !ids.isEmpty else { return }
        saveSnapshot()
        for id in ids {
            nodes[id]?.statusID = normalizedStatusID(statusID, settings: activeStatusSettings)
            nodes[id]?.legacyColorHex = nil
        }
    }

    func setNodePlannedDate(_ id: UUID, date: Date?) {
        saveSnapshot()
        nodes[id]?.plannedDate = date
    }

    func setNodePlannedDates(_ ids: Set<UUID>, date: Date?) {
        guard !ids.isEmpty else { return }
        saveSnapshot()
        for id in ids {
            nodes[id]?.plannedDate = date
        }
    }

    func setNodeBudget(_ id: UUID, budget: Double?) {
        saveSnapshot()
        nodes[id]?.budget = budget
    }

    func setNodeBudgets(_ ids: Set<UUID>, budget: Double?) {
        guard !ids.isEmpty else { return }
        saveSnapshot()
        for id in ids {
            nodes[id]?.budget = budget
        }
    }

    func contextMenuTargetNodeIDs(for anchorNodeID: UUID) -> Set<UUID> {
        let selectedSet: Set<UUID>
        if !selectedNodeIDs.isEmpty {
            selectedSet = selectedNodeIDs
        } else if let selectedNodeID {
            selectedSet = [selectedNodeID]
        } else {
            selectedSet = []
        }

        return selectedSet.contains(anchorNodeID) ? selectedSet : [anchorNodeID]
    }

    /// Aligns every node in `ids` to the same minX, maxX, minY, or maxY as the extreme among the selection (uses stored positions and measured sizes).
    func alignNodes(_ ids: Set<UUID>, alignment: NodeAlignment) {
        guard ids.count >= 2 else { return }
        let targets = ids.filter { nodes[$0] != nil }
        guard targets.count >= 2 else { return }

        var rects: [(UUID, CGRect)] = []
        rects.reserveCapacity(targets.count)
        for id in targets {
            guard let node = nodes[id] else { continue }
            let size = nodeSizes[id] ?? NodeDefaults.size
            let rect = CGRect(
                x: node.position.x - size.width / 2,
                y: node.position.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            rects.append((id, rect))
        }
        guard rects.count >= 2 else { return }

        saveSnapshot()

        switch alignment {
        case .left:
            let ref = rects.map(\.1.minX).min()!
            for (id, _) in rects {
                let w = (nodeSizes[id] ?? NodeDefaults.size).width
                nodes[id]?.position.x = ref + w / 2
            }
        case .right:
            let ref = rects.map(\.1.maxX).max()!
            for (id, _) in rects {
                let w = (nodeSizes[id] ?? NodeDefaults.size).width
                nodes[id]?.position.x = ref - w / 2
            }
        case .top:
            let ref = rects.map(\.1.minY).min()!
            for (id, _) in rects {
                let h = (nodeSizes[id] ?? NodeDefaults.size).height
                nodes[id]?.position.y = ref + h / 2
            }
        case .bottom:
            let ref = rects.map(\.1.maxY).max()!
            for (id, _) in rects {
                let h = (nodeSizes[id] ?? NodeDefaults.size).height
                nodes[id]?.position.y = ref - h / 2
            }
        }

        for id in targets {
            nodeDragOffset.removeValue(forKey: id)
        }
    }

    func areAllNodesHidden(_ ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { nodes[$0]?.isHidden == true }
    }

    func setNodesHidden(_ ids: Set<UUID>, isHidden: Bool) {
        guard !ids.isEmpty else { return }
        let targetIDs = ids.filter { nodes[$0]?.isHidden != isHidden }
        guard !targetIDs.isEmpty else { return }
        saveSnapshot()
        for id in targetIDs {
            nodes[id]?.isHidden = isHidden
        }
        pruneSelectionForHiddenItems()
    }

    package func setShowHiddenItems(_ show: Bool) {
        showHiddenItems = show
        pruneSelectionForHiddenItems()
    }

    func statusDefinition(for statusID: UUID?) -> DominoStatusDefinition {
        activeStatusSettings.definition(for: statusID)
    }

    func addFileStatusSettings() {
        guard fileStatusSettings == nil else { return }
        fileStatusSettings = systemStatusSettings
        clearInvalidNodeStatusesForActiveSettings()
        isDirty = true
    }

    func removeFileStatusSettings() {
        guard fileStatusSettings != nil else { return }
        fileStatusSettings = nil
        clearInvalidNodeStatusesForActiveSettings()
        isDirty = true
    }

    func addStatus(forFileSettings: Bool) {
        mutateStatusSettings(forFileSettings: forFileSettings) { settings in
            settings.statusPalette.append(
                DominoStatusDefinition(
                    id: UUID(),
                    name: settings.nextStatusName(),
                    colorHex: settings.nextStatusColorHex()
                )
            )
        }
    }

    func updateStatusName(_ id: UUID, name: String, forFileSettings: Bool) {
        mutateStatusSettings(forFileSettings: forFileSettings) { settings in
            guard let index = settings.statusPalette.firstIndex(where: { $0.id == id }) else { return }
            settings.statusPalette[index].name = name
        }
    }

    func updateStatusColor(_ id: UUID, colorHex: String, forFileSettings: Bool) {
        guard id != DominoStatusSettings.noneStatusID else { return }
        mutateStatusSettings(forFileSettings: forFileSettings) { settings in
            guard let index = settings.statusPalette.firstIndex(where: { $0.id == id }) else { return }
            settings.statusPalette[index].colorHex = colorHex
        }
    }

    func removeStatus(_ id: UUID, forFileSettings: Bool) {
        guard canRemoveStatus(id) else { return }
        mutateStatusSettings(forFileSettings: forFileSettings) { settings in
            settings.statusPalette.removeAll { $0.id == id }
        }
    }

    func canRemoveStatus(_ id: UUID) -> Bool {
        id != DominoStatusSettings.noneStatusID
    }

    private func mutateStatusSettings(forFileSettings: Bool, update: (inout DominoStatusSettings) -> Void) {
        var settings = forFileSettings ? (fileStatusSettings ?? systemStatusSettings) : systemStatusSettings
        update(&settings)
        settings = DominoStatusSettings(statusPalette: settings.statusPalette)

        if forFileSettings {
            fileStatusSettings = settings
            isDirty = true
        } else {
            systemStatusSettings = settings
            persistSystemStatusSettings()
        }

        clearInvalidNodeStatusesForActiveSettings()
    }

    private func normalizedStatusID(_ statusID: UUID?, settings: DominoStatusSettings) -> UUID? {
        guard let statusID else { return nil }
        guard statusID != DominoStatusSettings.noneStatusID else { return nil }
        return settings.containsStatus(statusID) ? statusID : nil
    }

    private func clearInvalidNodeStatusesForActiveSettings() {
        let validIDs = Set(activeStatusSettings.statusPalette.map(\.id))
        for id in nodes.keys {
            guard let statusID = nodes[id]?.statusID else {
                nodes[id]?.legacyColorHex = nil
                continue
            }
            if !validIDs.contains(statusID) || statusID == DominoStatusSettings.noneStatusID {
                nodes[id]?.statusID = nil
            }
            nodes[id]?.legacyColorHex = nil
        }
    }

    private static func loadSystemStatusSettings(from defaults: UserDefaults, key: String) -> DominoStatusSettings {
        guard let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(DominoStatusSettings.self, from: data)
        else {
            return .defaultValue
        }
        return decoded
    }

    private func persistSystemStatusSettings() {
        guard let data = try? JSONEncoder().encode(systemStatusSettings) else { return }
        userDefaults.set(data, forKey: systemStatusSettingsKey)
    }

    private struct DecodedBoard {
        let nodes: [DominoNode]
        let fileStatusSettings: DominoStatusSettings?
    }

    private struct MigratedNodes {
        let nodes: [DominoNode]
        let fileStatusSettings: DominoStatusSettings?
    }

    private func decodeBoard(from data: Data) -> DecodedBoard? {
        let decoder = JSONDecoder()

        if let document = try? decoder.decode(DominoDocument.self, from: data) {
            let explicitFileSettings = document.settings.map { DominoStatusSettings(statusPalette: $0.statusPalette) }
            let migrated = migrateLoadedNodes(document.nodes, baseSettings: explicitFileSettings ?? systemStatusSettings)
            return DecodedBoard(
                nodes: migrated.nodes,
                fileStatusSettings: migrated.fileStatusSettings ?? explicitFileSettings
            )
        }

        guard let legacyNodes = try? decoder.decode([DominoNode].self, from: data) else { return nil }
        let migrated = migrateLoadedNodes(legacyNodes, baseSettings: systemStatusSettings)
        return DecodedBoard(nodes: migrated.nodes, fileStatusSettings: migrated.fileStatusSettings)
    }

    private func migrateLoadedNodes(_ loadedNodes: [DominoNode], baseSettings: DominoStatusSettings) -> MigratedNodes {
        var migratedNodes: [DominoNode] = []
        migratedNodes.reserveCapacity(loadedNodes.count)

        var resolvedSettings = baseSettings
        var customStatusesByHex: [String: UUID] = [:]
        var createdFileSettings = false

        for node in loadedNodes {
            var updated = node
            let legacyHex = DominoStatusSettings.normalizedHex(node.legacyColorHex)

            if !legacyHex.isEmpty {
                if let existingStatusID = resolvedSettings.matchingStatusID(forLegacyColorHex: legacyHex) {
                    updated.statusID = normalizedStatusID(existingStatusID, settings: resolvedSettings)
                } else {
                    if let reusedStatusID = customStatusesByHex[legacyHex] {
                        updated.statusID = reusedStatusID
                    } else {
                        createdFileSettings = true
                        let newStatus = DominoStatusDefinition(
                            id: UUID(),
                            name: makeUniqueStatusName(
                                baseName: DominoStatusSettings.legacyFallbackName(for: legacyHex),
                                existingSettings: resolvedSettings
                            ),
                            colorHex: legacyHex
                        )
                        resolvedSettings.statusPalette.append(newStatus)
                        resolvedSettings = DominoStatusSettings(statusPalette: resolvedSettings.statusPalette)
                        customStatusesByHex[legacyHex] = newStatus.id
                        updated.statusID = newStatus.id
                    }
                }
            } else {
                updated.statusID = normalizedStatusID(node.statusID, settings: resolvedSettings)
            }

            updated.legacyColorHex = nil
            migratedNodes.append(updated)
        }

        return MigratedNodes(
            nodes: migratedNodes,
            fileStatusSettings: createdFileSettings ? resolvedSettings : nil
        )
    }

    private func makeUniqueStatusName(baseName: String, existingSettings: DominoStatusSettings) -> String {
        let existing = Set(existingSettings.statusPalette.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedBase.isEmpty ? "Custom Status" : trimmedBase
        guard existing.contains(fallback.lowercased()) else { return fallback }

        var suffix = 2
        while existing.contains("\(fallback) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(fallback) \(suffix)"
    }

    func updateNodeText(_ id: UUID, text: String) {
        nodes[id]?.text = text
    }

    /// Persists a full node `text` change with undo support (e.g. table editing).
    func commitNodeTextIfChanged(_ id: UUID, text: String) {
        guard nodes[id]?.text != text else { return }
        saveSnapshot()
        nodes[id]?.text = text
    }

    package func deleteNode(_ id: UUID) {
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
        for (id, _) in nodes where id != excluding && isNodeVisible(id) {
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

    package func clearSelection() {
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
    }

    func selectSingleNode(_ id: UUID) {
        guard isNodeVisible(id) else { return }
        commitEditing()
        selectedNodeID = id
        selectedNodeIDs = [id]
        selectedEdgeID = nil
    }

    func requestCanvasFocus(on id: UUID) {
        guard isNodeVisible(id) else { return }
        canvasFocusRequest = NodeFocusRequest(nodeID: id)
    }

    package func requestCanvasRecenter() {
        canvasRecenterToken &+= 1
    }

    var isCanvasRecenterPending: Bool {
        canvasRecenterToken != lastAppliedCanvasRecenterToken
    }

    func markCanvasRecenterApplied() {
        lastAppliedCanvasRecenterToken = canvasRecenterToken
    }

    func requestTableFocus(on id: UUID) {
        guard isNodeVisible(id) else { return }
        tableFocusRequest = NodeFocusRequest(nodeID: id)
    }

    func selectFirstVisibleNode(matching query: String) -> UUID? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let node = visibleNodes.first(where: { $0.text.localizedCaseInsensitiveContains(trimmed) }) else {
            return nil
        }
        selectSingleNode(node.id)
        return node.id
    }

    package func presentSearch() {
        searchPresentationRequest = SearchPresentationRequest()
    }

    private func pruneSelectionForHiddenItems() {
        guard !showHiddenItems else { return }

        selectedNodeIDs = selectedNodeIDs.filter { nodes[$0]?.isHidden != true }
        if let selectedNodeID, nodes[selectedNodeID]?.isHidden == true {
            self.selectedNodeID = selectedNodeIDs.first
        }

        if let edgeID = selectedEdgeID {
            let parts = edgeID.split(separator: ">")
            if parts.count == 2,
                let parentID = UUID(uuidString: String(parts[0])),
                let childID = UUID(uuidString: String(parts[1]))
            {
                if nodes[parentID]?.isHidden == true || nodes[childID]?.isHidden == true {
                    selectedEdgeID = nil
                }
            }
        }
    }

    func selectNodesInRect(_ rect: CGRect) {
        var ids = Set<UUID>()
        for (id, node) in nodes {
            guard isNodeVisible(id) else { continue }
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

    package func deleteSelectedNode() {
        guard let id = selectedNodeID else { return }
        selectedNodeID = nil
        selectedNodeIDs.remove(id)
        deleteNode(id)
    }

    package func deleteSelectedEdge() {
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

    package func confirmDiscardIfNeeded(then action: @escaping () -> Void) {
        guard isDirty else {
            action()
            return
        }
        if Self.showDiscardAlert() {
            action()
        }
    }

    package static func showDiscardAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Do you want to discard your current board?"
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - New / Save / Open

    package func newBoard() {
        nodes.removeAll()
        fileStatusSettings = nil
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

    package func save() {
        if let url = currentFileURL {
            writeToFile(url)
        } else {
            saveAs()
        }
    }

    package func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Domino.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentFileURL = url
        writeToFile(url)
    }

    package func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        readFromFile(url)
    }

    private func writeToFile(_ url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let document = DominoDocument(
            nodes: sortedNodes,
            settings: fileStatusSettings == systemStatusSettings ? nil : fileStatusSettings
        )
        guard let data = try? encoder.encode(document) else { return }
        try? data.write(to: url)
        isDirty = false
    }

    private func readFromFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
            let loaded = decodeBoard(from: data)
        else { return }
        nodes = Dictionary(uniqueKeysWithValues: loaded.nodes.map { ($0.id, $0) })
        fileStatusSettings = loaded.fileStatusSettings
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
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
        enum Anchor {
            case leading
            case center
            case trailing
        }

        let anchor: Anchor
        let value: CGFloat
        let targetNodeID: UUID
        let targetDistance: CGFloat
    }

    private struct DraggedStop {
        let anchor: SnapStop.Anchor
        let value: CGFloat
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
            .filter { !excluding.contains($0) && isNodeVisible($0) }
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
                    anchor: .leading,
                    value: candidate.bounds.minX,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
            vertical.append(
                SnapStop(
                    anchor: .center,
                    value: candidate.bounds.midX,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
            vertical.append(
                SnapStop(
                    anchor: .trailing,
                    value: candidate.bounds.maxX,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )

            horizontal.append(
                SnapStop(
                    anchor: .leading,
                    value: candidate.bounds.minY,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
            horizontal.append(
                SnapStop(
                    anchor: .center,
                    value: candidate.bounds.midY,
                    targetNodeID: candidate.id,
                    targetDistance: distance
                )
            )
            horizontal.append(
                SnapStop(
                    anchor: .trailing,
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
        for draggedStops: [DraggedStop],
        against stops: [SnapStop],
        axis: AlignmentAxis,
        threshold: CGFloat
    ) -> AxisSnap? {
        var bestDelta: CGFloat?
        var bestDistance = CGFloat.infinity
        var bestStop: SnapStop?
        var bestGuides: [SnapGuide] = []

        // Keep anchor types consistent to avoid unintuitive matches like left edge -> center line.
        for draggedStop in draggedStops {
            for stop in stops {
                guard stop.anchor == draggedStop.anchor else { continue }

                let delta = stop.value - draggedStop.value
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
        let xStops = [
            DraggedStop(anchor: .leading, value: draggedBounds.minX),
            DraggedStop(anchor: .center, value: draggedBounds.midX),
            DraggedStop(anchor: .trailing, value: draggedBounds.maxX),
        ]
        let yStops = [
            DraggedStop(anchor: .leading, value: draggedBounds.minY),
            DraggedStop(anchor: .center, value: draggedBounds.midY),
            DraggedStop(anchor: .trailing, value: draggedBounds.maxY),
        ]

        let alignmentX = bestAlignmentSnap(
            for: xStops,
            against: stops.vertical,
            axis: .vertical,
            threshold: threshold
        )
        let alignmentY = bestAlignmentSnap(
            for: yStops,
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
