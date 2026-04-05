import CoreGraphics
import Foundation

enum DragDirection: Sendable {
    case top, right, bottom, left
}

/// Distribute multi-selected nodes to a common edge using the extreme node on that axis.
enum NodeAlignment: Sendable {
    case left, right, top, bottom
}

struct EdgeDragState: Equatable {
    var sourceNodeID: UUID
    var direction: DragDirection
    var currentPoint: CGPoint
}

struct NodeFocusRequest: Equatable {
    let nodeID: UUID
    let token = UUID()
}

struct SearchPresentationRequest: Equatable {
    let token = UUID()
}
