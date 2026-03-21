import AppKit
import SwiftUI

/// Shared palette for colours that must be identical across SDK/toolchain versions.
enum AppColors {
    /// The canvas and window background. Explicitly defined so it never drifts
    /// with the SDK-linked version of `NSColor.windowBackgroundColor`.
    static let canvasBackground = NSColor(name: "canvasBackground") { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua: return NSColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1)
        default:        return NSColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
        }
    }

    static var canvasBackgroundSwiftUI: Color { Color(nsColor: canvasBackground) }
}
