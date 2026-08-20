import AppKit
import SwiftUI
import HelmUI
import Module_Hosts_Engine

/// Tab 1: one row per key pair in `~/.ssh`, and what each key still opens.
///
/// **The rows are lines, not columns.** A fingerprint is 47 characters and a
/// comment is whatever `ssh-keygen` was told; no width can be chosen that
/// survives both at the 490 pt the settings pane comes down to. So a row is
/// built the way a macOS list row is — a title line that truncates last, and
/// detail lines that may truncate freely — and nothing in it is pinned to a
/// number. `HostsRowsFitTheMinimumPaneTests` is what keeps that true.
struct KeysTable: View {
    @ObservedObject var hvm: HostsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            agentLine
            if case .tooOpen = hvm.directoryPermission { directoryLine }
            ForEach(hvm.keys) { row in
                // Named, so a host row on the other tab can scroll to the key
                // it points at rather than leaving somebody to find it.
                KeyCard(hvm: hvm, row: row, usage: hvm.usage(of: row.name))
                    .id(row.name)
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
                .foregroundStyle(HelmText.quiet)
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
    /// **Handed in, never worked out here.** The join is three files wide and
    /// belongs to the whole tab; a row that computed its own share would parse
    /// all three again per row and again on every redraw, with nothing keeping
    /// two rows' answers in step.
    let usage: KeyUsage.OfKey

    /// This row's own controls go quiet while its own act runs — not the
    /// page's. A page-wide flag would disable four keys because one `chmod` is
    /// in flight.
    @State private var passphrase = ""

    private var busy: Bool { hvm.busyKey == row.name }
    private var anyBusy: Bool { hvm.busyKey != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            title
            fingerprintLine
            // **The sentence this whole tab was rebuilt for.** Four states, and
            // «used by default» is not «unused»: `ssh` reaches for `id_ed25519`
            // without being told, so the difference is between «safe to delete»
            // and «this is how you log in».
            Text(HostsStr.usage(of: usage))
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(2)
                .truncationMode(.tail)
                // Selectable for the same reason the fingerprint is — this line
                // lists host names somebody may want to paste — and for a second
                // one worth stating: a plain `Text` leaves no AppKit view, so
                // `HostsRowsFitTheMinimumPaneTests` finds nothing to measure and
                // a fixed width **here** left all three of its cases green. The
                // line the whole tab was rebuilt around was the one line its
                // width guard could not see.
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            verdict
            controls
            passphraseField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmCard()
        .opacity(busy ? 0.5 : 1)
    }

    /// The name, then what `ssh-keygen` said about the key, then the date.
    ///
    /// The name takes the room the badges leave and truncates in the middle —
    /// `id_ed25519_work` and `id_ed25519_home` differ at the end, so a tail
    /// truncation would make two keys look like one. Nothing here is pinned to
    /// a width: the badges are as wide as their words, in eight languages.
    private var title: some View {
        HStack(spacing: HelmSpace.s2) {
            Text(row.name)
                .font(HelmText.sectionHeading)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if let described = row.described {
                HelmBadge(described.type)
                Text("\(described.bits)").font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            }
            if row.inAgent { HelmBadge(HostsStr.inAgent, tint: .green) }
            Spacer(minLength: HelmSpace.s2)
            if let modified = row.modified {
                Text(HelmDates.relative(modified))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
            }
        }
    }

    /// The fingerprint and the comment, on one line that may lose either end.
    ///
    /// **Middle truncation, so both ends stay comparable**: what a person does
    /// with a fingerprint is check it against one somewhere else, and a tail
    /// truncation leaves every SHA-256 line looking identical.
    @ViewBuilder private var fingerprintLine: some View {
        if let described = row.described {
            HStack(spacing: HelmSpace.s2) {
                Text(described.fingerprint)
                    .font(HelmText.figureFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel(HostsStr.keyFingerprint)
                if !described.comment.isEmpty {
                    Text(described.comment)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
        } else {
            // No `.pub` to read, or a line this build could not parse. Said
            // rather than drawn as a blank: a fingerprint that is empty because
            // the parse failed and one that is empty because the key has no
            // comment are different facts.
            Text(row.hasPublicHalf ? HostsStr.keyUnreadable : HostsStr.noPublicHalf)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
        }
    }

    /// Exhaustive over the three answers, with no `default` — «unknown» has its
    /// own sentence and offers no button, because a `chmod` over a file nobody
    /// could `stat` is a guess about somebody's key.
    @ViewBuilder private var verdict: some View {
        switch row.permission {
        case .ok:
            EmptyView()
        case .unknown:
            Text(HostsStr.keyModeUnknown).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
        case .tooOpen(let fix):
            // On the first baseline, because the sentence is the only thing
            // here that wraps: centred, the `chmod` and the button float to the
            // middle of a two-line paragraph at the narrow pane, which is where
            // nothing else on the row sits.
            HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s2) {
                Text(HostsStr.keyTooOpen)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                // **The mode is not translated**, for the reason the four
                // `ssh_config` keywords are not: `chmod 600` is what somebody
                // would type, and a localised spelling of it would teach a
                // command that does not exist. It is carried on the verdict
                // rather than recomputed, so the number on screen and the one
                // the button writes cannot disagree.
                Text(verbatim: "chmod \(String(fix, radix: 8))")
                    .font(HelmText.figureFont)
                    .foregroundStyle(HelmText.quiet)
                    .textSelection(.enabled)
                Button(HostsStr.fixPermissions) {
                    Task { await hvm.fixPermissions(of: row.name) }
                }
                .disabled(anyBusy)
                Spacer(minLength: 0)
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
                    // **No width of its own.** It had one — 240 pt — which at
                    // the narrowest pane took half the row from a card that has
                    // three other controls on this line.
                    SecureField(HostsStr.keyPassphrase, text: $passphrase)
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

    /// The typed answer is dropped as soon as it **has been** handed over,
    /// whatever came back. It is a `String` because `SecureField` binds to
    /// nothing else — the boundary `HostsViewModel.load` states.
    ///
    /// **Cleared after the act was taken, not before it was attempted.** It
    /// used to empty the field first, and `load` opens with a busy gate that
    /// refuses silently — so a second press while the first was in flight lost
    /// what somebody had typed, leaving «this key is locked» over an empty box
    /// with nothing said. The button is disabled while an act runs; the field's
    /// own `onSubmit` is not, so two quick Returns are two presses.
    private func unlock() {
        let given = passphrase
        Task { if await hvm.load(row.name, passphrase: given) { passphrase = "" } }
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
            Spacer(minLength: 0)
        }
    }
}
