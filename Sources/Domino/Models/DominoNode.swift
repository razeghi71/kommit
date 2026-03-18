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

    init(
        id: UUID = UUID(),
        text: String = "",
        position: CGPoint,
        parentIDs: Set<UUID> = [],
        colorHex: String? = nil,
        plannedDate: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.position = position
        self.parentIDs = parentIDs
        self.colorHex = colorHex
        self.plannedDate = plannedDate
    }
}
