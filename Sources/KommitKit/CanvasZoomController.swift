import AppKit
import SwiftUI

package enum CanvasZoomCommand: String {
    case zoomIn
    case zoomOut
}

package enum CanvasZoomController {
    static let commandNotification = Notification.Name("Kommit.CanvasZoomCommand")

    static let minScale: CGFloat = 0.2
    static let maxScale: CGFloat = 5.0
    /// Per-point multiplier exponent when `hasPreciseScrollingDeltas` is true.
    static let preciseScrollExponent: CGFloat = 0.0028
    /// Per-line multiplier exponent for traditional mouse wheels.
    static let lineScrollExponent: CGFloat = 0.11

    package static func post(_ command: CanvasZoomCommand) {
        NotificationCenter.default.post(name: commandNotification, object: command.rawValue)
    }

    static func command(from notification: Notification) -> CanvasZoomCommand? {
        guard let rawValue = notification.object as? String else { return nil }
        return CanvasZoomCommand(rawValue: rawValue)
    }

    @MainActor
    package static func canHandleKeyboardShortcut(in window: NSWindow?) -> Bool {
        guard let window, window.isKeyWindow else { return false }
        switch window.firstResponder {
        case is NSTextView:
            return false
        case let field as NSTextField where field.isEditable:
            return false
        default:
            return true
        }
    }

    static func clampScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minScale), maxScale)
    }

    static func keyboardStepFactor(zoomingIn: Bool) -> CGFloat {
        let zoomInFactor = exp(lineScrollExponent)
        return zoomingIn ? zoomInFactor : 1 / zoomInFactor
    }

    /// Same mapping as `CanvasView.screenPointToCanvas` (scaleEffect anchor at center).
    static func screenPointToCanvas(
        _ point: CGPoint,
        offset: CGSize,
        scale: CGFloat,
        center: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: (point.x - center.x - offset.width) / scale + center.x,
            y: (point.y - center.y - offset.height) / scale + center.y
        )
    }

    static func panOffsetKeepingCanvasPointAtScreen(
        canvasPoint: CGPoint,
        screenAnchor: CGPoint,
        scale: CGFloat,
        center: CGPoint
    ) -> CGSize {
        let c = center
        return CGSize(
            width: screenAnchor.x - c.x - (canvasPoint.x - c.x) * scale,
            height: screenAnchor.y - c.y - (canvasPoint.y - c.y) * scale
        )
    }

    static func zoom(
        offset: CGSize,
        scale: CGFloat,
        anchor: CGPoint,
        center: CGPoint,
        multiplier: CGFloat
    ) -> (offset: CGSize, scale: CGFloat) {
        let focalCanvas = screenPointToCanvas(anchor, offset: offset, scale: scale, center: center)
        let nextScale = clampScale(scale * multiplier)
        let nextOffset = panOffsetKeepingCanvasPointAtScreen(
            canvasPoint: focalCanvas,
            screenAnchor: anchor,
            scale: nextScale,
            center: center
        )
        return (offset: nextOffset, scale: nextScale)
    }
}
