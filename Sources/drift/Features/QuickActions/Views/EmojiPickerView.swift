import SwiftUI

/// Shows an emoji grid that mirrors to the same corner as the surrounding overlay surface.
struct EmojiPickerView: View {
    /// Emoji items to display in the grid.
    let items: [QuickActionItem]
    /// Horizontal flow direction used to anchor the picker.
    let horizontalFlow: MasonryHorizontalFlow
    /// Vertical flow direction used to order and anchor the picker.
    let verticalFlow: MasonryVerticalFlow

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 6)

        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.53, green: 0.31, blue: 0.78).opacity(0.7))

                Text("Search")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(red: 0.53, green: 0.31, blue: 0.78).opacity(0.72))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.white.opacity(0.08), in: Capsule())

            LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
                ForEach(orderedItems) { item in
                    Button {} label: {
                        Text(item.title)
                            .font(.system(size: 25))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(width: 258, height: 328, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 10)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: stackAlignment)
    }

    /// Items ordered so the first candidate stays closest to the cursor-side origin.
    private var orderedItems: [QuickActionItem] {
        // Reversing the grid keeps the first selectable item closest to the cursor-side origin.
        verticalFlow == .bottomToTop ? Array(items.reversed()) : items
    }

    /// Alignment that pins the picker to the active overlay corner.
    private var stackAlignment: Alignment {
        switch (horizontalFlow, verticalFlow) {
        case (.leftToRight, .topToBottom): return .topLeading
        case (.leftToRight, .bottomToTop): return .bottomLeading
        case (.rightToLeft, .topToBottom): return .topTrailing
        case (.rightToLeft, .bottomToTop): return .bottomTrailing
        }
    }
}
