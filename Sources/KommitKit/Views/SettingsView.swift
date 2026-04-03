import AppKit
import SwiftUI

private enum SettingsSidebarSection: String, CaseIterable, Identifiable {
    case tasks
    case financial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .financial: "Financial"
        }
    }

    var systemImage: String {
        switch self {
        case .tasks: "checklist"
        case .financial: "dollarsign.circle"
        }
    }
}

package struct SettingsView: View {
    @ObservedObject package var viewModel: KommitViewModel
    @AppStorage(FinancialPlanningUserDefaultsKey.hideFullyPaidCommitments) private var hideFullyPaidCommitments = true
    @State private var selectedSection: SettingsSidebarSection = .tasks
    @State private var editorScope: KommitViewModel.StatusSettingsScope = .system
    @State private var financialCurrencyScope: KommitViewModel.StatusSettingsScope = .system

    package init(viewModel: KommitViewModel) {
        self.viewModel = viewModel
    }

    private var currentEditorScope: KommitViewModel.StatusSettingsScope {
        viewModel.hasFileStatusSettings ? editorScope : .system
    }

    private var currentEditorSettings: KommitStatusSettings {
        viewModel.resolvedStatusSettings(for: currentEditorScope)
    }

    package var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(SettingsSidebarSection.allCases) { section in
                    sidebarButton(section)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 84)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            Group {
                switch selectedSection {
                case .tasks:
                    tasksManagementPane
                case .financial:
                    financialPlaceholderPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(AppColors.canvasBackgroundSwiftUI)
        .onAppear {
            syncEditorScopeWithModel()
            syncFinancialCurrencyScopeWithModel()
        }
        .onChange(of: viewModel.fileLoadID) { _, _ in
            syncEditorScopeWithModel()
            syncFinancialCurrencyScopeWithModel()
        }
    }

    private func sidebarButton(_ section: SettingsSidebarSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            selectedSection = section
        } label: {
            VStack(spacing: 6) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(section.title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var tasksManagementPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tasks")
                        .font(.title2.weight(.semibold))
                    Text("This board uses one status palette at a time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                tasksHeader
                statusEditorSection(for: currentEditorScope)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tasksHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusSourceTitle)
                    .font(.headline)
                Text(statusSourceDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.hasFileStatusSettings {
                HStack(spacing: 12) {
                    Picker("Editing", selection: $editorScope) {
                        Text("Current Board").tag(KommitViewModel.StatusSettingsScope.file)
                        Text("System Defaults").tag(KommitViewModel.StatusSettingsScope.system)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    Button("Use System Defaults", role: .destructive) {
                        confirmRevertToSystemDefaults()
                    }
                }
            } else if viewModel.hasOpenBoardContext {
                Button("Customize for This Board") {
                    viewModel.addFileStatusSettings()
                    editorScope = .file
                }
            } else {
                Text("Open or create a board to add board-specific status overrides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusEditorSection(for scope: KommitViewModel.StatusSettingsScope) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editorSectionTitle(for: scope))
                .font(.headline)

            Text(editorSectionDescription(for: scope))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            StatusSettingsEditor(
                statuses: currentEditorSettings.statusPalette,
                scope: scope,
                viewModel: viewModel,
                onRemoveStatus: { status in
                    confirmRemovingStatus(status, from: scope)
                }
            )
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )

            if scope == .system && viewModel.hasFileStatusSettings {
                Text("You are editing the shared defaults. This board keeps using its own custom palette until you switch it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentFinancialCurrencyScope: KommitViewModel.StatusSettingsScope {
        viewModel.hasFileCurrencyOverride ? financialCurrencyScope : .system
    }

    private var financialCurrencyPickerSelection: Binding<String> {
        Binding(
            get: {
                switch currentFinancialCurrencyScope {
                case .file:
                    return viewModel.filePreferredCurrencyCode ?? viewModel.systemPreferredCurrencyCode
                case .system:
                    return viewModel.systemPreferredCurrencyCode
                }
            },
            set: { newValue in
                switch currentFinancialCurrencyScope {
                case .file:
                    viewModel.updateFilePreferredCurrencyCode(newValue)
                case .system:
                    viewModel.updateSystemPreferredCurrencyCode(newValue)
                }
            }
        )
    }

    private var financialPlaceholderPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Financial")
                        .font(.title2.weight(.semibold))
                    Text("Amounts in calendars, summaries, and lists follow one currency at a time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                financialCurrencyHeader
                financialCurrencyEditorSection

                GroupBox("Financial planning") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Hide fully paid commitments", isOn: $hideFullyPaidCommitments)
                        Text(
                            "When this is on, the Financial Planning list omits one-time commitments whose due date is in the past and are paid, and recurring commitments whose end date is in the past (or fixed count finished) with every occurrence paid."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var financialCurrencyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(financialCurrencySourceTitle)
                    .font(.headline)
                Text(financialCurrencySourceDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.hasFileCurrencyOverride {
                HStack(spacing: 12) {
                    Picker("Editing", selection: $financialCurrencyScope) {
                        Text("Current Board").tag(KommitViewModel.StatusSettingsScope.file)
                        Text("System Defaults").tag(KommitViewModel.StatusSettingsScope.system)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    Button("Use System Default Currency", role: .destructive) {
                        confirmRevertFinancialCurrencyToSystem()
                    }
                }
            } else if viewModel.hasOpenBoardContext {
                Button("Customize Currency for This Board") {
                    viewModel.addFileCurrencyOverride()
                    financialCurrencyScope = .file
                }
            } else {
                Text("Open or create a board to set a currency that is saved only in that file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var financialCurrencyEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(financialCurrencySectionTitle(for: currentFinancialCurrencyScope))
                .font(.headline)

            Text(financialCurrencySectionDescription(for: currentFinancialCurrencyScope))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Currency", selection: financialCurrencyPickerSelection) {
                ForEach(FinancialCurrencyFormatting.sortedISOCurrencyCodes, id: \.self) { code in
                    Text(Self.currencyMenuLabel(for: code)).tag(code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 420, alignment: .leading)

            if currentFinancialCurrencyScope == .system && viewModel.hasFileCurrencyOverride {
                Text("You are editing the shared default. This board keeps its own currency until you switch it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var financialCurrencySourceTitle: String {
        if !viewModel.hasOpenBoardContext {
            return "Editing the system default currency"
        }
        if viewModel.hasFileCurrencyOverride {
            return "This board uses a custom currency"
        }
        return "This board uses the system default currency"
    }

    private var financialCurrencySourceDescription: String {
        if !viewModel.hasOpenBoardContext {
            return "Open or create a board to use a different currency in just that file."
        }
        if viewModel.hasFileCurrencyOverride {
            return "The override is saved in \(boardFileDescription)."
        }
        return "Changes to the system default affect every board without its own currency."
    }

    private func financialCurrencySectionTitle(for scope: KommitViewModel.StatusSettingsScope) -> String {
        switch scope {
        case .file:
            return "Currency for This Board"
        case .system:
            if viewModel.hasFileCurrencyOverride || !viewModel.hasOpenBoardContext {
                return "System Default Currency"
            }
            return "Currency"
        }
    }

    private func financialCurrencySectionDescription(for scope: KommitViewModel.StatusSettingsScope) -> String {
        switch scope {
        case .file:
            return "Only this board uses this ISO currency for display."
        case .system:
            if !viewModel.hasOpenBoardContext {
                return "Boards without a per-file override use this currency."
            }
            if viewModel.hasFileCurrencyOverride {
                return "Boards without a per-file override use this currency."
            }
            return "This board follows the system default above."
        }
    }

    private func syncFinancialCurrencyScopeWithModel() {
        financialCurrencyScope = viewModel.hasFileCurrencyOverride ? .file : .system
    }

    private static func currencyMenuLabel(for code: String) -> String {
        let localized = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(localized) (\(code))"
    }

    private func confirmRevertFinancialCurrencyToSystem() {
        let alert = NSAlert()
        alert.messageText = "Use System Default Currency?"
        alert.informativeText =
            "This removes the board-specific currency from \(boardFileDescription). Amounts will use the shared system default."
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        viewModel.removeFileCurrencyOverride()
        financialCurrencyScope = .system
    }

    private var statusSourceTitle: String {
        if !viewModel.hasOpenBoardContext {
            return "Editing the system defaults"
        }
        switch viewModel.effectiveStatusSettingsScope {
        case .file:
            return "This board is using custom statuses"
        case .system:
            return "This board is using the system defaults"
        }
    }

    private var statusSourceDescription: String {
        if !viewModel.hasOpenBoardContext {
            return "Open or create a board to customize statuses for just that board."
        }
        switch viewModel.effectiveStatusSettingsScope {
        case .file:
            return "Changes to the current board are saved in \(boardFileDescription)."
        case .system:
            return "Changes here affect every board that has not been customized."
        }
    }

    private func editorSectionTitle(for scope: KommitViewModel.StatusSettingsScope) -> String {
        switch scope {
        case .file:
            return "Statuses for This Board"
        case .system:
            if viewModel.hasFileStatusSettings || !viewModel.hasOpenBoardContext {
                return "System Default Statuses"
            }
            return "Statuses"
        }
    }

    private func editorSectionDescription(for scope: KommitViewModel.StatusSettingsScope) -> String {
        switch scope {
        case .file:
            return "Only this board uses these statuses."
        case .system:
            if !viewModel.hasOpenBoardContext {
                return "These are the shared defaults used by boards without custom statuses."
            }
            if viewModel.hasFileStatusSettings {
                return "These are the shared defaults used by boards without custom statuses."
            }
            return "These are the statuses currently used by this board."
        }
    }

    private func syncEditorScopeWithModel() {
        editorScope = viewModel.hasFileStatusSettings ? .file : .system
    }

    private var boardFileDescription: String {
        if let currentFileURL = viewModel.currentFileURL {
            return currentFileURL.lastPathComponent
        }
        return "this board"
    }

    private func confirmRemovingStatus(_ status: KommitStatusDefinition, from scope: KommitViewModel.StatusSettingsScope) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(status.name)\"?"
        alert.informativeText = removeStatusMessage(for: status, from: scope)
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        viewModel.removeStatus(status.id, from: scope)
    }

    private func confirmRevertToSystemDefaults() {
        let alert = NSAlert()
        alert.messageText = "Revert to System Defaults?"
        alert.informativeText = revertToSystemDefaultsMessage()
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        viewModel.removeFileStatusSettings()
        editorScope = .system
    }

    private func removeStatusMessage(for status: KommitStatusDefinition, from scope: KommitViewModel.StatusSettingsScope) -> String {
        let impact = viewModel.removalImpact(forStatus: status.id, from: scope)
        if impact.affectedNodeCount > 0 {
            return "\(impact.affectedNodeCount) task\(impact.affectedNodeCount == 1 ? "" : "s") on this board currently use this status. Deleting it will clear their status assignment.\(sampleTaskSuffix(for: impact))"
        }

        switch scope {
        case .file:
            return "This status will be removed from the current board override saved in \(boardFileDescription)."
        case .system:
            if viewModel.hasFileStatusSettings {
                return "This board will keep using its board-specific palette, but boards that rely on system defaults will no longer have this status."
            }
            return "Boards that rely on system defaults, including this board, will no longer have this status."
        }
    }

    private func revertToSystemDefaultsMessage() -> String {
        let impact = viewModel.revertToSystemDefaultsImpact()
        if impact.affectedNodeCount > 0 {
            return "\(impact.affectedNodeCount) task\(impact.affectedNodeCount == 1 ? "" : "s") on this board use statuses that exist only in the board override. Reverting will switch back to the shared system defaults and clear those assignments.\(sampleTaskSuffix(for: impact))"
        }
        return "This removes the board-specific palette from \(boardFileDescription) and switches the board back to the shared system defaults."
    }

    private func sampleTaskSuffix(for impact: KommitViewModel.StatusSettingsImpact) -> String {
        guard !impact.sampleNodeNames.isEmpty else { return "" }
        let examples = impact.sampleNodeNames.joined(separator: ", ")
        let remainder = impact.affectedNodeCount - impact.sampleNodeNames.count
        if remainder > 0 {
            return "\n\nExamples: \(examples), and \(remainder) more."
        }
        return "\n\nExamples: \(examples)."
    }

}

private struct StatusSettingsEditor: View {
    let statuses: [KommitStatusDefinition]
    let scope: KommitViewModel.StatusSettingsScope
    @ObservedObject var viewModel: KommitViewModel
    let onRemoveStatus: (KommitStatusDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(statuses) { status in
                StatusRow(
                    status: status,
                    scope: scope,
                    viewModel: viewModel,
                    onRemoveStatus: onRemoveStatus
                )
            }

            Button("Add Status") {
                viewModel.addStatus(in: scope)
            }
        }
    }
}

private struct StatusRow: View {
    let status: KommitStatusDefinition
    let scope: KommitViewModel.StatusSettingsScope
    @ObservedObject var viewModel: KommitViewModel
    let onRemoveStatus: (KommitStatusDefinition) -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField(
                "Status name",
                text: Binding(
                    get: { status.name },
                    set: { viewModel.updateStatusName(status.id, name: $0, in: scope) }
                )
            )
            .textFieldStyle(.roundedBorder)

            if status.id == KommitStatusSettings.noneStatusID {
                Text("No color")
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
            } else {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(hex: status.colorHex ?? "0079BF") },
                        set: { viewModel.updateStatusColor(status.id, colorHex: $0.toHex(), in: scope) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 44)

                Text("#\(status.colorHex ?? "0079BF")")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)
            }

            Spacer(minLength: 0)

            if viewModel.canRemoveStatus(status.id) {
                Button(role: .destructive) {
                    onRemoveStatus(status)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
