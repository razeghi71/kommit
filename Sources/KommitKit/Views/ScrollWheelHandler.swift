import SwiftUI
import AppKit

/// Captures scroll wheel events: pans the canvas, or zooms when ⌘ is held (cursor as focal point).
struct ScrollWheelHandler: NSViewRepresentable {
    @Binding var panOffset: CGSize
    @Binding var scale: CGFloat
    var viewportSize: CGSize

    private static let scaleMin: CGFloat = 0.2
    private static let scaleMax: CGFloat = 5.0
    /// Per-point multiplier exponent when `hasPreciseScrollingDeltas` is true.
    private static let preciseZoomK: CGFloat = 0.0028
    /// Per-line multiplier exponent for traditional mouse wheels.
    private static let lineZoomK: CGFloat = 0.11

    func makeNSView(context: Context) -> NSView {
        let view = ScrollWheelReceivingView()
        applyCallbacks(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ScrollWheelReceivingView else { return }
        applyCallbacks(to: view)
    }

    private func applyCallbacks(to view: ScrollWheelReceivingView) {
        let panBinding = $panOffset
        let scaleBinding = $scale
        let size = viewportSize
        view.updateCallback = { event, hostView in
            guard let eventWindow = event.window, eventWindow === hostView.window else {
                return event
            }
            let loc = hostView.convert(event.locationInWindow, from: nil)
            let deltaZoom = event.scrollingDeltaY + event.scrollingDeltaX
            let k = event.hasPreciseScrollingDeltas ? Self.preciseZoomK : Self.lineZoomK

            if event.modifierFlags.contains(.command), deltaZoom != 0 {
                DispatchQueue.main.async {
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let s = scaleBinding.wrappedValue
                    var pan = panBinding.wrappedValue
                    let focalCanvas = Self.canvasPoint(
                        underScreenPoint: loc,
                        offset: pan,
                        scale: s,
                        center: center
                    )
                    let nextScale = Self.clampScale(s * exp(deltaZoom * k))
                    pan = Self.panOffsetKeepingCanvasPointAtScreen(
                        canvasPoint: focalCanvas,
                        screenAnchor: loc,
                        scale: nextScale,
                        center: center
                    )
                    scaleBinding.wrappedValue = nextScale
                    panBinding.wrappedValue = pan
                }
                return nil
            }

            DispatchQueue.main.async {
                panBinding.wrappedValue.width += event.scrollingDeltaX
                panBinding.wrappedValue.height += event.scrollingDeltaY
            }
            return nil
        }
    }

    private static func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, scaleMin), scaleMax)
    }

    /// Same mapping as `CanvasView.screenPointToCanvas` (scaleEffect anchor at center).
    private static func canvasPoint(
        underScreenPoint point: CGPoint,
        offset: CGSize,
        scale: CGFloat,
        center: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: (point.x - center.x - offset.width) / scale + center.x,
            y: (point.y - center.y - offset.height) / scale + center.y
        )
    }

    private static func panOffsetKeepingCanvasPointAtScreen(
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

    final class ScrollWheelReceivingView: NSView {
        var updateCallback: ((NSEvent, NSView) -> NSEvent?)?
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                guard let callback = self.updateCallback else { return event }
                return callback(event, self)
            }
        }
    }
}
