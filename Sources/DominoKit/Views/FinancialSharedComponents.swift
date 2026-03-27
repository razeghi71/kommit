import SwiftUI

// MARK: - Tag input

struct TagInputField: View {
    @Binding var tags: [String]
    @Binding var input: String
    let suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.system(size: 12))
                                Button {
                                    removeTag(tag)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
            }

            TextField("Add tag and press Enter", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addTag(input)
                }

            HStack(spacing: 8) {
                Button("Add Tag") {
                    addTag(input)
                }
                .buttonStyle(.bordered)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("You can create new tags here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                addTag(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func addTag(_ rawTag: String) {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = normalizedTagKey(trimmed)
        guard !tags.contains(where: { normalizedTagKey($0) == key }) else {
            input = ""
            return
        }
        tags.append(trimmed)
        input = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { normalizedTagKey($0) == normalizedTagKey(tag) }
    }

    private func normalizedTagKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

// MARK: - Metadata strip

struct FinancialMetadataStrip: View {
    let items: [String]
    var width: CGFloat = 160

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - Helpers

extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
