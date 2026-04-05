import CoreGraphics
import Foundation

/// Figma-style alignment snapping while dragging nodes: compares selection bounds to other nodes and returns a small correction + guide geometry (canvas space).
enum CanvasAlignmentSnap {
    struct VerticalGuide {
        /// Vertical line x (canvas).
        var x: CGFloat
        var y1: CGFloat
        var y2: CGFloat
        /// Intersection markers on *reference* nodes only (canvas points).
        var markers: [CGPoint]
    }

    struct HorizontalGuide {
        var y: CGFloat
        var x1: CGFloat
        var x2: CGFloat
        var markers: [CGPoint]
    }

    struct Result {
        var snapDelta: CGSize
        var verticals: [VerticalGuide]
        var horizontals: [HorizontalGuide]
    }

    private static let alignEpsilon: CGFloat = 0.5

    /// - Parameters:
    ///   - draggedNodeIDs: Nodes being moved (excluded from references).
    ///   - nodes: All nodes.
    ///   - referenceNodes: Candidates to snap to (caller filters by viewport visibility).
    ///   - combinedTranslation: Gesture + autoscroll delta in canvas space (same for every dragged node).
    ///   - thresholdCanvas: Maximum snap distance in canvas points.
    static func compute(
        draggedNodeIDs: Set<UUID>,
        nodes: [UUID: KommitNode],
        referenceNodes: [KommitNode],
        combinedTranslation: CGSize,
        thresholdCanvas: CGFloat,
        measuredNodeSizes: [UUID: CGSize] = [:]
    ) -> Result {
        guard thresholdCanvas > 0, !draggedNodeIDs.isEmpty else {
            return Result(snapDelta: .zero, verticals: [], horizontals: [])
        }

        var dragRects: [CGRect] = []
        dragRects.reserveCapacity(draggedNodeIDs.count)
        for id in draggedNodeIDs {
            guard let node = nodes[id] else { continue }
            let rect = rect(for: node, measuredNodeSizes: measuredNodeSizes)
            let ox = rect.minX + combinedTranslation.width
            let oy = rect.minY + combinedTranslation.height
            dragRects.append(CGRect(x: ox, y: oy, width: rect.width, height: rect.height))
        }
        guard let dragBBox = unionRect(dragRects), !dragBBox.isNull, !dragBBox.isEmpty else {
            return Result(snapDelta: .zero, verticals: [], horizontals: [])
        }

        let dx = bestAxisSnap(
            dragMin: dragBBox.minX,
            dragMid: dragBBox.midX,
            dragMax: dragBBox.maxX,
            references: referenceNodes,
            refMin: { rect(for: $0, measuredNodeSizes: measuredNodeSizes).minX },
            refMid: { rect(for: $0, measuredNodeSizes: measuredNodeSizes).midX },
            refMax: { rect(for: $0, measuredNodeSizes: measuredNodeSizes).maxX },
            threshold: thresholdCanvas
        )
        let dy = bestAxisSnap(
            dragMin: dragBBox.minY,
            dragMid: dragBBox.midY,
            dragMax: dragBBox.maxY,
            references: referenceNodes,
            refMin: { rect(for: $0, measuredNodeSizes: measuredNodeSizes).minY },
            refMid: { rect(for: $0, measuredNodeSizes: measuredNodeSizes).midY },
            refMax: { rect(for: $0, measuredNodeSizes: measuredNodeSizes).maxY },
            threshold: thresholdCanvas
        )

        let snapDelta = CGSize(width: dx?.delta ?? 0, height: dy?.delta ?? 0)
        guard dx != nil || dy != nil else {
            return Result(snapDelta: .zero, verticals: [], horizontals: [])
        }

        let snappedBBox = dragBBox.offsetBy(dx: snapDelta.width, dy: snapDelta.height)

        var verticals: [VerticalGuide] = []
        if let vx = dx?.lineCoordinate {
            verticals.append(
                verticalGuide(
                    x: vx,
                    snappedDragBBox: snappedBBox,
                    references: referenceNodes,
                    measuredNodeSizes: measuredNodeSizes
                )
            )
        }

        var horizontals: [HorizontalGuide] = []
        if let hy = dy?.lineCoordinate {
            horizontals.append(
                horizontalGuide(
                    y: hy,
                    snappedDragBBox: snappedBBox,
                    references: referenceNodes,
                    measuredNodeSizes: measuredNodeSizes
                )
            )
        }

        return Result(snapDelta: snapDelta, verticals: verticals, horizontals: horizontals)
    }

    private struct AxisSnap {
        var delta: CGFloat
        var lineCoordinate: CGFloat
    }

