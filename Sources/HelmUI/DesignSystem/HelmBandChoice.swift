import Foundation
import SwiftUI

/// **Whose band lies under the settings window's header row — Helm's or the system's — decided once, from
/// the running macOS, and handed down as one value.**
///
/// On macOS 27 the band is Helm's: `HeaderEdgeLight` over the row (`HelmPageHeader`). On macOS 26 the owner
/// chose the system's: the sidebar there is floating glass, and Helm's band ends in a straight edge at its
/// rounded corner. That reading of 26 comes from the owner's 26 virtual machine, not from anything in this tree.
///
/// `SettingsWindow` reads `running` once and hands it to its pane (`helmBandChoice`), where `HelmPageHeader`
/// reads `pageHeaderBand`. The title bar is transparent on every system (`SettingsWindow.init`), so the
/// owner's wish for an opaque title bar on 26 is not carried out; that is open with the owner.
///
/// One value, read in one place: a flag set from one reading of the version and a band drawn from another is
/// a page with two bands or none.
public struct HelmBandChoice: Equatable, Sendable {
    /// Helm's own light on the header row (`HelmPageHeader`).
    let pageHeaderBand: Bool

    /// The owner's answer for macOS 26: the system's edge everywhere, so the header drawn in the page gives up
    /// Helm's band there too. `true` would keep the in-page header's band on 26; this line is the whole switch.
    static let pageHeaderBandOn26 = false

    /// The decision for a system's major version: Helm's band from 27 on, the
    /// system's below it — 26 is the oldest system Helm ships to.
    public static func onMacOS(_ major: Int) -> HelmBandChoice {
        let helmsBand = major >= 27
        return HelmBandChoice(pageHeaderBand: helmsBand || pageHeaderBandOn26)
    }

    /// The running system's decision.
    public static let running = onMacOS(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
}

extension EnvironmentValues {
    /// The band decision the views below draw by. `SettingsWindow` sets its
    /// own; a view outside it — a sheet, another window — reads the running
    /// system's.
    @Entry public var helmBandChoice: HelmBandChoice = .running
}
