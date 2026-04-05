import CoreGraphics

/// Canvas layout uses integer point coordinates (implicit grid step 1).
enum CanvasIntegerGeometry {
    static func center(x: Int, y: Int, width: Int, height: Int) -> CGPoint {
        CGPoint(x: CGFloat(x) + CGFloat(width) / 2, y: CGFloat(y) + CGFloat(height) / 2)
    }

    /// Top-left after applying a canvas-space translation; rounds each axis independently.
    static func snappedOrigin(nodeX: Int, nodeY: Int, translation: CGSize) -> (x: Int, y: Int) {
        let nx = Int((Double(nodeX) + Double(translation.width)).rounded())
        let ny = Int((Double(nodeY) + Double(translation.height)).rounded())
        return (nx, ny)
    }

    /// Top-left so the node's center lands near `point` (e.g. double-click).
    static func topLeftCentered(at point: CGPoint, width: Int, height: Int) -> (x: Int, y: Int) {
        let x = Int((Double(point.x) - Double(width) / 2).rounded())
        let y = Int((Double(point.y) - Double(height) / 2).rounded())
        return (x, y)
    }

    static func sizeSnappedUp(from size: CGSize, minWidth: Int, minHeight: Int) -> (width: Int, height: Int) {
        let w = max(minWidth, Int(size.width.rounded(.up)))
        let h = max(minHeight, Int(size.height.rounded(.up)))
        return (w, h)
    }
}
