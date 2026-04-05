import CoreGraphics
import Foundation

/// Name for `View.coordinateSpace(name:)` on the canvas viewport layer (matches marquee selection coordinates).
enum KommitCanvasCoordinateSpace {
    static let viewportName = "kommitCanvasViewport"
}

enum DragDirection: Sendable {
    case top, right, bottom, left
}

/// Distribute multi-selected nodes to a common edge using the extreme node on that axis.
enum NodeAlignment: Sendable {
    case left, right, top, bottom, horizontalCenter, verticalCenter
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
