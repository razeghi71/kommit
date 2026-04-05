import SwiftUI
import AppKit

/// Captures scroll wheel events: pans the canvas, or zooms when ⌘ is held (cursor as focal point).
struct ScrollWheelHandler: NSViewRepresentable {
    @Binding var panOffset: CGSize
    @Binding var scale: CGFloat
    var viewportSize: CGSize

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
            let k = event.hasPreciseScrollingDeltas
                ? CanvasZoomController.preciseScrollExponent
                : CanvasZoomController.lineScrollExponent

            if event.modifierFlags.contains(.command), deltaZoom != 0 {
                guard CanvasZoomController.canHandleKeyboardShortcut(in: hostView.window) else {
                    return event
                }
                DispatchQueue.main.async {
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let next = CanvasZoomController.zoom(
                        offset: panBinding.wrappedValue,
                        scale: scaleBinding.wrappedValue,
                        anchor: loc,
                        center: center,
                        multiplier: exp(deltaZoom * k)
                    )
                    scaleBinding.wrappedValue = next.scale
                    panBinding.wrappedValue = next.offset
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
