import Foundation

struct KommitStatusDefinition: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String?
}

struct KommitStatusSettings: Codable, Equatable {
    var statusPalette: [KommitStatusDefinition]

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

    init(statusPalette: [KommitStatusDefinition]) {
        self.statusPalette = Self.sanitizedPalette(statusPalette)
    }

    static var defaultValue: KommitStatusSettings {
        KommitStatusSettings(statusPalette: [
            KommitStatusDefinition(id: noneStatusID, name: "None", colorHex: nil),
            KommitStatusDefinition(id: inProgressStatusID, name: "In Progress", colorHex: "F2D600"),
            KommitStatusDefinition(id: doneStatusID, name: "Done", colorHex: "61BD4F"),
        ])
    }

    var noneStatus: KommitStatusDefinition {
        statusPalette.first(where: { $0.id == Self.noneStatusID }) ?? Self.defaultValue.statusPalette[0]
    }

    var selectableStatuses: [KommitStatusDefinition] {
        statusPalette.filter { $0.id != Self.noneStatusID }
    }

    func definition(for id: UUID?) -> KommitStatusDefinition {
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

    private static func sanitizedPalette(_ palette: [KommitStatusDefinition]) -> [KommitStatusDefinition] {
        var unique: [KommitStatusDefinition] = []
        var seen = Set<UUID>()

        let trimmedNoneName =
            palette.first(where: { $0.id == noneStatusID })?
            .name
            .trimmingCharacters(in: .whitespacesAndNewlines)

        unique.append(
            KommitStatusDefinition(
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
                KommitStatusDefinition(
                    id: status.id,
                    name: trimmedName.isEmpty ? "Untitled Status" : trimmedName,
                    colorHex: normalizedColor.isEmpty ? "0079BF" : normalizedColor
                )
            )
        }

        return unique
    }
}

// MARK: - Per-document board settings (JSON `settings` object)

/// Board-level **preferences** saved under JSON `settings` (status palette and currency only).
struct KommitBoardSettings: Equatable {
    /// When set, overrides the app default status palette for this board only.
    var statusPalette: [KommitStatusDefinition]?
    /// ISO 4217 code when this board overrides the app default currency.
    var preferredCurrencyCode: String?

    init(statusPalette: [KommitStatusDefinition]? = nil, preferredCurrencyCode: String? = nil) {
        self.statusPalette = statusPalette
        self.preferredCurrencyCode = preferredCurrencyCode
    }

    var hasAnyValue: Bool {
        statusPalette != nil || preferredCurrencyCode != nil
    }
}

extension KommitBoardSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case statusPalette
        case preferredCurrencyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusPalette = try container.decodeIfPresent([KommitStatusDefinition].self, forKey: .statusPalette)
        preferredCurrencyCode = try container.decodeIfPresent(String.self, forKey: .preferredCurrencyCode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(statusPalette, forKey: .statusPalette)
        try container.encodeIfPresent(preferredCurrencyCode, forKey: .preferredCurrencyCode)
    }
}

struct KommitDocument: Codable {
    var format: Int
    var nodes: [KommitNode]
    var settings: KommitBoardSettings?
    var commitments: [Commitment]?
    var forecasts: [Forecast]?
    var financialTransactions: [FinancialTransaction]?
    /// Document data for the finance calendar (not a board “setting”); omitted when zero.
    var financeCalendarStartingBalance: Double?

    private enum CodingKeys: String, CodingKey {
        case format
        case nodes
        case settings
        case commitments
        case forecasts
        case financialTransactions
        case financeCalendarStartingBalance
    }

    init(
        format: Int = 4,
        nodes: [KommitNode],
        settings: KommitBoardSettings?,
        financeCalendarStartingBalance: Double? = nil,
        commitments: [Commitment]? = nil,
        forecasts: [Forecast]? = nil,
        financialTransactions: [FinancialTransaction]? = nil
    ) {
        self.format = format
        self.nodes = nodes
        self.settings = settings
        self.financeCalendarStartingBalance = financeCalendarStartingBalance
        self.commitments = commitments
        self.forecasts = forecasts
        self.financialTransactions = financialTransactions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Int.self, forKey: .format)
        nodes = try container.decode([KommitNode].self, forKey: .nodes)
        commitments = try container.decodeIfPresent([Commitment].self, forKey: .commitments)
        forecasts = try container.decodeIfPresent([Forecast].self, forKey: .forecasts)
        financialTransactions = try container.decodeIfPresent([FinancialTransaction].self, forKey: .financialTransactions)
        settings = try container.decodeIfPresent(KommitBoardSettings.self, forKey: .settings)
        financeCalendarStartingBalance = try container.decodeIfPresent(Double.self, forKey: .financeCalendarStartingBalance)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(nodes, forKey: .nodes)
        try container.encodeIfPresent(commitments, forKey: .commitments)
        try container.encodeIfPresent(forecasts, forKey: .forecasts)
        try container.encodeIfPresent(financialTransactions, forKey: .financialTransactions)
        if let settings, settings.hasAnyValue {
            try container.encode(settings, forKey: .settings)
        }
        if let balance = financeCalendarStartingBalance, balance != 0 {
            try container.encode(balance, forKey: .financeCalendarStartingBalance)
        }
    }
}
