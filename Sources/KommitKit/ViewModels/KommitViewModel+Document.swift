import AppKit
import Foundation

@MainActor
extension KommitViewModel {
    /// Clears the document and resets the suppress flag so the start hub shows.
    package func resetToStartHub() {
        nodes.removeAll()
        commitments.removeAll()
        forecasts.removeAll()
        financialTransactions.removeAll()
        financeCalendarStartingBalance = 0
        fileStatusSettings = nil
        filePreferredCurrencyCode = nil
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
        currentFileURL = nil
        undoStack.removeAll()
        redoStack.removeAll()
        isDirty = false
        fileLoadID = UUID()
        suppressStartHubForEmptyDocument = false
    }

    /// Recent Kommit JSON files that still exist on disk (stale paths are removed from storage).
    package func recentDocumentURLs() -> [URL] {
        let paths = userDefaults.stringArray(forKey: Self.recentDocumentPathsKey) ?? []
        let valid = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if valid.count != paths.count {
            userDefaults.set(valid, forKey: Self.recentDocumentPathsKey)
        }
        return valid.map { URL(fileURLWithPath: $0) }
    }

    private func recordDocumentURL(_ url: URL) {
        let path = url.path
        var paths = userDefaults.stringArray(forKey: Self.recentDocumentPathsKey) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > 10 {
            paths = Array(paths.prefix(10))
        }
        userDefaults.set(paths, forKey: Self.recentDocumentPathsKey)
        recentDocumentsRefreshToken &+= 1
    }
    private struct DecodedBoard {
        let nodes: [KommitNode]
        let fileStatusSettings: KommitStatusSettings?
        let commitments: [Commitment]?
        let forecasts: [Forecast]?
        let financialTransactions: [FinancialTransaction]?
        let financeCalendarStartingBalance: Double?
        let preferredCurrencyCode: String?
    }

    private struct MigratedNodes {
        let nodes: [KommitNode]
        let fileStatusSettings: KommitStatusSettings?
    }

    private func decodeBoard(from data: Data) -> DecodedBoard? {
        let decoder = JSONDecoder()

        if let document = try? decoder.decode(KommitDocument.self, from: data) {
            let explicitFileSettings = document.settings?.statusPalette.map { KommitStatusSettings(statusPalette: $0) }
            let migrated = migrateLoadedNodes(document.nodes, baseSettings: explicitFileSettings ?? systemStatusSettings)
            return DecodedBoard(
                nodes: migrated.nodes,
                fileStatusSettings: migrated.fileStatusSettings ?? explicitFileSettings,
                commitments: document.commitments,
                forecasts: document.forecasts,
                financialTransactions: document.financialTransactions,
                financeCalendarStartingBalance: document.financeCalendarStartingBalance,
                preferredCurrencyCode: document.settings?.preferredCurrencyCode
            )
        }

        guard let legacyNodes = try? decoder.decode([KommitNode].self, from: data) else { return nil }
        let migrated = migrateLoadedNodes(legacyNodes, baseSettings: systemStatusSettings)
        return DecodedBoard(
            nodes: migrated.nodes,
            fileStatusSettings: migrated.fileStatusSettings,
            commitments: nil,
            forecasts: nil,
            financialTransactions: nil,
            financeCalendarStartingBalance: nil,
            preferredCurrencyCode: nil
        )
    }

