import SwiftUI

/// Chooses the visible Quick Actions section and renders the swipe-progress indicator over it.
struct QuickActionSurface: View {
    @ObservedObject var clipboardHistory: ClipboardHistoryStore
    let section: QuickActionSection
    let progress: Double
    let horizontalFlow: MasonryHorizontalFlow
    let verticalFlow: MasonryVerticalFlow
    let numberOfSections: Int

    var body: some View {
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(contentPadding)

            SectionProgressOrb(section: section, progress: progress, numberOfSections: numberOfSections)
                .frame(width: 50, height: 50)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: orbAlignment)
        }
    }

    @ViewBuilder
    private var content: some View {
        // Both sections receive the same flow information so they follow the cursor-side placement.
        switch section {
        case .clipboard:
            ClipboardHistoryView(
                history: clipboardHistory,
                horizontalFlow: horizontalFlow,
                verticalFlow: verticalFlow
            )
        case .emoji:
            EmojiPickerView(
                items: section.items,
                horizontalFlow: horizontalFlow,
                verticalFlow: verticalFlow
            )
        }
    }

    private var contentPadding: EdgeInsets {
        let topInset: CGFloat = verticalFlow == .topToBottom ? 65 : 0
        let bottomInset: CGFloat = verticalFlow == .bottomToTop ? 65 : 0
        return EdgeInsets(top: topInset, leading: 0, bottom: bottomInset, trailing: 0)
    }

    private var orbAlignment: Alignment {
        switch (horizontalFlow, verticalFlow) {
        case (.leftToRight, .topToBottom): return .topLeading
        case (.leftToRight, .bottomToTop): return .bottomLeading
        case (.rightToLeft, .topToBottom): return .topTrailing
        case (.rightToLeft, .bottomToTop): return .bottomTrailing
        }
    }
}

private struct SectionProgressOrb: View {
    let section: QuickActionSection
    let progress: Double
    let numberOfSections: Int
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .background {
                    Circle()
                        .fill(Color(red: 0.06, green: 0.04, blue: 0.13).opacity(0.72))
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.4)
                }
                .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 14)

            Circle()
                .trim(from: 0, to: max(0.005, min(1.0, (progress*Double(numberOfSections)).truncatingRemainder(dividingBy: 1))))
                .stroke(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(3)

            Image(systemName: section.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(section.title)
    }
}
