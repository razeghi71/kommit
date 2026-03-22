import AppKit
import SwiftUI
import XCTest

@testable import DominoKit

private extension NSView {
    func allDescendants() -> [NSView] {
        var out: [NSView] = [self]
        for child in subviews {
            out.append(contentsOf: child.allDescendants())
        }
        return out
    }
}

/// Stress-tests the AppKit table used by `NodesTableView` while mutating node status.
/// This targets crashes in AppKit constraint / baseline updates when the table reloads.
@MainActor
final class TableStatusStressTests: XCTestCase {
    func testNodesTableViewRepeatedStatusChangesWithLayout() throws {
        _ = NSApplication.shared

        let vm = DominoViewModel()
        vm.openSettingsWindowAction = {}

        vm.addNode(at: CGPoint(x: 120, y: 120))
        guard let nodeID = vm.editingNodeID else {
            XCTFail("Expected a new node after addNode")
            return
        }
        vm.commitEditing()
        vm.selectSingleNode(nodeID)

        let root = NSHostingView(
            rootView: NodesTableView(viewModel: vm)
                .frame(width: 920, height: 420)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 920, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        root.frame = window.contentView!.bounds
        root.autoresizingMask = [.width, .height]

        root.layoutSubtreeIfNeeded()
        pumpRunLoopForHostingLayout(root)

        let popupsAfterLayout = root.allDescendants().compactMap { $0 as? NSPopUpButton }
        XCTAssertGreaterThanOrEqual(
            popupsAfterLayout.count,
            1,
            "NSTableView status column should contain an NSPopUpButton once SwiftUI/AppKit layout runs"
        )

        let inProgress = DominoStatusSettings.inProgressStatusID
        let done = DominoStatusSettings.doneStatusID

        for _ in 0..<25 {
            vm.setNodeStatus(nodeID, statusID: nil)
            root.layoutSubtreeIfNeeded()

            vm.setNodeStatus(nodeID, statusID: inProgress)
            root.layoutSubtreeIfNeeded()

            vm.setNodeStatus(nodeID, statusID: done)
            root.layoutSubtreeIfNeeded()
        }

        pumpRunLoopForHostingLayout(root, iterations: 8, step: 0.01)
    }

    /// Simulates choosing a different item on the first status popup (without going modal).
    func testNodesTableViewPopUpButtonSelection() throws {
        _ = NSApplication.shared

        let vm = DominoViewModel()
        vm.openSettingsWindowAction = {}

        vm.addNode(at: CGPoint(x: 50, y: 50))
        guard let nodeID = vm.editingNodeID else {
            XCTFail("Expected a new node after addNode")
            return
        }
        vm.commitEditing()

        let root = NSHostingView(
            rootView: NodesTableView(viewModel: vm)
                .frame(width: 800, height: 300)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        root.frame = window.contentView!.bounds
        root.layoutSubtreeIfNeeded()
        pumpRunLoopForHostingLayout(root)

        guard let popup = root.allDescendants().compactMap({ $0 as? NSPopUpButton }).first else {
            XCTFail("Expected NSPopUpButton in table")
            return
        }

        for idx in 0..<min(popup.numberOfItems, 6) {
            popup.selectItem(at: idx)
            root.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        // Restore a sane state
        vm.setNodeStatus(nodeID, statusID: nil)
        root.layoutSubtreeIfNeeded()
    }

    private func pumpRunLoopForHostingLayout(
        _ root: NSView,
        iterations: Int = 12,
        step: TimeInterval = 0.015
    ) {
        for _ in 0..<iterations {
            root.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(step))
        }
    }
}
