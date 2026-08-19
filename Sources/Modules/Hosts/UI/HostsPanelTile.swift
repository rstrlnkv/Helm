import SwiftUI
import HelmRuntime
import HelmUI
import Module_Hosts_Engine

/// The panel tile: three counts and no controls.
///
/// **Read-only, and that is a decision rather than an omission.** A hosts toggle
/// in the menu-bar panel would be a macOS password dialog raised from the menu
/// bar, and a password dialog needs a gesture that asked for it — «I opened the
/// panel» is not that gesture. The keys have the same shape one step along: a
/// `chmod` is cheap, but the row that would carry it is the row the person came
/// to read.
///
/// What it says is what a person opens the panel to find out: how many mappings
/// are in the file, how many of them are switched off, how many keys are in
/// `~/.ssh`, and whether the agent is holding anything — the last being the one
/// that changes on its own between two glances.
struct HostsPanelTile: View {
    @ObservedObject var hvm: HostsViewModel


    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            Text(HostsStr.moduleName)
                .font(HelmText.rowTitle)
            Text(knownHostsLine)
                // The panel's scale rather than the settings window's, the way
                // every tile in this app draws its detail.
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
            Text(keysLine)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmPanelCard()
    }

    /// **The hosts file's own counts are not here, because its editor is not on
    /// the page.** A tile that counted a file nobody can open from it would be
    /// the app pointing at a door it had taken away. `Plural.entries` and
    /// `HostsStr.entriesOff` are kept for the day the tab comes back.
    private var knownHostsLine: String {
        hvm.knownHostsReadable
            ? Plural.hosts(hvm.knownHosts.count, language: AppLanguage.current.rawValue)
            : HostsStr.knownHostsUnreadable
    }

    /// The keys, and what the agent is doing with them. The agent's sentence is
    /// the module's own — three states, and «no agent» is one of them, because
    /// «0 loaded» over a dead socket is the fold this module refuses everywhere
    /// else.
    private var keysLine: String {
        let counted = hvm.keysReadable
            ? Plural.keys(hvm.keys.count, language: AppLanguage.current.rawValue)
            : HostsStr.keysUnreadable
        switch hvm.agent {
        case .holding(let held): return counted + " · " + HostsStr.agentHolds(held.count)
        case .empty: return counted
        case .unreachable: return counted + " · " + HostsStr.agentMissing
        }
    }
}
