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

    private var entries: [HostsFile.Entry] { hvm.entries }
    private var off: Int { entries.filter { !$0.enabled }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            Text(HostsStr.moduleName)
                .font(HelmText.rowTitle)
            if hvm.readable {
                Text(hostsLine)
                    // The panel's scale rather than the settings window's, the
                    // way every tile in this app draws its detail.
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
            } else {
                Text(HostsStr.unreadable)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
            }
            Text(keysLine)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmPanelCard()
    }

    /// «12 entries · 3 off», and the second half only when there is one: a
    /// «· 0 off» is a fact nobody needed and a line that never settles.
    private var hostsLine: String {
        let counted = Plural.entries(entries.count, language: AppLanguage.current.rawValue)
        guard off > 0 else { return counted }
        return counted + " · " + HostsStr.entriesOff(off)
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
