import SwiftUI

public extension View {
    /// The kit's part of a hosting root: the roots of the Settings window, `HostWindow.present`, the
    /// menu-bar panel and Screenshots' after-shot window carry it. The environment stops at each root (an `NSHostingView` or
    /// `NSHostingController` starts a fresh one), so a root that lacks it draws its plain `Button`s and
    /// `Toggle`s in the system's look, not Helm's. The Screenshots capture hosts (the capture overlay's
    /// editor bar and the capture panel) keep their own drawing and do not carry it; the toast does. A root may
    /// also carry what is its own: the Settings roots add `RebuiltOnLanguageChange` and `TellsWindowActivity` (`SettingsWindow.swift`).
    ///
    /// - the accessibility tracker (`helmTracksAccessibilityDisplay()`), which keeps `\.helmTraits` current;
    /// - `HelmButtonStyle` and `HelmToggleStyle`. A style set on the control itself wins over these.
    func helmRoot() -> some View {
        helmTracksAccessibilityDisplay()
            .buttonStyle(HelmButtonStyle())
            .toggleStyle(HelmToggleStyle())
    }
}
