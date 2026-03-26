import Foundation

struct DominoStatusDefinition: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String?
}

struct DominoStatusSettings: Codable, Equatable {
    var statusPalette: [DominoStatusDefinition]

    static let noneStatusID = UUID(uuidString: "A0000001-0000-4000-8000-000000000000")!
    static let inProgressStatusID = UUID(uuidString: "A0000001-0000-4000-8000-000000000001")!
    static let doneStatusID = UUID(uuidString: "A0000001-0000-4000-8000-000000000002")!

    private static let defaultExtraColors = [
        "FF9F1A",
        "EB5A46",
        "0079BF",
        "FF2F92",
        "8B5CF6",
        "14B8A6",
    ]

    init(statusPalette: [DominoStatusDefinition]) {
        self.statusPalette = Self.sanitizedPalette(statusPalette)
    }

    static var defaultValue: DominoStatusSettings {
        DominoStatusSettings(statusPalette: [
            DominoStatusDefinition(id: noneStatusID, name: "None", colorHex: nil),
            DominoStatusDefinition(id: inProgressStatusID, name: "In Progress", colorHex: "F2D600"),
            DominoStatusDefinition(id: doneStatusID, name: "Done", colorHex: "61BD4F"),
        ])
    }

    var noneStatus: DominoStatusDefinition {
        statusPalette.first(where: { $0.id == Self.noneStatusID }) ?? Self.defaultValue.statusPalette[0]
    }

    var selectableStatuses: [DominoStatusDefinition] {
        statusPalette.filter { $0.id != Self.noneStatusID }
    }

    func definition(for id: UUID?) -> DominoStatusDefinition {
        guard let id else { return noneStatus }
        return statusPalette.first(where: { $0.id == id }) ?? noneStatus
    }

    func containsStatus(_ id: UUID?) -> Bool {
        guard let id else { return true }
        return statusPalette.contains(where: { $0.id == id })
    }

    func matchingStatusID(forLegacyColorHex hex: String) -> UUID? {
        let normalized = Self.normalizedHex(hex)
        return selectableStatuses.first(where: {
            Self.normalizedHex($0.colorHex) == normalized
        })?.id
    }

    func nextStatusName() -> String {
        let existing = Set(statusPalette.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var index = 1
        while existing.contains("status \(index)") {
            index += 1
        }
        return "Status \(index)"
    }

    func nextStatusColorHex() -> String {
        let used = Set(selectableStatuses.compactMap(\.colorHex).map(Self.normalizedHex))
        if let unused = Self.defaultExtraColors.first(where: { !used.contains(Self.normalizedHex($0)) }) {
            return unused
        }
        return Self.defaultExtraColors.first ?? "0079BF"
    }

    static func normalizedHex(_ hex: String?) -> String {
        guard let hex else { return "" }
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("#") {
            value.removeFirst()
        }
        return value.uppercased()
    }

    static func legacyFallbackName(for hex: String) -> String {
        switch normalizedHex(hex) {
        case normalizedHex(defaultValue.statusPalette[1].colorHex): return defaultValue.statusPalette[1].name
        case normalizedHex(defaultValue.statusPalette[2].colorHex): return defaultValue.statusPalette[2].name
        case "FF9F1A": return "Orange"
        case "EB5A46": return "Red"
        case "0079BF": return "Blue"
        case "FF2F92": return "Pink"
        default:
            let prefix = String(normalizedHex(hex).prefix(6))
            return prefix.isEmpty ? "Custom Status" : "Status \(prefix)"
        }
    }

    private static func sanitizedPalette(_ palette: [DominoStatusDefinition]) -> [DominoStatusDefinition] {
        var unique: [DominoStatusDefinition] = []
        var seen = Set<UUID>()

        let trimmedNoneName =
            palette.first(where: { $0.id == noneStatusID })?
            .name
            .trimmingCharacters(in: .whitespacesAndNewlines)

        unique.append(
            DominoStatusDefinition(
                id: noneStatusID,
                name: trimmedNoneName?.isEmpty == false ? trimmedNoneName! : "None",
                colorHex: nil
            )
        )
        seen.insert(noneStatusID)

        for status in palette where !seen.contains(status.id) && status.id != noneStatusID {
            seen.insert(status.id)
            let trimmedName = status.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedColor = normalizedHex(status.colorHex)
            unique.append(
                DominoStatusDefinition(
                    id: status.id,
                    name: trimmedName.isEmpty ? "Untitled Status" : trimmedName,
                    colorHex: normalizedColor.isEmpty ? "0079BF" : normalizedColor
                )
            )
        }

        return unique
    }
}

struct DominoDocument: Codable {
    var format: Int
    var nodes: [DominoNode]
    var settings: DominoStatusSettings?
    var commitments: [Commitment]?
    var forecasts: [Forecast]?
    var financialTransactions: [FinancialTransaction]?

    init(
        format: Int = 4,
        nodes: [DominoNode],
        settings: DominoStatusSettings?,
        commitments: [Commitment]? = nil,
        forecasts: [Forecast]? = nil,
        financialTransactions: [FinancialTransaction]? = nil
    ) {
        self.format = format
        self.nodes = nodes
        self.settings = settings
        self.commitments = commitments
        self.forecasts = forecasts
        self.financialTransactions = financialTransactions
    }
}
