import AppKit
import SwiftUI

enum ThumbnailType {
    case small
    case `default`
}

struct ThumbnailView: View {
    let record: ExcalidrawDocumentRecord
    var type: ThumbnailType = .default;

    @Environment(\.colorScheme) private var colorScheme

    private var size: CGSize {
        switch type {
        case .small:
            return CGSize(width: 20, height: 20)
        case .default:
            return CGSize(width: ExcalidrawHUDStyle.thumbnailSize.width, height: ExcalidrawHUDStyle.thumbnailSize.width)
        }
    }

    private var cornerRadius: CGFloat {
        switch type {
        case .small:
            3
        case .default:
            9
        }
    }

    var body: some View {
        if let thumbnailURL = record.thumbnailURL(resolvedTheme: resolvedTheme),
           let image = NSImage(contentsOf: thumbnailURL) {
            thumbnailImage(image)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.2))
                .frame(width: size.width, height: size.width)
                .overlay {
                    Image(systemName: "scribble.variable")
                        .font(DriftTypography.hudActionIcon)
                        .foregroundStyle(Color.excalidrawAccent)
                }
        }
    }

    private var resolvedTheme: ExcalidrawResolvedTheme {
        let systemTheme: ExcalidrawResolvedTheme = colorScheme == .dark ? .dark : .light
        return record.preferredTheme.resolved(systemTheme: systemTheme)
    }

    @ViewBuilder
    private func thumbnailImage(_ image: NSImage) -> some View {
        let imageView = Image(nsImage: image)
            .resizable()
            .scaledToFill()

        if resolvedTheme == .dark {
            imageView
                .colorInvert()
                .contrast(0.86)
                .hueRotation(.degrees(180))
                .frame(width: size.width, height: size.width)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            imageView
                .frame(width: size.width, height: size.width)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