    private static func bestAxisSnap(
        dragMin: CGFloat,
        dragMid: CGFloat,
        dragMax: CGFloat,
        references: [KommitNode],
        refMin: (KommitNode) -> CGFloat,
        refMid: (KommitNode) -> CGFloat,
        refMax: (KommitNode) -> CGFloat,
        threshold: CGFloat
    ) -> AxisSnap? {
        let dragValues = [dragMin, dragMid, dragMax]
        var best: (absDelta: CGFloat, delta: CGFloat, line: CGFloat)?

        for ref in references {
            let r0 = refMin(ref)
            let r1 = refMid(ref)
            let r2 = refMax(ref)
            let refValues = [r0, r1, r2]

            for d in dragValues {
                for r in refValues {
                    let delta = r - d
                    let ad = abs(delta)
                    guard ad <= threshold else { continue }
                    if best == nil || ad < best!.absDelta {
                        best = (ad, delta, r)
                    }
                }
            }
        }

        guard let b = best else { return nil }
        return AxisSnap(delta: b.delta, lineCoordinate: b.line)
    }

    private static func verticalGuide(
        x: CGFloat,
        snappedDragBBox: CGRect,
        references: [KommitNode],
        measuredNodeSizes: [UUID: CGSize]
    ) -> VerticalGuide {
        var yLow = min(snappedDragBBox.minY, snappedDragBBox.maxY)
        var yHigh = max(snappedDragBBox.minY, snappedDragBBox.maxY)
        var markers: [CGPoint] = []

        for ref in references {
            let r = rect(for: ref, measuredNodeSizes: measuredNodeSizes)
            guard refHasVerticalSnap(x: x, rect: r) else { continue }
            yLow = min(yLow, r.minY)
            yHigh = max(yHigh, r.maxY)
            markers.append(CGPoint(x: x, y: r.minY))
            markers.append(CGPoint(x: x, y: r.maxY))
            if abs(x - r.midX) < alignEpsilon {
                markers.append(CGPoint(x: x, y: r.midY))
            }
        }

        yLow = min(yLow, snappedDragBBox.minY, snappedDragBBox.maxY)
        yHigh = max(yHigh, snappedDragBBox.minY, snappedDragBBox.maxY)

        return VerticalGuide(x: x, y1: yLow, y2: yHigh, markers: markers)
    }

    private static func horizontalGuide(
        y: CGFloat,
        snappedDragBBox: CGRect,
        references: [KommitNode],
        measuredNodeSizes: [UUID: CGSize]
    ) -> HorizontalGuide {
        var xLow = min(snappedDragBBox.minX, snappedDragBBox.maxX)
        var xHigh = max(snappedDragBBox.minX, snappedDragBBox.maxX)
        var markers: [CGPoint] = []

        for ref in references {
            let r = rect(for: ref, measuredNodeSizes: measuredNodeSizes)
            guard refHasHorizontalSnap(y: y, rect: r) else { continue }
            xLow = min(xLow, r.minX)
            xHigh = max(xHigh, r.maxX)
            markers.append(CGPoint(x: r.minX, y: y))
            markers.append(CGPoint(x: r.maxX, y: y))
            if abs(y - r.midY) < alignEpsilon {
                markers.append(CGPoint(x: r.midX, y: y))
            }
        }

        xLow = min(xLow, snappedDragBBox.minX, snappedDragBBox.maxX)
        xHigh = max(xHigh, snappedDragBBox.maxX, snappedDragBBox.minX)

        return HorizontalGuide(y: y, x1: xLow, x2: xHigh, markers: markers)
    }

    private static func rect(for node: KommitNode, measuredNodeSizes: [UUID: CGSize]) -> CGRect {
        let size = measuredNodeSizes[node.id] ?? CGSize(width: CGFloat(node.width), height: CGFloat(node.height))
        return CGRect(x: CGFloat(node.x), y: CGFloat(node.y), width: size.width, height: size.height)
    }

    private static func refHasVerticalSnap(x: CGFloat, rect: CGRect) -> Bool {
        abs(x - rect.minX) < alignEpsilon || abs(x - rect.maxX) < alignEpsilon || abs(x - rect.midX) < alignEpsilon
    }

    private static func refHasHorizontalSnap(y: CGFloat, rect: CGRect) -> Bool {
        abs(y - rect.minY) < alignEpsilon || abs(y - rect.maxY) < alignEpsilon || abs(y - rect.midY) < alignEpsilon
    }

    private static func unionRect(_ rects: [CGRect]) -> CGRect? {
        guard var u = rects.first else { return nil }
        for i in 1 ..< rects.count {
            u = u.union(rects[i])
        }
        return u
    }
}
