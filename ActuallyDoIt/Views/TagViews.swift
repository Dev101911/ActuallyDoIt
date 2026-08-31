//
//  TagViews.swift
//  ActuallyDoIt
//
//  Reusable tag UI shared across the app: a wrapping `FlowLayout`, a capsule `TagChip`, and the
//  `TagEditorField` used to add/remove a task's tags. Keeping these together means the editor, the
//  task rows and the Now filter all present tags consistently.
//

import SwiftUI

// MARK: - Flow layout

/// A simple wrapping layout: lays subviews left-to-right and wraps onto a new line when the next
/// subview would overflow the available width. Used to let tag chips wrap over multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                // Wrap to the next row.
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: proposal.width ?? totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width - bounds.minX > maxWidth {
                // Wrap to the next row.
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Chip

/// A small rounded capsule showing a single tag. When `onRemove` is supplied it shows a trailing
/// "x" so the tag can be deleted (used in the editor); without it the chip is display-only.
struct TagChip: View {
    let text: String
    /// A smaller, tighter chip for dense contexts like task rows.
    var compact: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove tag \(text)")
            }
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 2 : 5)
        .background(.tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Editor field

/// The tag-editing control: the task's current tags as removable chips, a text field to add a new
/// one (commits on submit), and tappable suggestion chips drawn from tags used elsewhere.
struct TagEditorField: View {
    @Binding var tags: [String]
    /// Tags used on other tasks, offered as quick-add suggestions.
    var suggestions: [String]

    @State private var draft = ""
    
    @FocusState private var isTagsFocused: Bool

    /// Suggestions not already applied to this task (case-insensitive).
    private var unusedSuggestions: [String] {
        let applied = Set(tags.map { $0.lowercased() })
        return suggestions.filter { !applied.contains($0.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !tags.isEmpty {
                FlowLayout {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(text: tag) { remove(tag) }
                    }
                }
            }

            TextField("Add a tag (optional)", text: $draft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(commitDraft)
                .focused($isTagsFocused)

            if !unusedSuggestions.isEmpty && isTagsFocused {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayout {
                        ForEach(unusedSuggestions, id: \.self) { suggestion in
                            Button { add(suggestion) } label: {
                                TagChip(text: suggestion)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func commitDraft() {
        if let tag = TaskItem.normalize(draft) {
            add(tag)
        }
        draft = ""
    }

    /// Appends a tag unless an equal one (case-insensitive) is already present.
    private func add(_ tag: String) {
        guard !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        tags.append(tag)
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }
}
