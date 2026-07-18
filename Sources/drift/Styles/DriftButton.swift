import SwiftUI

/// Shared button variants used by drift UI surfaces.
enum DriftButtonVariant {
    /// High-emphasis HUD action button.
    case hudPrimary
    /// Neutral HUD action button.
    case hudSecondary
    /// Destructive HUD action button.
    case hudDestructive
    /// Icon-only inline HUD control.
    case hudInlineIcon
    
    case hudDark

    /// Button text or symbol font.
    var font: Font {
        switch self {
        case .hudPrimary, .hudSecondary, .hudDestructive, .hudDark:
            DriftTypography.hudAction
        case .hudInlineIcon:
            DriftTypography.hudInlineControlIcon
        }
    }

    /// Symbol font for buttons that pair an icon with text.
    var pairedIconFont: Font {
        switch self {
        case .hudPrimary, .hudSecondary, .hudDestructive, .hudDark:
            DriftTypography.hudActionIcon
        case .hudInlineIcon:
            DriftTypography.hudInlineControlIcon
        }
    }

    /// Foreground style for button content.
    var foreground: Color {
        switch self {
        case .hudPrimary, .hudInlineIcon, .hudDark:
            Color.white
        case .hudSecondary:
            Color.white
        case .hudDestructive:
            Color.red
        }
    }

    /// Background fill for the button.
    @ViewBuilder
    var background: some View {
        switch self {
        case .hudPrimary:
            Color.accentColor
        case .hudSecondary:
            Color.white.opacity(0.12)
        case .hudDestructive:
            Color.red.opacity(0.25)
        case .hudInlineIcon:
            Color.clear
        case .hudDark:
            Color.black
        }
    }

    /// Whether the button should use a capsule clipping shape.
    var clipsToCapsule: Bool {
        switch self {
        case .hudPrimary, .hudSecondary, .hudDestructive, .hudDark:
            true
        case .hudInlineIcon:
            false
        }
    }

    /// Default size used when the call site does not request one.
    var defaultSize: DriftButtonSize {
        switch self {
        case .hudPrimary, .hudSecondary, .hudDestructive, .hudDark:
            .default
        case .hudInlineIcon:
            .inlineIcon
        }
    }
}

/// Standard button sizes.
enum DriftButtonSize {
    /// Default HUD action button size.
    case `default`
    /// Compact icon-only button size.
    case inlineIcon

    /// Button height.
    var height: CGFloat {
        switch self {
        case .default:
            35
        case .inlineIcon:
            20
        }
    }
}

/// Position for a button icon relative to its title.
enum DriftButtonIconPosition {
    /// Render the icon before the title.
    case front
    /// Render the icon after the title.
    case back
}

/// Reusable drift button with stable visual variants.
struct DriftButton: View {
    /// Visual treatment for the button.
    let variant: DriftButtonVariant
    /// Size treatment for the button.
    let size: DriftButtonSize
    /// Optional text title.
    let title: String?
    /// Optional SF Symbol name.
    let systemImage: String?
    /// Position for the icon when both title and icon are present.
    let iconPosition: DriftButtonIconPosition
    /// Optional content font override.
    let font: Font?
    /// Optional paired icon font override.
    let iconFont: Font?
    /// Optional fixed width.
    let width: CGFloat?
    /// Optional fixed height.
    let height: CGFloat?
    /// Optional maximum width.
    let maxWidth: CGFloat?
    /// Action to run when tapped.
    let action: () -> Void

    /// Creates a drift button.
    init(
        variant: DriftButtonVariant,
        size: DriftButtonSize? = nil,
        title: String? = nil,
        systemImage: String? = nil,
        iconPosition: DriftButtonIconPosition = .front,
        font: Font? = nil,
        iconFont: Font? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.variant = variant
        self.size = size ?? variant.defaultSize
        self.title = title
        self.systemImage = systemImage
        self.iconPosition = iconPosition
        self.font = font
        self.iconFont = iconFont
        self.width = width
        self.height = height
        self.maxWidth = maxWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            content
                .font(font ?? variant.font)
                .foregroundStyle(variant.foreground)
                .frame(width: width)
                .frame(maxWidth: maxWidth)
                .frame(height: height ?? size.height)
                .background(variant.background)
                .modifier(DriftButtonCapsuleModifier(enabled: variant.clipsToCapsule))
        }
        .buttonStyle(DriftButtonNoAnimationStyle())
    }

    /// Renders the configured title and/or icon.
    @ViewBuilder
    private var content: some View {
        switch (title, systemImage) {
        case (.some(let title), .some(let systemImage)):
            Label(title, systemImage: systemImage)
                .labelStyle(
                    DriftButtonIconPositionLabelStyle(
                        position: iconPosition,
                        spacing: 5,
                        iconFont: iconFont ?? variant.pairedIconFont
                    )
                )
        case (.some(let title), .none):
            Text(title)
        case (.none, .some(let systemImage)):
            Image(systemName: systemImage)
        case (.none, .none):
            EmptyView()
        }
    }
}

/// Label style that renders an icon before or after the title.
private struct DriftButtonIconPositionLabelStyle: LabelStyle {
    /// Icon position relative to the title.
    let position: DriftButtonIconPosition
    /// Space between title and icon.
    let spacing: CGFloat
    /// Font used by the icon.
    let iconFont: Font

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch position {
        case .front:
            HStack(spacing: spacing) {
                configuration.icon
                    .font(iconFont)
                configuration.title
            }
        case .back:
            HStack(spacing: spacing) {
                configuration.title
                configuration.icon
                    .font(iconFont)
            }
        }
    }
}

/// Conditionally clips button content to a capsule.
private struct DriftButtonCapsuleModifier: ViewModifier {
    /// Whether clipping should be applied.
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.clipShape(Capsule())
        } else {
            content
        }
    }
}

/// Button style that disables default pressed opacity and animation changes.
private struct DriftButtonNoAnimationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
            .animation(nil, value: configuration.isPressed)
    }
}
