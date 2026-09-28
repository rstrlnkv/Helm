import Foundation
import SwiftUI

/// **Whose band lies under the settings window's toolbar — Helm's or the
/// system's — decided once, from the running macOS, and handed down as one
/// value.**
///
/// On macOS 27 the band is Helm's: `helmToolbarBackdrop` draws
/// `HeaderEdgeLight` over the pane's top inset, and the window's transparent
/// title bar holds the system's own scroll-edge effect at opacity 0 over that
/// pane (`TheSystemsScrollEdgeEffectAttachesTests` is the measurement). On
/// macOS 26 the owner asked for the system's behaviour back (2026-09-27): the
/// sidebar there is the system's floating glass, and Helm's band ended in a
/// straight edge at its rounded corner (a screenshot from a 26.6.2 virtual
/// machine, not a reading taken here) — so on 26 Helm draws no band under the
/// toolbar and leaves the title bar opaque, which is what lets the system's
/// effect attach to the pane.
///
/// **On 26 the second half is inference, not measurement.** This Mac runs 27,
/// and the reading that an opaque title bar lets the pane's effect draw was
/// taken here; whether macOS 26 draws the same from the same flag is checked
/// by the owner in a 26 virtual machine, not by anything in this tree.
///
/// **One value, read in one place.** `running` is the only reading of the
/// system's version; `SettingsWindow` takes the value as an argument (so a test
/// builds either system's window on this one), sets its title bar from it and
/// hands the same value to its pane through the environment (`helmBandChoice`),
/// where `helmToolbarBackdrop` and `HelmPageHeader` read it. A flag set from
/// one reading and a band drawn from another is a page with two bands or none.
public struct HelmBandChoice: Equatable, Sendable {
    /// Helm's own band under the window's toolbar (`helmToolbarBackdrop`).
    public let toolbarBand: Bool
    /// The same light on a header drawn in the page (`HelmPageHeader`), where
    /// the window has no toolbar to put the header in.
    public let pageHeaderBand: Bool

    /// **Half of the toolbar band's decision, never a separate one.** The
    /// transparent title bar is what withholds the system's effect from the
    /// pane, so it goes with Helm's band and goes when the band goes.
    public var titlebarAppearsTransparent: Bool { toolbarBand }

    /// **The owner's answer (2026-09-27): on macOS 26 the system's edge
    /// everywhere** — the header drawn in the page gives up Helm's band there
    /// as well, so on 26 no `HeaderEdgeLight` is drawn in either page-bar
    /// style; 27 keeps it in both. `true` would keep the in-page header's band
    /// on 26; this line is the whole switch.
    static let pageHeaderBandOn26 = false

    /// The decision for a system's major version: Helm's band from 27 on, the
    /// system's below it — 26 is the oldest system Helm ships to.
    public static func onMacOS(_ major: Int) -> HelmBandChoice {
        let helmsToolbarBand = major >= 27
        return HelmBandChoice(toolbarBand: helmsToolbarBand,
                              pageHeaderBand: helmsToolbarBand || pageHeaderBandOn26)
    }

    /// The running system's decision — the one place its version is read.
    public static let running = onMacOS(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
}

public extension EnvironmentValues {
    /// The band decision the views below draw by. `SettingsWindow` sets its
    /// own; a view outside it — a sheet, another window — reads the running
    /// system's.
    @Entry var helmBandChoice: HelmBandChoice = .running
}
