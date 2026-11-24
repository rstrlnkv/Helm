import SwiftUI

/// Which pointer state a kit control draws: the live one, or one forced for a screen that has to show it.
///
/// `HelmShowcase` is the only consumer of the other two values. A hover or a press cannot be held on a
/// screen for a photograph, and a control that was not drawn in a state was never checked in it, so the
/// showcase sets `.hover` or `.pressed` on a column and `HelmButtonStyle`, `HelmSidebarRow` and
/// `HelmPageHeader` draw as if the pointer were there. Nothing else sets it; the default `.live` leaves every
/// control answering the real pointer.
public enum HelmInteraction: Sendable {
    case live, hover, pressed
}

extension EnvironmentValues {
    @Entry public var helmShownInteraction: HelmInteraction = .live
}
