import Foundation

enum NodeDefaults {
    static let width = 132
    static let height = 44
    /// Minimum width for layout and persistence (`NodeView` `minWidth`). Default height for new nodes; intrinsic
    /// card height can be smaller once measured (single-line rows are usually below 44pt).
    static let minWidth = 100
    static let minHeight = 44
    /// For APIs that still need `CGSize` (e.g. previews).
    static var size: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }
}

struct KommitNode: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    /// Integer canvas coordinates: top-left of the node frame (implicit 1pt grid).
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var parentIDs: Set<UUID>
    var statusID: UUID?
    var plannedDate: Date?
    var budget: Double?
    var isHidden: Bool

    init(
        id: UUID = UUID(),
        text: String = "",
        x: Int,
        y: Int,
        width: Int = NodeDefaults.width,
        height: Int = NodeDefaults.height,
        parentIDs: Set<UUID> = [],
        statusID: UUID? = nil,
        plannedDate: Date? = nil,
        budget: Double? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.parentIDs = parentIDs
        self.statusID = statusID
        self.plannedDate = plannedDate
        self.budget = budget
        self.isHidden = isHidden
    }

    var center: CGPoint {
        CanvasIntegerGeometry.center(x: x, y: y, width: width, height: height)
    }

    var frameSize: CGSize {
        CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case x
        case y
        case width
        case height
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
        x = try container.decode(Int.self, forKey: .x)
        y = try container.decode(Int.self, forKey: .y)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
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
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(parentIDs, forKey: .parentIDs)
        try container.encodeIfPresent(statusID, forKey: .statusID)
        try container.encodeIfPresent(plannedDate, forKey: .plannedDate)
        try container.encodeIfPresent(budget, forKey: .budget)
        try container.encode(isHidden, forKey: .isHidden)
    }
}
