import AppKit
import SwiftUI

@MainActor
package final class KommitViewModel: ObservableObject {
    @Published var nodes: [UUID: KommitNode] = [:]
    @Published var systemStatusSettings: KommitStatusSettings
    @Published var fileStatusSettings: KommitStatusSettings?
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

    package enum DoneVisibility: CaseIterable {
        case showAll
        case hideChains
        case hideAll
    }
    @Published package var doneVisibility: DoneVisibility = .showAll
    @Published var canvasFocusRequest: NodeFocusRequest?
    @Published var searchPresentationRequest: SearchPresentationRequest?
    @Published var commitments: [UUID: Commitment] = [:]
    @Published var forecasts: [UUID: Forecast] = [:]
    @Published var financialTransactions: [UUID: FinancialTransaction] = [:]
    /// Persisted with the document; drives finance calendar day balances from today onward.
    @Published package var financeCalendarStartingBalance: Double = 0
    /// Incremented to request resetting canvas pan/zoom to the default framing; handled in `CanvasView`.
    @Published private(set) var canvasRecenterToken: UInt64 = 0

    private var lastAppliedCanvasRecenterToken: UInt64 = 0
    let userDefaults = UserDefaults.standard
    private let systemStatusSettingsKey = "kommit.systemStatusSettings"

    static let recentDocumentPathsKey = "kommit.recentDocumentPaths"

    /// Bumped when recent documents change so SwiftUI can refresh lists.
    @Published var recentDocumentsRefreshToken: UInt64 = 0
    /// Set when the user explicitly starts a blank board (⌘N or hub); avoids re-showing the start hub for that empty session.
    @Published var suppressStartHubForEmptyDocument = false

    var undoStack: [[UUID: KommitNode]] = []
    var redoStack: [[UUID: KommitNode]] = []
    private let maxUndoLevels = 50
    package var isDirty = false

    package var canUndo: Bool { !undoStack.isEmpty }
    package var canRedo: Bool { !redoStack.isEmpty }
    var activeStatusSettings: KommitStatusSettings { fileStatusSettings ?? systemStatusSettings }
    var hasFileStatusSettings: Bool { fileStatusSettings != nil }

    /// Set from the main SwiftUI window (`ContentView`). Used where `EnvironmentValues.openWindow` is unavailable.
    var openSettingsWindowAction: (() -> Void)?

    func openSettingsWindow() {
        openSettingsWindowAction?()
    }

    package init() {
        systemStatusSettings = KommitViewModel.loadSystemStatusSettings(from: UserDefaults.standard, key: "kommit.systemStatusSettings")
    }

    package var shouldShowStartHub: Bool {
        currentFileURL == nil && nodes.isEmpty && !suppressStartHubForEmptyDocument
    }

    /// Main window title: file name, `Untitled` for a new board without a path, or `Kommit` on the start hub. Prefix `*` when `isDirty`.
    package var documentWindowTitle: String {
        if shouldShowStartHub {
            return "Kommit"
        }
        let baseName = currentFileURL?.lastPathComponent ?? "Untitled"
        return isDirty ? "*" + baseName : baseName
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

    var sortedNodes: [KommitNode] {
        Array(nodes.values).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var visibleNodes: [KommitNode] {
        let excluded: Set<UUID>
        switch doneVisibility {
        case .showAll: excluded = []
        case .hideChains: excluded = doneChainNodeIDs
        case .hideAll: excluded = doneNodeIDs
        }
        return sortedNodes.filter { node in
            if !excluded.isEmpty, excluded.contains(node.id) { return false }
            return showHiddenItems || !node.isHidden
        }
    }

    private var doneNodeIDs: Set<UUID> {
        Set(nodes.filter { $0.value.statusID == KommitStatusSettings.doneStatusID }.map(\.key))
    }

    private var doneChainNodeIDs: Set<UUID> {
        var neighbors: [UUID: Set<UUID>] = [:]
        for (id, node) in nodes {
            neighbors[id, default: []].formUnion(node.parentIDs)
            for pid in node.parentIDs {
                neighbors[pid, default: []].insert(id)
            }
        }

        var visited = Set<UUID>()
        var result = Set<UUID>()
        for start in nodes.keys {
            if visited.contains(start) { continue }
            var stack = [start]
            var component = Set<UUID>()
            while let v = stack.popLast() {
                if !component.insert(v).inserted { continue }
                for u in neighbors[v] ?? [] where !component.contains(u) {
                    stack.append(u)
                }
            }
            visited.formUnion(component)
            if component.allSatisfy({ nodes[$0]?.statusID == KommitStatusSettings.doneStatusID }) {
                result.formUnion(component)
            }
        }
        return result
    }

    func isNodeVisible(_ id: UUID) -> Bool {
        guard let node = nodes[id] else { return false }
        switch doneVisibility {
        case .hideAll:
            if node.statusID == KommitStatusSettings.doneStatusID { return false }
        case .hideChains:
            if doneChainNodeIDs.contains(id) { return false }
        case .showAll:
            break
        }
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
        let parent: KommitNode
        let child: KommitNode
    }

    var edges: [Edge] {
        let excluded: Set<UUID>
        switch doneVisibility {
        case .showAll: excluded = []
        case .hideChains: excluded = doneChainNodeIDs
        case .hideAll: excluded = doneNodeIDs
        }
        return nodes.values.flatMap { child in
            child.parentIDs.compactMap { parentID in
                guard let parent = nodes[parentID] else { return nil }
                if !showHiddenItems, (child.isHidden || parent.isHidden) {
                    return nil
                }
                if !excluded.isEmpty, excluded.contains(child.id) || excluded.contains(parent.id) {
                    return nil
                }
                return Edge(id: "\(parentID)>\(child.id)", parent: parent, child: child)
            }
        }
    }

    func addNode(at position: CGPoint) {
        saveSnapshot()
        let node = KommitNode(position: position)
        nodes[node.id] = node
        editingNodeID = node.id
    }

    func addChildNode(parentID: UUID, direction: DragDirection, at dropPoint: CGPoint? = nil) {
        guard let parent = nodes[parentID] else { return }
        saveSnapshot()

        let offset: CGFloat = 180
        let position: CGPoint
        if let dropPoint {
            let halfW = NodeDefaults.size.width / 2
            let halfH = NodeDefaults.size.height / 2
            switch direction {
            case .top:
                // Pointer indicates the new node's bottom edge.
                position = CGPoint(x: dropPoint.x, y: dropPoint.y - halfH)
            case .bottom:
                // Pointer indicates the new node's top edge.
                position = CGPoint(x: dropPoint.x, y: dropPoint.y + halfH)
            case .left:
                // Pointer indicates the new node's right edge.
                position = CGPoint(x: dropPoint.x - halfW, y: dropPoint.y)
            case .right:
                // Pointer indicates the new node's left edge.
                position = CGPoint(x: dropPoint.x + halfW, y: dropPoint.y)
            }
        } else {
            switch direction {
            case .top: position = CGPoint(x: parent.position.x, y: parent.position.y - offset)
            case .bottom: position = CGPoint(x: parent.position.x, y: parent.position.y + offset)
            case .left: position = CGPoint(x: parent.position.x - offset, y: parent.position.y)
            case .right: position = CGPoint(x: parent.position.x + offset, y: parent.position.y)
            }
        }

        let child = KommitNode(position: position, parentIDs: [parentID])
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

    package func setDoneVisibility(_ visibility: DoneVisibility) {
        doneVisibility = visibility
        pruneSelectionForDoneChains()
    }

    func statusDefinition(for statusID: UUID?) -> KommitStatusDefinition {
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
                KommitStatusDefinition(
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
        guard id != KommitStatusSettings.noneStatusID else { return }
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
        id != KommitStatusSettings.noneStatusID
    }

    private func mutateStatusSettings(forFileSettings: Bool, update: (inout KommitStatusSettings) -> Void) {
        var settings = forFileSettings ? (fileStatusSettings ?? systemStatusSettings) : systemStatusSettings
        update(&settings)
        settings = KommitStatusSettings(statusPalette: settings.statusPalette)

        if forFileSettings {
            fileStatusSettings = settings
            isDirty = true
        } else {
            systemStatusSettings = settings
            persistSystemStatusSettings()
        }

        clearInvalidNodeStatusesForActiveSettings()
    }

    func normalizedStatusID(_ statusID: UUID?, settings: KommitStatusSettings) -> UUID? {
        guard let statusID else { return nil }
        guard statusID != KommitStatusSettings.noneStatusID else { return nil }
        return settings.containsStatus(statusID) ? statusID : nil
    }

    private func clearInvalidNodeStatusesForActiveSettings() {
        let validIDs = Set(activeStatusSettings.statusPalette.map(\.id))
        for id in nodes.keys {
            guard let statusID = nodes[id]?.statusID else {
                nodes[id]?.legacyColorHex = nil
                continue
            }
            if !validIDs.contains(statusID) || statusID == KommitStatusSettings.noneStatusID {
                nodes[id]?.statusID = nil
            }
            nodes[id]?.legacyColorHex = nil
        }
    }

    private static func loadSystemStatusSettings(from defaults: UserDefaults, key: String) -> KommitStatusSettings {
        guard let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(KommitStatusSettings.self, from: data)
        else {
            return .defaultValue
        }
        return decoded
    }

    private func persistSystemStatusSettings() {
        guard let data = try? JSONEncoder().encode(systemStatusSettings) else { return }
        userDefaults.set(data, forKey: systemStatusSettingsKey)
    }


    func updateNodeText(_ id: UUID, text: String) {
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

    private func pruneSelectionForDoneChains() {
        let excluded: Set<UUID>
        switch doneVisibility {
        case .showAll: return
        case .hideChains: excluded = doneChainNodeIDs
        case .hideAll: excluded = doneNodeIDs
        }
        guard !excluded.isEmpty else { return }

        selectedNodeIDs = selectedNodeIDs.filter { !excluded.contains($0) }
        if let selectedNodeID, excluded.contains(selectedNodeID) {
            self.selectedNodeID = selectedNodeIDs.first
        }

        if let edgeID = selectedEdgeID {
            let parts = edgeID.split(separator: ">")
            if parts.count == 2,
                let parentID = UUID(uuidString: String(parts[0])),
                let childID = UUID(uuidString: String(parts[1]))
            {
                if excluded.contains(parentID) || excluded.contains(childID) {
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


}
