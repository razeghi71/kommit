import SwiftUI

/// Welcome window: open a document, start blank, or pick a recent file (launcher-style, separate from the canvas window).
package struct StartHubView: View {
    @ObservedObject package var viewModel: KommitViewModel
    @State private var projectSearch = ""

    package init(viewModel: KommitViewModel) {
        self.viewModel = viewModel
    }

    package var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color.primary.opacity(0.045))

            Divider()

            mainPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppColors.canvasBackgroundSwiftUI)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kommit")
                    .font(.system(size: 20, weight: .semibold))
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            sidebarNavRow(title: "Boards", systemImage: "square.grid.2x2", isSelected: true)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)

            Button {
                viewModel.openSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func sidebarNavRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 20)
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .regular))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
    }

    private var mainPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to Kommit")
                    .font(.title2.weight(.semibold))

                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search recent boards", text: $projectSearch)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .frame(maxWidth: 280)

                    Spacer(minLength: 16)

                    Button {
                        viewModel.confirmDiscardIfNeeded {
                            viewModel.newBoard(suppressStartHub: true)
                        }
                    } label: {
                        Text("New Board")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        viewModel.confirmDiscardIfNeeded {
                            viewModel.open()
                        }
                    } label: {
                        Text("Open…")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            if !filteredRecentURLs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent")
                        .font(.headline)
                        .padding(.horizontal, 28)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(filteredRecentURLs, id: \.path) { url in
                                recentRow(url: url)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 16)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var filteredRecentURLs: [URL] {
        let all = viewModel.recentDocumentURLs()
        let q = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.lastPathComponent.localizedCaseInsensitiveContains(q)
                || $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    private func recentRow(url: URL) -> some View {
        let initials = recentInitials(for: url)
        return Button {
            viewModel.confirmDiscardIfNeeded {
                _ = viewModel.openDocument(at: url)
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Text(initials)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func recentInitials(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split { !($0.isLetter || $0.isNumber) }
        let letters = parts.compactMap { $0.first }.map { String($0) }
        if letters.count >= 2 {
            return (letters[0] + letters[1]).uppercased()
        }
        if let first = name.first {
            return String(first).uppercased()
        }
        return "?"
    }
}
