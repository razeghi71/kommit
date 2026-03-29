import AppKit
import DominoKit
import SwiftUI

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
                    appDelegate.openMainWindowAction = { [openWindow] in openWindow(id: "main") }
                    if let window = NSApplication.shared.windows.first {
                        appDelegate.mainWindow = window
                        appDelegate.configureWindow(window)
                    }
                    appDelegate.syncMainWindowDocumentTitle(with: viewModel)
                }
                .onReceive(viewModel.objectWillChange) { _ in
                    DispatchQueue.main.async {
                        appDelegate.syncMainWindowDocumentTitle(with: viewModel)
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
                        viewModel.newBoard(suppressStartHub: true)
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
                Button("Find") {
                    viewModel.presentSearch()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Recenter Canvas") {
                    viewModel.requestCanvasRecenter()
                }
                // ⌘C is reserved for Edit › Copy; a duplicate key equivalent does not show in the menu.
                .keyboardShortcut("0", modifiers: .command)

                Toggle("Show Node Ranks", isOn: $showNodeRanks)
                Toggle(
                    "Show Hidden Items",
                    isOn: Binding(
                        get: { viewModel.showHiddenItems },
                        set: { viewModel.setShowHiddenItems($0) }
                    )
                )
                Menu("Done") {
                    Button {
                        viewModel.setDoneVisibility(.showAll)
                    } label: {
                        Label("Show All", systemImage: viewModel.doneVisibility == .showAll ? "checkmark" : "")
                    }
                    Button {
                        viewModel.setDoneVisibility(.hideChains)
                    } label: {
                        Label("Hide Done Chains", systemImage: viewModel.doneVisibility == .hideChains ? "checkmark" : "")
                    }
                    Button {
                        viewModel.setDoneVisibility(.hideAll)
                    } label: {
                        Label("Hide Done Nodes", systemImage: viewModel.doneVisibility == .hideAll ? "checkmark" : "")
                    }
                }
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
        Window("Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 620, height: 520)
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
    var mainWindow: NSWindow?
    var openMainWindowAction: (() -> Void)?

    func configureWindow(_ window: NSWindow) {
        window.delegate = self
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = false
        window.backgroundColor = AppColors.canvasBackground
        if window === mainWindow, let viewModel {
            window.title = viewModel.documentWindowTitle
        }
    }

    func syncMainWindowDocumentTitle(with viewModel: DominoViewModel) {
        mainWindow?.title = viewModel.documentWindowTitle
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }
        guard let viewModel else { return true }
        if viewModel.isDirty {
            guard DominoViewModel.showDiscardConfirmation(
                informativeText: DominoViewModel.documentDiscardInformativeText
            ) else { return false }
        }
        viewModel.resetToStartHub()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel, viewModel.isDirty else { return .terminateNow }
        guard DominoViewModel.showDiscardConfirmation(
            informativeText: DominoViewModel.documentDiscardInformativeText
        ) else { return .terminateCancel }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            openMainWindowAction?()
        }
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
