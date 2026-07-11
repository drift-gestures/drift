import SwiftUI

struct ExcalidrawLauncherContent: View {
    let launcherItems: [LauncherItem]
    @Binding var selectedLauncherIndex: Int
    let execute: (LauncherItem) -> Void

    var body: some View {
        HStack(spacing: ExcalidrawHUDStyle.spacing) {
            ForEach(Array(launcherItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    selectedLauncherIndex = index
                    execute(item)
                } label: {
                    LauncherItemView(
                        item: item,
                        isSelected: index == selectedLauncherIndex
                    )
                    if (index == 1 && index != launcherItems.count - 1) {
                        Rectangle()
                            .background(.white.opacity(0.1))
                            .cornerRadius(.infinity)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 15)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding([.vertical, .horizontal], ExcalidrawHUDStyle.padding)
        .frame(maxHeight: ExcalidrawHUDStyle.launcherSize.height)
        .cornerRadius(ExcalidrawHUDStyle.cornerRadius)
        .glassEffect(.regular ,in: .rect(cornerRadius: ExcalidrawHUDStyle.cornerRadius))
        .frame(maxWidth: ExcalidrawHUDStyle.launcherSize.width, maxHeight: ExcalidrawHUDStyle.launcherSize.height)
    }
}

struct LauncherItem: Identifiable {
    enum Action: Equatable {
        case search
        case new
        case open(String)
    }

    var id: String {
        switch action {
        case .search: "search"
        case .new: "new"
        case .open(let id): id
        }
    }

    let action: Action
    let title: String
    let systemImage: String?
    let record: ExcalidrawDocumentRecord?
}

struct LauncherItemView: View {
    let item: LauncherItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                if let record = item.record {
                    ThumbnailView(record: record)
                } else if let systemImage = item.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 37, weight: .semibold))
                        .foregroundStyle(Color.excalidrawAccent)
                }
            }
            .frame(width: ExcalidrawHUDStyle.itemSize.width, height: ExcalidrawHUDStyle.itemSize.height)

            Text(item.title)
                .font(DriftTypography.hudMiniText)
                .lineLimit(1)
                .frame(width: ExcalidrawHUDStyle.itemSize.width)
        }
        .foregroundStyle(.primary)
        .frame(width: ExcalidrawHUDStyle.itemSize.width, height: ExcalidrawHUDStyle.itemSize.height)
    }
}
