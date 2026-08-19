import AppKit
import SwiftUI
import HelmUI
import Module_Hosts_Engine

/// Tab 3: one row per key pair in `~/.ssh`.
///
/// A list of cards rather than a `Table`, because a row here is not four values
/// in four columns — it is a name, what `ssh-keygen` said about it, a verdict
/// that may carry a button, and a control for the agent. The hosts tab's table
/// is a grid because its rows really are three fields wide.
struct KeysTable: View {
    @ObservedObject var hvm: HostsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            agentLine
            if case .tooOpen = hvm.directoryPermission { directoryLine }
            ForEach(hvm.keys) { row in
                KeyCard(hvm: hvm, row: row)
            }
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s3)
    }

    /// **The agent's own sentence, above the rows.** Three states, and the one
    /// that matters is «no agent»: the controls on every row below are dead
    /// while it holds, and a page that only drew empty badges would leave a
    /// person pressing them.
    private var agentLine: some View {
        HStack(spacing: HelmSpace.s2) {
            Text(agentSaid)
                .font(HelmText.rowTitle)
                .foregroundStyle(.secondary)
            Spacer()
            Button(HostsStr.agentCheck) { Task { await hvm.refreshAgent() } }
                .buttonStyle(.link)
        }
    }

    /// Exhaustive over the port's three answers, with no `default`.
    private var agentSaid: String {
        switch hvm.agent {
        case .holding: return HostsStr.agentHolding
        case .empty: return HostsStr.agentEmpty
        case .unreachable: return HostsStr.agentMissing
        }
    }

    /// The directory's own verdict and its own fix. Drawn only when it is too
    /// open: a row saying «this folder is fine» is a row nobody needs, and the
    /// page is a list of keys.
    private var directoryLine: some View {
        HelmBanner(HostsStr.directoryTooOpen) {
            Button(HostsStr.fixPermissions) { Task { await hvm.fixDirectoryPermissions() } }
                .disabled(hvm.busyKey != nil)
        }
    }
}

/// One key.
private struct KeyCard: View {
    @ObservedObject var hvm: HostsViewModel
    let row: KeyRow

    /// This row's own controls go quiet while its own act runs — not the
    /// page's. A page-wide flag would disable four keys because one `chmod` is
    /// in flight.
    @State private var passphrase = ""

    private var busy: Bool { hvm.busyKey == row.name }
    private var anyBusy: Bool { hvm.busyKey != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            HStack(spacing: HelmSpace.s2) {
                Text(row.name).font(.headline)
                if let described = row.described {
                    HelmBadge(described.type)
                    Text("\(described.bits)").font(HelmText.rowDetail).foregroundStyle(.secondary)
                }
                if row.inAgent { HelmBadge(HostsStr.inAgent, tint: .green) }
                Spacer()
                if let modified = row.modified {
                    Text(HelmDates.relative(modified))
                        .font(HelmText.rowDetail)
                        .foregroundStyle(.secondary)
                }
            }

            if let described = row.described {
                Text(described.fingerprint)
                    .font(HelmText.figureFont)
                    .textSelection(.enabled)
                    .accessibilityLabel(HostsStr.keyFingerprint)
                if !described.comment.isEmpty {
                    Text(described.comment).font(HelmText.rowDetail).foregroundStyle(.secondary)
                }
            } else {
                // No `.pub` to read, or a line this build could not parse.
                // Said rather than drawn as blank columns: a fingerprint column
                // that is empty because the parse failed and one that is empty
                // because the key has no comment are different facts.
                Text(row.hasPublicHalf ? HostsStr.keyUnreadable : HostsStr.noPublicHalf)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(.secondary)
            }

            verdict
            controls
            passphraseField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmCard()
        .opacity(busy ? 0.5 : 1)
    }

    /// Exhaustive over the three answers, with no `default` — «unknown» has its
    /// own sentence and offers no button, because a `chmod` over a file nobody
    /// could `stat` is a guess about somebody's key.
    @ViewBuilder private var verdict: some View {
        switch row.permission {
        case .ok:
            EmptyView()
        case .unknown:
            Text(HostsStr.keyModeUnknown).font(HelmText.rowDetail).foregroundStyle(.secondary)
        case .tooOpen:
            HStack(spacing: HelmSpace.s2) {
                Text(HostsStr.keyTooOpen).font(HelmText.rowDetail).foregroundStyle(.orange)
                Button(HostsStr.fixPermissions) {
                    Task { await hvm.fixPermissions(of: row.name) }
                }
                .disabled(anyBusy)
            }
        }
    }

    /// The field the row opens when `ssh-add` has asked.
    ///
    /// **In the row, not in a sheet.** The question belongs to one key, and a
    /// sheet would take the fingerprint and the name off the screen at the
    /// moment somebody needs to be sure which key they are unlocking.
    @ViewBuilder private var passphraseField: some View {
        if hvm.askingFor == row.name {
            VStack(alignment: .leading, spacing: HelmSpace.s2) {
                Text(hvm.passphraseRefused ? HostsStr.passphraseRefused : HostsStr.keyIsLocked)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(hvm.passphraseRefused ? .orange : HelmText.quiet)
                HStack(spacing: HelmSpace.s2) {
                    SecureField(HostsStr.keyPassphrase, text: $passphrase)
                        .frame(maxWidth: 240)
                        .onSubmit { unlock() }
                    Button(HostsStr.unlockAndAdd) { unlock() }
                        .disabled(passphrase.isEmpty || anyBusy)
                    Button(HostsStr.cancel) {
                        passphrase = ""
                        hvm.stopAsking()
                    }
                }
            }
        }
    }

    /// The typed answer is dropped as soon as it has been handed over, whatever
    /// came back. It is a `String` because `SecureField` binds to nothing else —
    /// the boundary `HostsViewModel.load` states.
    private func unlock() {
        let given = passphrase
        passphrase = ""
        Task { await hvm.load(row.name, passphrase: given) }
    }

    private var controls: some View {
        HStack(spacing: HelmSpace.s2) {
            // **The direction is read off the row**, so the word on the button
            // is the word for what pressing it does. A control deciding from
            // its own state would offer to add a key that is already in.
            Button(row.inAgent ? HostsStr.removeFromAgent : HostsStr.addToAgent) {
                Task { await hvm.setInAgent(row) }
            }
            // Dead while there is no agent, and the sentence above says why —
            // a button that cannot work is worse than none.
            .disabled(anyBusy || hvm.agent == .unreachable)

            if let text = row.publicText {
                // No engine command: the public half is public, it travels in
                // the state, and the copy is a pasteboard write here.
                Button(HostsStr.copyPublicKey) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(anyBusy)
            }
            Spacer()
        }
    }
}
