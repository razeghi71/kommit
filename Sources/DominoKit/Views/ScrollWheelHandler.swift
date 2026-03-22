import SwiftUI
import AppKit

/// Captures scroll wheel events for the window and updates pan offset (replacing drag-to-pan).
struct ScrollWheelHandler: NSViewRepresentable {
    @Binding var panOffset: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = ScrollWheelReceivingView()
        view.updateCallback = { [binding = $panOffset] deltaX, deltaY in
            DispatchQueue.main.async {
                binding.wrappedValue.width += deltaX
                binding.wrappedValue.height += deltaY
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ScrollWheelReceivingView else { return }
        view.updateCallback = { [binding = $panOffset] deltaX, deltaY in
            DispatchQueue.main.async {
                binding.wrappedValue.width += deltaX
                binding.wrappedValue.height += deltaY
            }
        }
    }

    final class ScrollWheelReceivingView: NSView {
        var updateCallback: ((CGFloat, CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.updateCallback?(event.scrollingDeltaX, event.scrollingDeltaY)
                return nil
            }
        }
    }
}
