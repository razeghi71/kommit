import AppKit
import KommitKit
import SwiftUI

@main
struct KommitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = KommitViewModel()
    @AppStorage("showNodeRanks") private var showNodeRanks = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        // Smaller welcome window is listed first so it is the default at launch (same pattern as IntelliJ).
        Window("Welcome to Kommit", id: "hub") {
            StartHubView(viewModel: viewModel)
                .frame(minWidth: 620, idealWidth: 780, minHeight: 440, idealHeight: 560)
                .background(HubWindowAccessor { window in
                    appDelegate.hubWindow = window
                    appDelegate.configureWindow(window)
                })
                .onAppear {
                    appDelegate.viewModel = viewModel
                    appDelegate.openHubWindowAction = { [openWindow] in openWindow(id: "hub") }
                }
                .onChange(of: viewModel.shouldShowStartHub) { _, showHub in
                    guard !showHub else { return }
                    appDelegate.suppressTerminateWhenHubCloses = true
                    dismissWindow(id: "hub")
                    openWindow(id: "main")
                }
        }
        .defaultSize(width: 780, height: 560)

        Window(viewModel.documentWindowTitle, id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 800, idealWidth: 1200, minHeight: 600, idealHeight: 800)
                .background(MainWindowAccessor { window in
                    appDelegate.mainWindow = window
                    appDelegate.configureWindow(window)
                })
                .onAppear {
                    appDelegate.viewModel = viewModel
                    appDelegate.openMainWindowAction = { [openWindow] in openWindow(id: "main") }
                    appDelegate.openHubWindowAction = { [openWindow] in openWindow(id: "hub") }
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
                    ensureWorkspaceWindowOpen()
                    viewModel.confirmDiscardIfNeeded {
                        viewModel.newBoard(suppressStartHub: true)
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open...") {
                    ensureWorkspaceWindowOpen()
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

                Button("Zoom In") {
                    appDelegate.performCanvasZoom(.zoomIn)
                }
                // Standard macOS mapping: ⌘+ (base key is “=”).
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    appDelegate.performCanvasZoom(.zoomOut)
                }
                .keyboardShortcut("-", modifiers: .command)

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

    private func ensureWorkspaceWindowOpen() {
        let visible = NSApplication.shared.windows.filter(\.isVisible)
        guard visible.isEmpty else { return }
        if viewModel.shouldShowStartHub {
            openWindow(id: "hub")
        } else {
            openWindow(id: "main")
        }
    }
}

/// Resolves the welcome window so hub close can quit the app (except during programmatic dismiss).
private struct HubWindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    final class Coordinator {
        weak var attachedWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { attachIfNeeded(view, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { attachIfNeeded(nsView, coordinator: context.coordinator) }
    }

    private func attachIfNeeded(_ view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        if coordinator.attachedWindow === window { return }
        coordinator.attachedWindow = window
        onAttach(window)
    }
}

/// Resolves the actual `NSWindow` that hosts the main canvas (not the welcome window).
private struct MainWindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    final class Coordinator {
        weak var attachedWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { attachIfNeeded(view, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { attachIfNeeded(nsView, coordinator: context.coordinator) }
    }

    private func attachIfNeeded(_ view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        if coordinator.attachedWindow === window { return }
        coordinator.attachedWindow = window
        onAttach(window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    var viewModel: KommitViewModel?
    var mainWindow: NSWindow?
    /// Welcome window; when the user closes it (red button or ⌘W), the app terminates.
    var hubWindow: NSWindow?
    /// Set while dismissing the hub to open the main window — must not trigger quit.
    var suppressTerminateWhenHubCloses = false
    var openMainWindowAction: (() -> Void)?
    var openHubWindowAction: (() -> Void)?

    /// `kVK_ANSI_KeypadPlus` — SwiftUI’s ⌘+ menu binding uses the `=` key only, not numpad `+`.
    private static let keypadPlusKeyCode: UInt16 = 0x45

    private var canvasKeypadZoomMonitor: Any?

    func configureWindow(_ window: NSWindow) {
        window.delegate = self
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = false
        window.backgroundColor = AppColors.canvasBackground
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === hubWindow {
            return true
        }
        guard sender === mainWindow else { return true }
        guard let viewModel else { return true }
        if viewModel.isDirty {
            guard KommitViewModel.showDiscardConfirmation(
                informativeText: KommitViewModel.documentDiscardInformativeText
            ) else { return false }
        }
        viewModel.resetToStartHub()
        openHubWindowAction?()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === mainWindow {
            mainWindow = nil
        }
        if window === hubWindow {
            hubWindow = nil
            if suppressTerminateWhenHubCloses {
                suppressTerminateWhenHubCloses = false
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel, viewModel.isDirty else { return .terminateNow }
        guard KommitViewModel.showDiscardConfirmation(
            informativeText: KommitViewModel.documentDiscardInformativeText
        ) else { return .terminateCancel }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            if viewModel?.shouldShowStartHub == true {
                openHubWindowAction?()
            } else {
                openMainWindowAction?()
            }
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
        installCanvasKeypadZoomMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                self.configureWindow(window)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Handles ⌘ on the numeric keypad `+` so Zoom In matches the main keyboard (⌘+ / ⌘=).
    private func installCanvasKeypadZoomMonitor() {
        guard canvasKeypadZoomMonitor == nil else { return }
        canvasKeypadZoomMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == Self.keypadPlusKeyCode else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !flags.contains(.control) else { return event }
            guard let main = self.mainWindow, event.window === main else { return event }
            guard CanvasZoomController.canHandleKeyboardShortcut(in: main) else { return event }
            CanvasZoomController.post(.zoomIn)
            return nil
        }
    }

    func performCanvasZoom(_ command: CanvasZoomCommand) {
        guard CanvasZoomController.canHandleKeyboardShortcut(in: mainWindow) else { return }
        CanvasZoomController.post(command)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
