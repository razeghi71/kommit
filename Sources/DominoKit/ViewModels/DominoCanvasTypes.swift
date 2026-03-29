import CoreGraphics
import Foundation

enum DragDirection: Sendable {
    case top, right, bottom, left
}

enum AlignmentAxis: Sendable {
    case horizontal  // a horizontal line (y value)
    case vertical  // a vertical line (x value)
}

/// Distribute multi-selected nodes to a common edge using the extreme node on that axis.
enum NodeAlignment: Sendable {
    case left, right, top, bottom
}

struct GuideSegment: Equatable, Sendable {
    let from: CGPoint
    let to: CGPoint
}

struct SnapGuide: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case alignmentLine
        case gapIndicator
    }

    let kind: Kind
    let axis: AlignmentAxis
    let position: CGFloat?
    let segments: [GuideSegment]
    let targetNodeIDs: [UUID]

    static func alignmentLine(axis: AlignmentAxis, position: CGFloat, targetNodeIDs: [UUID]) -> SnapGuide {
        SnapGuide(
            kind: .alignmentLine,
            axis: axis,
            position: position,
            segments: [],
            targetNodeIDs: Array(Set(targetNodeIDs)).sorted { $0.uuidString < $1.uuidString }
        )
    }

    static func gapIndicator(axis: AlignmentAxis, segments: [GuideSegment], targetNodeIDs: [UUID]) -> SnapGuide {
        SnapGuide(
            kind: .gapIndicator,
            axis: axis,
            position: nil,
            segments: segments,
            targetNodeIDs: Array(Set(targetNodeIDs)).sorted { $0.uuidString < $1.uuidString }
        )
    }
}

struct SnapResult: Sendable {
    var snappedOffset: CGSize  // the adjusted offset after snapping
    var guides: [SnapGuide]  // active guide lines to display
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
