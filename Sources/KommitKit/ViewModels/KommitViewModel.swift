import AppKit
import SwiftUI

@MainActor
package final class KommitViewModel: ObservableObject {
    enum StatusSettingsScope: String, CaseIterable, Identifiable {
        case file
        case system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .file: "Current Board"
            case .system: "System Defaults"
            }
        }
    }

    struct StatusSettingsImpact {
        let affectedNodeCount: Int
        let sampleNodeNames: [String]

        static let none = StatusSettingsImpact(affectedNodeCount: 0, sampleNodeNames: [])
    }

    @Published var nodes: [UUID: KommitNode] = [:]
    @Published var systemStatusSettings: KommitStatusSettings
    @Published var fileStatusSettings: KommitStatusSettings?
    /// App-wide default ISO 4217 currency; boards without an override use this.
    @Published var systemPreferredCurrencyCode: String
    /// When set, the open board shows amounts in this currency and the value is saved in the document.
    @Published var filePreferredCurrencyCode: String?
    @Published package var editingNodeID: UUID?
    @Published package var selectedNodeID: UUID?
    @Published package var selectedNodeIDs: Set<UUID> = []
    @Published var edgeDrag: EdgeDragState?
    @Published var dropTargetNodeID: UUID?
    @Published package var selectedEdgeID: String?
    @Published var currentFileURL: URL?
    @Published var fileLoadID: UUID = UUID()
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
    /// Persisted with the document; calendar starting balance is the sum of `balance` for each account.
    @Published package var financeAccounts: [FinanceAccount] = []

    /// Combined balance passed into `FinanceCalendarProjection` as today’s starting point.
    package var financeCalendarTotalBalance: Double {
        financeAccounts.reduce(0) { $0 + $1.balance }
    }

    /// Incremented to request resetting canvas pan/zoom to the default framing; handled in `CanvasView`.
    @Published private(set) var canvasRecenterToken: UInt64 = 0
    /// Transient layout measurements from `NodeView`; used for rendering/hit-testing without mutating document data.
    @Published private(set) var measuredNodeSizes: [UUID: CGSize] = [:]

    private var lastAppliedCanvasRecenterToken: UInt64 = 0
    let userDefaults = UserDefaults.standard
    private let systemStatusSettingsKey = "kommit.systemStatusSettings"
    private let systemPreferredCurrencyKey = "kommit.systemPreferredCurrencyCode"

    private var financialCurrencyFormatterCacheCode: String?
    private var financialCurrencyFormatterInstance: NumberFormatter?

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
    var effectiveStatusSettingsScope: StatusSettingsScope { hasFileStatusSettings ? .file : .system }
    var hasFileStatusSettings: Bool { fileStatusSettings != nil }
    package var hasFileCurrencyOverride: Bool { filePreferredCurrencyCode != nil }
    package var hasOpenBoardContext: Bool { !shouldShowStartHub }

    package var effectiveFinancialCurrencyCode: String {
        if let file = filePreferredCurrencyCode {
            return file
        }
        return systemPreferredCurrencyCode
    }

    package var effectiveFinancialCurrencySymbol: String {
        let formatter = financialCurrencyFormatter()
        if let symbol = formatter.currencySymbol, !symbol.isEmpty {
            return symbol
        }
        return formatter.internationalCurrencySymbol ?? effectiveFinancialCurrencyCode
    }

    /// Set from the main SwiftUI window (`ContentView`). Used where `EnvironmentValues.openWindow` is unavailable.
    var openSettingsWindowAction: (() -> Void)?

    func openSettingsWindow() {
        openSettingsWindowAction?()
    }

    package init() {
        systemStatusSettings = KommitViewModel.loadSystemStatusSettings(from: UserDefaults.standard, key: "kommit.systemStatusSettings")
        systemPreferredCurrencyCode = KommitViewModel.loadSystemPreferredCurrencyCode(from: UserDefaults.standard, key: systemPreferredCurrencyKey)
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
        clearMeasuredNodeSizeCache()
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
    }

    package func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(nodes)
        nodes = snapshot
        clearMeasuredNodeSizeCache()
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
        let (x, y) = CanvasIntegerGeometry.topLeftCentered(
            at: position,
            width: NodeDefaults.width,
            height: NodeDefaults.height
        )
        let node = KommitNode(x: x, y: y)
        nodes[node.id] = node
        beginEditing(nodeID: node.id, recordUndoSnapshot: false)
    }

    func addChildNode(parentID: UUID, direction: DragDirection, at dropPoint: CGPoint? = nil) {
        guard let parent = nodes[parentID] else { return }
        saveSnapshot()

        let cw = NodeDefaults.width
        let ch = NodeDefaults.height
        let parentCenter = effectiveNodeCenter(for: parentID) ?? parent.center
        let pcx = parentCenter.x
        let pcy = parentCenter.y
        let offset: CGFloat = 180
        let halfWCg = CGFloat(cw) / 2
        let halfHCg = CGFloat(ch) / 2

        let (childX, childY): (Int, Int)
        if let dropPoint {
            let center: CGPoint
            switch direction {
            case .top:
                center = CGPoint(x: dropPoint.x, y: dropPoint.y - halfHCg)
            case .bottom:
                center = CGPoint(x: dropPoint.x, y: dropPoint.y + halfHCg)
            case .left:
                center = CGPoint(x: dropPoint.x - halfWCg, y: dropPoint.y)
            case .right:
                center = CGPoint(x: dropPoint.x + halfWCg, y: dropPoint.y)
            }
            childX = Int((Double(center.x) - Double(cw) / 2).rounded())
            childY = Int((Double(center.y) - Double(ch) / 2).rounded())
        } else {
            let center: CGPoint
            switch direction {
            case .top: center = CGPoint(x: pcx, y: pcy - offset)
            case .bottom: center = CGPoint(x: pcx, y: pcy + offset)
            case .left: center = CGPoint(x: pcx - offset, y: pcy)
            case .right: center = CGPoint(x: pcx + offset, y: pcy)
            }
            childX = Int((Double(center.x) - Double(cw) / 2).rounded())
            childY = Int((Double(center.y) - Double(ch) / 2).rounded())
        }

        let child = KommitNode(x: childX, y: childY, width: cw, height: ch, parentIDs: [parentID])
        nodes[child.id] = child
        beginEditing(nodeID: child.id, recordUndoSnapshot: false)
    }

    func moveNode(_ id: UUID, x: Int, y: Int) {
        saveSnapshot()
        nodes[id]?.x = x
        nodes[id]?.y = y
    }

    /// Updates transient integer size from laid-out bounds.
    ///
    /// This cache is intentionally view-only. Layout measurement should drive rendering, hit-testing, and snapping,
    /// but it must not reposition nodes or mark the document dirty.
    func updateNodeMeasuredFrame(id: UUID, size: CGSize) {
        guard nodes[id] != nil else { return }
        let nw = max(NodeDefaults.minWidth, Int(size.width.rounded(.up)))
        let nh = max(1, Int(size.height.rounded(.up)))
        let measured = CGSize(width: CGFloat(nw), height: CGFloat(nh))
        guard measuredNodeSizes[id] != measured else { return }
        measuredNodeSizes[id] = measured
    }

    func effectiveNodeSize(for id: UUID) -> CGSize {
        if let measured = measuredNodeSizes[id] {
            return measured
        }
        guard let node = nodes[id] else { return .zero }
        return CGSize(width: CGFloat(node.width), height: CGFloat(node.height))
    }

    func effectiveNodeRect(for id: UUID) -> CGRect? {
        guard let node = nodes[id] else { return nil }
        let size = effectiveNodeSize(for: id)
        return CGRect(x: CGFloat(node.x), y: CGFloat(node.y), width: size.width, height: size.height)
    }

    func effectiveNodeCenter(for id: UUID) -> CGPoint? {
        guard let rect = effectiveNodeRect(for: id) else { return nil }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func clearMeasuredNodeSizeCache() {
        guard !measuredNodeSizes.isEmpty else { return }
        measuredNodeSizes.removeAll()
    }

    func setNodeStatus(_ id: UUID, statusID: UUID?) {
        saveSnapshot()
        nodes[id]?.statusID = normalizedStatusID(statusID, settings: activeStatusSettings)
    }

    func setNodeStatuses(_ ids: Set<UUID>, statusID: UUID?) {
        guard !ids.isEmpty else { return }
        saveSnapshot()
        for id in ids {
            nodes[id]?.statusID = normalizedStatusID(statusID, settings: activeStatusSettings)
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

    /// Aligns every node in `ids` to the same edge or axis-center as the selection’s bounding box (integer frames).
    func alignNodes(_ ids: Set<UUID>, alignment: NodeAlignment) {
        guard ids.count >= 2 else { return }
        let targets = ids.filter { nodes[$0] != nil }
        guard targets.count >= 2 else { return }

        var rects: [(UUID, CGRect)] = []
        rects.reserveCapacity(targets.count)
        for id in targets {
            guard let rect = effectiveNodeRect(for: id) else { continue }
            rects.append((id, rect))
        }
        guard rects.count >= 2 else { return }

        saveSnapshot()

        switch alignment {
        case .left:
            let ref = Int(rects.map(\.1.minX).min()!.rounded())
            for (id, _) in rects {
                nodes[id]?.x = ref
            }
        case .right:
            let ref = Int(rects.map(\.1.maxX).max()!.rounded())
            for (id, _) in rects {
                let w = Int(effectiveNodeSize(for: id).width.rounded())
                nodes[id]?.x = ref - w
            }
        case .top:
            let ref = Int(rects.map(\.1.minY).min()!.rounded())
            for (id, _) in rects {
                nodes[id]?.y = ref
            }
        case .bottom:
            let ref = Int(rects.map(\.1.maxY).max()!.rounded())
            for (id, _) in rects {
                let h = Int(effectiveNodeSize(for: id).height.rounded())
                nodes[id]?.y = ref - h
            }
        case .horizontalCenter:
            let minX = rects.map(\.1.minX).min()!
            let maxX = rects.map(\.1.maxX).max()!
            let refX = (minX + maxX) / 2
            for (id, _) in rects {
                let w = effectiveNodeSize(for: id).width
                nodes[id]?.x = Int((Double(refX) - Double(w) / 2).rounded())
            }
        case .verticalCenter:
            let minY = rects.map(\.1.minY).min()!
            let maxY = rects.map(\.1.maxY).max()!
            let refY = (minY + maxY) / 2
            for (id, _) in rects {
                let h = effectiveNodeSize(for: id).height
                nodes[id]?.y = Int((Double(refY) - Double(h) / 2).rounded())
            }
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
        guard hasOpenBoardContext, fileStatusSettings == nil else { return }
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

    func statusSettings(for scope: StatusSettingsScope) -> KommitStatusSettings? {
        switch scope {
        case .file:
            fileStatusSettings
        case .system:
            systemStatusSettings
        }
    }

    func resolvedStatusSettings(for scope: StatusSettingsScope) -> KommitStatusSettings {
        switch scope {
        case .file:
            fileStatusSettings ?? systemStatusSettings
        case .system:
            systemStatusSettings
        }
    }

    func addStatus(in scope: StatusSettingsScope) {
        addStatus(forFileSettings: scope == .file)
    }

    func updateStatusName(_ id: UUID, name: String, in scope: StatusSettingsScope) {
        updateStatusName(id, name: name, forFileSettings: scope == .file)
    }

    func updateStatusColor(_ id: UUID, colorHex: String, in scope: StatusSettingsScope) {
        updateStatusColor(id, colorHex: colorHex, forFileSettings: scope == .file)
    }

    func removeStatus(_ id: UUID, from scope: StatusSettingsScope) {
        removeStatus(id, forFileSettings: scope == .file)
    }

    func nodeCount(usingStatus id: UUID, in scope: StatusSettingsScope) -> Int {
        guard scope == effectiveStatusSettingsScope else { return 0 }
        return nodes.values.reduce(into: 0) { partialResult, node in
            if node.statusID == id {
                partialResult += 1
            }
        }
    }

    func removalImpact(forStatus id: UUID, from scope: StatusSettingsScope, sampleLimit: Int = 3) -> StatusSettingsImpact {
        guard scope == effectiveStatusSettingsScope else { return .none }
        let affectedNodes = nodes.values.filter { $0.statusID == id }
        return StatusSettingsImpact(
            affectedNodeCount: affectedNodes.count,
            sampleNodeNames: Array(affectedNodes.prefix(sampleLimit).map(Self.displayName(for:)))
        )
    }

    func revertToSystemDefaultsImpact(sampleLimit: Int = 3) -> StatusSettingsImpact {
        guard fileStatusSettings != nil else { return .none }
        let validIDs = Set(systemStatusSettings.statusPalette.map(\.id))
        let affectedNodes = nodes.values.filter { node in
            guard let statusID = node.statusID else { return false }
            return !validIDs.contains(statusID) || statusID == KommitStatusSettings.noneStatusID
        }
        return StatusSettingsImpact(
            affectedNodeCount: affectedNodes.count,
            sampleNodeNames: Array(affectedNodes.prefix(sampleLimit).map(Self.displayName(for:)))
        )
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
                continue
            }
            if !validIDs.contains(statusID) || statusID == KommitStatusSettings.noneStatusID {
                nodes[id]?.statusID = nil
            }
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

    private static func loadSystemPreferredCurrencyCode(from defaults: UserDefaults, key: String) -> String {
        if let stored = defaults.string(forKey: key) {
            return FinancialCurrencyFormatting.normalizedISOCurrencyCode(stored)
        }
        return FinancialCurrencyFormatting.defaultCodeForCurrentLocale()
    }

    private func persistSystemPreferredCurrencyCode() {
        userDefaults.set(systemPreferredCurrencyCode, forKey: systemPreferredCurrencyKey)
    }

    private func invalidateFinancialCurrencyFormatterCache() {
        financialCurrencyFormatterCacheCode = nil
        financialCurrencyFormatterInstance = nil
    }

    private func financialCurrencyFormatter() -> NumberFormatter {
        let code = effectiveFinancialCurrencyCode
        if financialCurrencyFormatterCacheCode == code, let cached = financialCurrencyFormatterInstance {
            return cached
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = .current
        formatter.currencySymbol = FinancialCurrencyFormatting.displaySymbol(for: code, locale: formatter.locale)
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        financialCurrencyFormatterCacheCode = code
        financialCurrencyFormatterInstance = formatter
        return formatter
    }

    package func formatFinancialCurrency(_ amount: Double) -> String {
        financialCurrencyFormatter().string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    package func formatFinancialCurrencyUnsigned(_ magnitude: Double) -> String {
        let value = abs(magnitude)
        return financialCurrencyFormatter().string(from: NSNumber(value: value)) ?? "\(value)"
    }

    package func updateSystemPreferredCurrencyCode(_ code: String) {
        let normalized = FinancialCurrencyFormatting.normalizedISOCurrencyCode(code)
        guard normalized != systemPreferredCurrencyCode else { return }
        systemPreferredCurrencyCode = normalized
        invalidateFinancialCurrencyFormatterCache()
        persistSystemPreferredCurrencyCode()
    }

    package func updateFilePreferredCurrencyCode(_ code: String) {
        guard filePreferredCurrencyCode != nil else { return }
        let normalized = FinancialCurrencyFormatting.normalizedISOCurrencyCode(code)
        guard normalized != filePreferredCurrencyCode else { return }
        filePreferredCurrencyCode = normalized
        invalidateFinancialCurrencyFormatterCache()
        isDirty = true
    }

    package func addFileCurrencyOverride() {
        guard hasOpenBoardContext, filePreferredCurrencyCode == nil else { return }
        filePreferredCurrencyCode = systemPreferredCurrencyCode
        invalidateFinancialCurrencyFormatterCache()
        isDirty = true
    }

    package func removeFileCurrencyOverride() {
        guard filePreferredCurrencyCode != nil else { return }
        filePreferredCurrencyCode = nil
        invalidateFinancialCurrencyFormatterCache()
        isDirty = true
    }

    private static func displayName(for node: KommitNode) -> String {
        let trimmed = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Task" : trimmed
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
        measuredNodeSizes.removeValue(forKey: id)
        if editingNodeID == id {
            editingNodeID = nil
        }
    }

    func beginEditing(nodeID: UUID, recordUndoSnapshot: Bool = true) {
        if recordUndoSnapshot {
            saveSnapshot()
        }
        editingNodeID = nodeID
    }

    func commitEditing() {
        editingNodeID = nil
    }

    /// Find a node at the given canvas point (excluding a specific node)
    func nodeAt(point: CGPoint, excluding: UUID) -> UUID? {
        for id in nodes.keys where id != excluding && isNodeVisible(id) {
            guard let rect = effectiveNodeRect(for: id) else { continue }
            if rect.contains(point) {
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
            let nodeRect = effectiveNodeRect(for: id) ?? CGRect(
                x: CGFloat(node.x),
                y: CGFloat(node.y),
                width: CGFloat(node.width),
                height: CGFloat(node.height)
            )
            if rect.intersects(nodeRect) {
                ids.insert(id)
            }
        }
        selectedNodeIDs = ids
        selectedNodeID = ids.first
    }

    /// Selects every node currently visible on the canvas (Tasks view), matching marquee / filter rules.
    func selectAllVisibleNodes() {
        commitEditing()
        let ids = Set(visibleNodes.map(\.id))
        guard !ids.isEmpty else {
            clearSelection()
            return
        }
        selectedNodeIDs = ids
        selectedNodeID = ids.first
        selectedEdgeID = nil
    }

    func commitNodesMove(_ ids: Set<UUID>, by offset: CGSize) {
        guard !ids.isEmpty else { return }
        saveSnapshot()
        for id in ids {
            guard let node = nodes[id] else { continue }
            let (nx, ny) = CanvasIntegerGeometry.snappedOrigin(nodeX: node.x, nodeY: node.y, translation: offset)
            nodes[id]?.x = nx
            nodes[id]?.y = ny
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
