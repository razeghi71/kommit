import SwiftUI

/// Empty-state hub: open a document, start blank, or pick a recent file (VS Code–style orientation).
package struct StartHubView: View {
    @ObservedObject package var viewModel: KommitViewModel

    package init(viewModel: KommitViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        HStack(alignment: .top, spacing: 48) {
            startColumn
                .frame(maxWidth: 360, alignment: .leading)

            Spacer(minLength: 24)

            tipsColumn
                .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.canvasBackgroundSwiftUI)
    }

    private var startColumn: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Kommit")
                    .font(.system(size: 34, weight: .semibold))
                Text("Life planning on a dependency graph")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                hubButton(title: "Open…", systemImage: "folder") {
                    viewModel.confirmDiscardIfNeeded {
                        viewModel.open()
                    }
                }
                hubButton(title: "New blank board", systemImage: "doc.badge.plus") {
                    viewModel.confirmDiscardIfNeeded {
                        viewModel.newBoard(suppressStartHub: true)
                    }
                }
            }

            if !viewModel.recentDocumentURLs().isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent")
                        .font(.headline)
                    ForEach(viewModel.recentDocumentURLs(), id: \.path) { url in
                        Button {
                            viewModel.confirmDiscardIfNeeded {
                                _ = viewModel.openDocument(at: url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                viewModel.openSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private var tipsColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Get started")
                .font(.title2.weight(.semibold))

            tipRow(icon: "hand.tap", text: "Double-click the canvas to create a task.")
            tipRow(icon: "link", text: "Drag from a task’s + buttons to connect dependencies.")
            tipRow(icon: "square.and.arrow.down", text: "⌘S saves everything—tasks and finances—into one JSON file.")
            tipRow(icon: "command", text: "⌘O to open a file, ⌘F to search tasks.")
        }
    }

    private func hubButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
