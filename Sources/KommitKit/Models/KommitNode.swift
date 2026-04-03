import Foundation

enum NodeDefaults {
    static let size = CGSize(width: 132, height: 44)
}

struct KommitNode: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    var position: CGPoint
    var parentIDs: Set<UUID>
    var statusID: UUID?
    var plannedDate: Date?
    var budget: Double?
    var isHidden: Bool

    init(
        id: UUID = UUID(),
        text: String = "",
        position: CGPoint,
        parentIDs: Set<UUID> = [],
        statusID: UUID? = nil,
        plannedDate: Date? = nil,
        budget: Double? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.text = text
        self.position = position
        self.parentIDs = parentIDs
        self.statusID = statusID
        self.plannedDate = plannedDate
        self.budget = budget
        self.isHidden = isHidden
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case position
        case parentIDs
        case statusID
        case plannedDate
        case budget
        case isHidden
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        position = try container.decode(CGPoint.self, forKey: .position)
        parentIDs = try container.decode(Set<UUID>.self, forKey: .parentIDs)
        statusID = try container.decodeIfPresent(UUID.self, forKey: .statusID)
        plannedDate = try container.decodeIfPresent(Date.self, forKey: .plannedDate)
        budget = try container.decodeIfPresent(Double.self, forKey: .budget)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(position, forKey: .position)
        try container.encode(parentIDs, forKey: .parentIDs)
        try container.encodeIfPresent(statusID, forKey: .statusID)
        try container.encodeIfPresent(plannedDate, forKey: .plannedDate)
        try container.encodeIfPresent(budget, forKey: .budget)
        try container.encode(isHidden, forKey: .isHidden)
    }
}
