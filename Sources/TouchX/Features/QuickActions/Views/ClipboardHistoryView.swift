import SwiftUI

/// Displays clipboard candidates in a mirrored masonry layout that follows the overlay direction.
struct ClipboardHistoryView: View {
    @ObservedObject var history: ClipboardHistoryStore
    let horizontalFlow: MasonryHorizontalFlow
    let verticalFlow: MasonryVerticalFlow

    var body: some View {
        GeometryReader { proxy in
            let layout = masonryLayout(
                items: history.items,
                availableWidth: proxy.size.width,
                availableHeight: proxy.size.height
            )

            ZStack(alignment: .topLeading) {
                if history.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clipboard")
                            .font(.system(size: 28))
                        Text("No clipboard history yet")
                            .font(.headline)
                        Text("Copy text while TouchX is running to see it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(layout.placements) { placement in
                        ClipboardHistoryCard(item: placement.item) {
                            history.copyToPasteboard(placement.item)
                        }
                        .frame(width: placement.width, height: placement.height)
                        .position(
                            x: placement.x + placement.width / 2,
                            y: placement.y + placement.height / 2
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func masonryLayout(
        items: [ClipboardHistoryItem],
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> MasonryLayout {
        let gap: CGFloat = 20
        let columnCount = availableWidth >= 560 ? 2 : 1
        let columnWidth = columnCount == 1 ? min(360, availableWidth) : min(340, (availableWidth - gap) / 2)
        let columnsWidth = CGFloat(columnCount) * columnWidth + CGFloat(max(0, columnCount - 1)) * gap
        let startX: CGFloat

        switch horizontalFlow {
        case .leftToRight:
            startX = 0
        case .rightToLeft:
            startX = max(0, availableWidth - columnsWidth)
        }

        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)
        var placements: [MasonryPlacement] = []

        for item in items {
            let logicalColumn = columnHeights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            let cardHeight = height(for: item)
            let naturalColumn = horizontalFlow == .rightToLeft
                ? columnCount - 1 - logicalColumn
                : logicalColumn
            let x = startX + CGFloat(naturalColumn) * (columnWidth + gap)
            let y = columnHeights[logicalColumn]

            placements.append(MasonryPlacement(item: item, x: x, y: y, width: columnWidth, height: cardHeight))
            columnHeights[logicalColumn] += cardHeight + gap
        }

        let naturalHeight = max(columnHeights.max() ?? 0, availableHeight)
        // Reverse the final coordinates instead of reversing input order to preserve column balancing.
        let finalPlacements = placements.map { placement in
            guard verticalFlow == .bottomToTop else { return placement }
            var reversed = placement
            reversed.y = naturalHeight - placement.y - placement.height
            return reversed
        }

        return MasonryLayout(placements: finalPlacements, contentHeight: naturalHeight)
    }

    private func height(for item: ClipboardHistoryItem) -> CGFloat {
        switch item.text.count {
        case ..<54:
            return 52
        case ..<120:
            return 76
        default:
            return 104
        }
    }
}

/// A compact, multiline preview card for one clipboard candidate.
private struct ClipboardHistoryCard: View {
    let item: ClipboardHistoryItem
    let copy: () -> Void

    var body: some View {
        Button(action: copy) {
            textPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var textPreview: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(width: 18)

            Text(item.text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.77))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