    private func migrateLoadedNodes(_ loadedNodes: [KommitNode], baseSettings: KommitStatusSettings) -> MigratedNodes {
        var migratedNodes: [KommitNode] = []
        migratedNodes.reserveCapacity(loadedNodes.count)

        var resolvedSettings = baseSettings
        var customStatusesByHex: [String: UUID] = [:]
        var createdFileSettings = false

        for node in loadedNodes {
            var updated = node
            let legacyHex = KommitStatusSettings.normalizedHex(node.legacyColorHex)

            if !legacyHex.isEmpty {
                if let existingStatusID = resolvedSettings.matchingStatusID(forLegacyColorHex: legacyHex) {
                    updated.statusID = normalizedStatusID(existingStatusID, settings: resolvedSettings)
                } else {
                    if let reusedStatusID = customStatusesByHex[legacyHex] {
                        updated.statusID = reusedStatusID
                    } else {
                        createdFileSettings = true
                        let newStatus = KommitStatusDefinition(
                            id: UUID(),
                            name: makeUniqueStatusName(
                                baseName: KommitStatusSettings.legacyFallbackName(for: legacyHex),
                                existingSettings: resolvedSettings
                            ),
                            colorHex: legacyHex
                        )
                        resolvedSettings.statusPalette.append(newStatus)
                        resolvedSettings = KommitStatusSettings(statusPalette: resolvedSettings.statusPalette)
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

    private func makeUniqueStatusName(baseName: String, existingSettings: KommitStatusSettings) -> String {
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
    // MARK: - Unsaved changes guard

    package func confirmDiscardIfNeeded(then action: @escaping () -> Void) {
        guard isDirty else {
            action()
            return
        }
        if Self.showDiscardConfirmation(
            informativeText: Self.documentDiscardInformativeText
        ) {
            action()
        }
    }

    package static let documentDiscardInformativeText =
        "This will discard unsaved changes to your task board, finances, and any other data in this document."

    /// Shows a Discard / Cancel alert. Used for document-level and in-sheet draft confirmation.
    package static func showDiscardConfirmation(
        messageText: String = "You have unsaved changes",
        informativeText: String
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - New / Save / Open

    package func newBoard(suppressStartHub: Bool = false) {
        nodes.removeAll()
        commitments.removeAll()
        forecasts.removeAll()
        financialTransactions.removeAll()
        financeCalendarStartingBalance = 0
        fileStatusSettings = nil
        filePreferredCurrencyCode = nil
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
        currentFileURL = nil
        undoStack.removeAll()
        redoStack.removeAll()
        isDirty = false
        fileLoadID = UUID()
        if suppressStartHub {
            suppressStartHubForEmptyDocument = true
        }
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
        panel.nameFieldStringValue = "Kommit.json"
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
        let commitmentList = commitments.values.isEmpty ? nil : Array(commitments.values)
        let forecastList = forecasts.values.isEmpty ? nil : Array(forecasts.values)
        let transactions = financialTransactions.values.isEmpty ? nil : Array(financialTransactions.values)
        let statusPalette: [KommitStatusDefinition]? = {
            guard let file = fileStatusSettings else { return nil }
            return file == systemStatusSettings ? nil : file.statusPalette
        }()
        let boardSettings = KommitBoardSettings(
            statusPalette: statusPalette,
            preferredCurrencyCode: filePreferredCurrencyCode
        )
        let document = KommitDocument(
            nodes: sortedNodes,
            settings: boardSettings.hasAnyValue ? boardSettings : nil,
            financeCalendarStartingBalance: financeCalendarStartingBalance == 0 ? nil : financeCalendarStartingBalance,
            commitments: commitmentList,
            forecasts: forecastList,
            financialTransactions: transactions
        )
        guard let data = try? encoder.encode(document) else { return }
        do {
            try data.write(to: url)
            isDirty = false
            recordDocumentURL(url)
        } catch {
            // Keep isDirty true so the user can retry save elsewhere.
        }
    }

    @discardableResult
    package func openDocument(at url: URL) -> Bool {
        readFromFile(url)
    }

    @discardableResult
    private func readFromFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
            let loaded = decodeBoard(from: data)
        else { return false }
        nodes = Dictionary(uniqueKeysWithValues: loaded.nodes.map { ($0.id, $0) })
        commitments = Dictionary(uniqueKeysWithValues: (loaded.commitments ?? []).map { ($0.id, $0) })
        forecasts = Dictionary(uniqueKeysWithValues: (loaded.forecasts ?? []).map { ($0.id, $0) })
        financialTransactions = Dictionary(uniqueKeysWithValues: (loaded.financialTransactions ?? []).map { ($0.id, $0) })
        backfillTransactionTagsFromPlanningItemsIfNeeded()
        financeCalendarStartingBalance = loaded.financeCalendarStartingBalance ?? 0
        fileStatusSettings = loaded.fileStatusSettings
        if let rawCurrency = loaded.preferredCurrencyCode {
            filePreferredCurrencyCode = FinancialCurrencyFormatting.normalizedISOCurrencyCode(rawCurrency)
        } else {
            filePreferredCurrencyCode = nil
        }
        editingNodeID = nil
        selectedNodeID = nil
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
        currentFileURL = url
        isDirty = false
        fileLoadID = UUID()
        recordDocumentURL(url)
        return true
    }

}
