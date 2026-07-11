import SwiftUI

/// Shared type roles used by drift UI surfaces.
enum DriftTypography {
    /// Prominent HUD section titles.
    static let hudTitle: Font = .system(size: 22, weight: .semibold)
    /// Primary text in HUD action buttons.
    static let hudAction: Font = .system(size: 16, weight: .semibold)
    /// Icons inside HUD action buttons.
    static let hudActionIcon: Font = .system(size: 14, weight: .semibold)
    /// Labels for editable HUD fields.
    static let hudFieldLabel: Font = .system(size: 16, weight: .regular)
    /// Duration values inside compact HUD fields.
    static let hudFieldValue: Font = .system(size: 14, weight: .medium)
    /// Icons paired with compact HUD field values.
    static let hudFieldIcon: Font = .system(size: 14, weight: .medium)
    /// Small icon-only controls inside compact HUD fields.
    static let hudInlineControlIcon: Font = .system(size: 13, weight: .semibold)
    /// Large icon text in the Timer HUD control capsule.
    static let timerControlIcon: Font = .system(size: 22, weight: .semibold)
    /// Large duration value in the Timer HUD control capsule.
    static let timerControlValue: Font = .system(size: 22, weight: .medium)
    /// Duration rail number labels.
    static let timerRailNumber: Font = .system(size: 20)
    ///
    static let hudMiniText: Font = .system(size: 10)
    ///
    ///
}
