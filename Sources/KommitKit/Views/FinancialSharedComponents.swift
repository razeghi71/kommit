import SwiftUI

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        computeLayout(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var origins: [CGPoint]
        var size: CGSize
    }

    private func computeLayout(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            maxX = max(maxX, x - horizontalSpacing)
        }

        return LayoutResult(
            origins: origins,
            size: CGSize(width: maxX, height: y + rowHeight)
        )
    }
}

// MARK: - Field Group

struct FieldGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Tag input

struct TagInputField: View {
    @Binding var tags: [String]
    @Binding var input: String
    let suggestions: [String]

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                if !tags.isEmpty {
                    FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                        ForEach(tags, id: \.self) { tag in
                            chip(for: tag)
                        }
                    }
                }

                ZStack(alignment: .leading) {
                    if input.isEmpty {
                        Text(tags.isEmpty ? "Type to add tags…" : "Add another…")
                            .foregroundColor(Color.primary.opacity(0.3))
                            .font(.system(size: 13))
                    }
                    TextField("", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isInputFocused)
                        .onSubmit { addTag(input) }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isInputFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12),
                        lineWidth: isInputFocused ? 2 : 1
                    )
            )
            .padding(1)
            .contentShape(Rectangle())
            .onTapGesture { isInputFocused = true }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button { addTag(suggestion) } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(suggestion)
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func chip(for tag: String) -> some View {
        HStack(spacing: 3) {
            Text(tag)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Button { removeTag(tag) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
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
