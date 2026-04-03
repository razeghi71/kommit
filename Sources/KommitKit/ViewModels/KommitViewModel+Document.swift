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

    private func decodeBoard(from data: Data) -> DecodedBoard? {
        let decoder = JSONDecoder()
        guard let document = try? decoder.decode(KommitDocument.self, from: data) else { return nil }
        let explicitFileSettings = document.settings?.statusPalette.map { KommitStatusSettings(statusPalette: $0) }
        let baseSettings = explicitFileSettings ?? systemStatusSettings
        let loadedNodes = document.nodes.map { node in
            var n = node
            n.statusID = normalizedStatusID(node.statusID, settings: baseSettings)
            return n
        }
        return DecodedBoard(
            nodes: loadedNodes,
            fileStatusSettings: explicitFileSettings,
            commitments: document.commitments,
            forecasts: document.forecasts,
            financialTransactions: document.financialTransactions,
            financeCalendarStartingBalance: document.financeCalendarStartingBalance,
            preferredCurrencyCode: document.settings?.preferredCurrencyCode
        )
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
