import SwiftUI
import AppKit

@main
struct DominoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = DominoViewModel()
    @AppStorage("showNodeRanks") private var showNodeRanks = true
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Domino", id: "main") {
            ContentView(viewModel: viewModel)
                .onAppear {
                    appDelegate.viewModel = viewModel
                    if let window = NSApplication.shared.windows.first {
                        appDelegate.configureWindow(window)
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    viewModel.save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    viewModel.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    ensureWindowOpen()
                    viewModel.confirmDiscardIfNeeded {
                        viewModel.newBoard()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open...") {
                    ensureWindowOpen()
                    viewModel.confirmDiscardIfNeeded {
                        viewModel.open()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    viewModel.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!viewModel.canUndo)

                Button("Redo") {
                    viewModel.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!viewModel.canRedo)
            }
            CommandGroup(after: .toolbar) {
                Toggle("Show Node Ranks", isOn: $showNodeRanks)
                Toggle(
                    "Show Hidden Items",
                    isOn: Binding(
                        get: { viewModel.showHiddenItems },
                        set: { viewModel.setShowHiddenItems($0) }
                    )
                )
            }
            CommandGroup(after: .pasteboard) {
                Button("Delete") {
                    if viewModel.selectedNodeIDs.count > 1 {
                        for id in viewModel.selectedNodeIDs {
                            viewModel.deleteNode(id)
                        }
                        viewModel.clearSelection()
                    } else if viewModel.selectedNodeID != nil {
                        viewModel.deleteSelectedNode()
                    } else if viewModel.selectedEdgeID != nil {
                        viewModel.deleteSelectedEdge()
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(viewModel.editingNodeID != nil || (viewModel.selectedNodeID == nil && viewModel.selectedEdgeID == nil))
            }
        }
    }

    private func ensureWindowOpen() {
        if NSApplication.shared.windows.filter({ $0.isVisible }).isEmpty {
            openWindow(id: "main")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    var viewModel: DominoViewModel?

    func configureWindow(_ window: NSWindow) {
        window.delegate = self
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.backgroundColor = AppColors.canvasBackground
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let viewModel, viewModel.isDirty else { return true }
        guard DominoViewModel.showDiscardAlert() else { return false }
        viewModel.newBoard()
        return true
    }

    func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        configureWindow(window)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        } else if let icon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                self.configureWindow(window)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
