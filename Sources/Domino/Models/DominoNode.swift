import Foundation

enum NodeDefaults {
    static let size = CGSize(width: 132, height: 44)
}

struct DominoNode: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    var position: CGPoint
    var parentIDs: Set<UUID>
    var colorHex: String?
    var plannedDate: Date?
    var isHidden: Bool

    init(
        id: UUID = UUID(),
        text: String = "",
        position: CGPoint,
        parentIDs: Set<UUID> = [],
        colorHex: String? = nil,
        plannedDate: Date? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.text = text
        self.position = position
        self.parentIDs = parentIDs
        self.colorHex = colorHex
        self.plannedDate = plannedDate
        self.isHidden = isHidden
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case position
        case parentIDs
        case colorHex
        case plannedDate
        case isHidden
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        position = try container.decode(CGPoint.self, forKey: .position)
        parentIDs = try container.decode(Set<UUID>.self, forKey: .parentIDs)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        plannedDate = try container.decodeIfPresent(Date.self, forKey: .plannedDate)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }
}
