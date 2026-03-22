import SwiftUI

package struct SettingsView: View {
    @ObservedObject package var viewModel: DominoViewModel

    package init(viewModel: DominoViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        }
        .frame(minWidth: 560, minHeight: 440)
        .background(AppColors.canvasBackgroundSwiftUI)
    }

    private var fileSettingsDescription: String {
        if let currentFileURL = viewModel.currentFileURL {
            return "These statuses apply only to `\(currentFileURL.lastPathComponent)` and are saved inside that JSON file."
        }
        return "These statuses apply only to the current board and will be saved into the JSON file when you save it."
    }
}

private struct StatusSettingsEditor: View {
    let statuses: [DominoStatusDefinition]
    let forFileSettings: Bool
    @ObservedObject var viewModel: DominoViewModel

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
    let status: DominoStatusDefinition
    let forFileSettings: Bool
    @ObservedObject var viewModel: DominoViewModel

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

            if status.id == DominoStatusSettings.noneStatusID {
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
