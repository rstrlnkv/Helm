import Foundation
import SwiftUI

/// **Whose band lies under the settings window's header row — Helm's or the system's — decided once, from
/// the running macOS, and handed down as one value.**
///
/// On macOS 27 the band is Helm's: `HeaderEdgeLight` over the row (`HelmPageHeader`). On macOS 26 the owner
/// asked for the system's behaviour back (2026-09-27): the sidebar there is the system's floating glass, and
/// Helm's band ended in a straight edge at its rounded corner (a screenshot from a 26.6.2 virtual machine, not
/// a reading taken here) — so on 26 `pageHeaderBand` is false and no band is drawn under the row.
///
/// **What the window does with it now.** `SettingsWindow` reads `running` once and hands the same value to
/// its pane through the environment (`helmBandChoice`), where `HelmPageHeader` reads `pageHeaderBand`. It no
/// longer sets its title bar from it: the title bar is transparent on every system
/// (`titlebarAppearsTransparent = true`, `SettingsWindow.init`), so the owner's 26 decision that the title bar
/// stays opaque there is not carried out; that is open with the owner.
///
/// **On 26 the whole is inference, not measurement.** This Mac runs 27; whether macOS 26 looks as described
/// is checked by the owner in a 26 virtual machine, not by anything in this tree.
///
/// **One value, read in one place.** `running` is the only reading of the system's version the band is decided
/// from (the window's corner reads its own, which is no band); a flag set from
/// one reading and a band drawn from another is a page with two bands or none.
public struct HelmBandChoice: Equatable, Sendable {
    /// Helm's own light on the header row (`HelmPageHeader`).
    public let pageHeaderBand: Bool

    /// **The owner's answer (2026-09-27): on macOS 26 the system's edge
    /// everywhere** — the header drawn in the page gives up Helm's band there
    /// too, so on 26 no `HeaderEdgeLight` is drawn; 27 keeps it. `true` would keep the in-page header's band
    /// on 26; this line is the whole switch.
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

public extension EnvironmentValues {
    /// The band decision the views below draw by. `SettingsWindow` sets its
    /// own; a view outside it — a sheet, another window — reads the running
    /// system's.
    @Entry var helmBandChoice: HelmBandChoice = .running
}
