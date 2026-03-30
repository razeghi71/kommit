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

    package init(viewModel: KommitViewModel) {
        self.viewModel = viewModel
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
        .frame(minWidth: 640, minHeight: 440)
        .background(AppColors.canvasBackgroundSwiftUI)
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
            VStack(alignment: .leading, spacing: 20) {
                Text("Tasks")
                    .font(.title2.weight(.semibold))

                GroupBox("System-Level Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("These statuses are used by default across boards unless a file adds its own override.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        StatusSettingsEditor(
                            statuses: viewModel.systemStatusSettings.statusPalette,
                            forFileSettings: false,
                            viewModel: viewModel
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("File-Level Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let fileSettings = viewModel.fileStatusSettings {
                            Text(fileSettingsDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            StatusSettingsEditor(
                                statuses: fileSettings.statusPalette,
                                forFileSettings: true,
                                viewModel: viewModel
                            )

                            Button("Remove File-Level Settings", role: .destructive) {
                                viewModel.removeFileStatusSettings()
                            }
                        } else {
                            Text("Start from the current system settings, then change them just for this board. File-level settings are written into the JSON document.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button("Add File-Level Settings") {
                                viewModel.addFileStatusSettings()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var financialPlaceholderPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Financial")
                    .font(.title2.weight(.semibold))

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

    private var fileSettingsDescription: String {
        if let currentFileURL = viewModel.currentFileURL {
            return "These statuses apply only to `\(currentFileURL.lastPathComponent)` and are saved inside that JSON file."
        }
        return "These statuses apply only to the current board and will be saved into the JSON file when you save it."
    }
}

private struct StatusSettingsEditor: View {
    let statuses: [KommitStatusDefinition]
    let forFileSettings: Bool
    @ObservedObject var viewModel: KommitViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(statuses) { status in
                StatusRow(
                    status: status,
                    forFileSettings: forFileSettings,
                    viewModel: viewModel
                )
            }

            Button("Add Status") {
                viewModel.addStatus(forFileSettings: forFileSettings)
            }
        }
    }
}

private struct StatusRow: View {
    let status: KommitStatusDefinition
    let forFileSettings: Bool
    @ObservedObject var viewModel: KommitViewModel

    var body: some View {
        HStack(spacing: 12) {
            TextField(
                "Status name",
                text: Binding(
                    get: { status.name },
                    set: { viewModel.updateStatusName(status.id, name: $0, forFileSettings: forFileSettings) }
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
                        set: { viewModel.updateStatusColor(status.id, colorHex: $0.toHex(), forFileSettings: forFileSettings) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 44)

                Text("#\(status.colorHex ?? "0079BF")")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 86, alignment: .leading)
            }

            Spacer(minLength: 0)

            if viewModel.canRemoveStatus(status.id) {
                Button(role: .destructive) {
                    viewModel.removeStatus(status.id, forFileSettings: forFileSettings)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
