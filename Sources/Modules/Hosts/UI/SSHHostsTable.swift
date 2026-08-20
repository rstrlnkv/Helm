import SwiftUI
import HelmUI
import Module_Hosts_Engine

/// Tab 2: the hosts of `~/.ssh/config`, each with the key it uses and the
/// fingerprints this Mac has already trusted for it.
///
/// **`known_hosts` is not a tab any more.** A trusted fingerprint is a fact
/// *about a host*, so it belongs on the host's row, with Forget beside it for a
/// host that has changed its key — which is the one job people come to that
/// file for. The lines matching no block in the config gather under one heading
/// at the end, because they are still trusts somebody may want to drop and
/// forgetting is by line.
///
/// **Nothing here is pinned to a width.** The keyword column was 96 pt and the
/// pane comes down to about 490; a `Grid` sizes that column to the longest
/// keyword instead, which is a fact about the word rather than a number
/// somebody chose, and it is right in all eight languages by construction.
struct SSHHostsTable: View {

    @ObservedObject var hvm: HostsViewModel
    /// What the row's key name does when it is pressed: take the person to that
    /// key on the first tab. The page owns which tab is showing, so the act is
    /// handed in rather than reached for.
    let select: (String) -> Void

    var body: some View {
        // **The parse is asked for once.** `sshDocument` re-parses the file on
        // every read, so a body that asked it per block would parse the config
        // as many times as it has hosts — the rule `HostsTable` states next
        // door about its own document.
        let document = hvm.sshDocument
        return VStack(alignment: .leading, spacing: HelmSpace.s5) {
            ForEach(hvm.hostRows) { row in
                block(row, fields: document.fields(ofHost: row.index))
            }
            if hvm.hostRows.isEmpty {
                // Not an error and not an empty file — a config can be nothing
                // but `Include` and `Match`, which this table has no rows for
                // and the text view shows in full.
                Text(HostsStr.noHostBlocks)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
            }
            if !hvm.otherTrusted.isEmpty { other }
        }
        .padding(HelmLayout.formInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The trusts belonging to no block here: most of anybody's `known_hosts`,
    /// and every hashed line, since a hashed line names nobody.
    private var other: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            Text(HostsStr.otherTrustedHosts)
                .font(HelmText.sectionHeading)
            ForEach(hvm.otherTrusted) { entry in
                TrustLine(hvm: hvm, entry: entry, naming: true)
            }
        }
        .padding(HelmSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
            .fill(HelmSurface.wellFill))
    }

    private func block(_ row: SSHHostRows.Row,
                       fields: [SSHConfigFile.Field]) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            title(row)
            detail(row)
            grid(of: fields, ofHost: row.index)
            ForEach(row.trusted) { entry in
                TrustLine(hvm: hvm, entry: entry, naming: false)
            }
        }
        .padding(HelmSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
            .fill(HelmSurface.wellFill))
    }

    /// The patterns as written, and the mark for a host already trusted.
    ///
    /// The patterns are not editable here: renaming a block renames the thing
    /// every `ssh` invocation on this Mac names, and it belongs to the text
    /// view until it has a considered control of its own.
    private func title(_ row: SSHHostRows.Row) -> some View {
        HStack(spacing: HelmSpace.s2) {
            Text(row.patterns)
                .font(HelmText.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if !row.trusted.isEmpty { HelmBadge(HostsStr.trustedHost, tint: .green) }
            Spacer(minLength: 0)
        }
    }

    /// Where the block goes, and which key opens it.
    ///
    /// The address is the *resolved* one — `ssh` uses the alias when no
    /// `HostName` says otherwise — so it is not a second copy of the fields
    /// below it.
    private func detail(_ row: SSHHostRows.Row) -> some View {
        HStack(spacing: HelmSpace.s3) {
            if !row.address.isEmpty {
                Text(row.address)
                    .font(HelmText.figureFont)
                    .foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            // By position, because a block may name the same key twice and two
            // rows with one identity would be one row.
            ForEach(row.identities.indices, id: \.self) { at in
                key(row.identities[at])
            }
            Spacer(minLength: 0)
        }
    }

    /// The key this block names, in its three states — and **a host naming no
    /// key at all draws nothing**, because that is ordinary and a mark over it
    /// would be a warning about a file that is fine.
    ///
    /// Exhaustive, with no `default`: a state added to `KeyUsage.Identity` is a
    /// build error here rather than a row that quietly says nothing.
    @ViewBuilder private func key(_ identity: KeyUsage.Identity) -> some View {
        switch identity {
        case .named(let name):
            // The name takes you to the key. A row that only printed it would
            // leave somebody scrolling the first tab for a file name they have
            // just read.
            Button(HostsStr.usesKey(name)) { select(name) }
                .buttonStyle(.link)
                .lineLimit(1)
                .truncationMode(.middle)
        case .missing(let name):
            HStack(spacing: HelmSpace.s2) {
                Text(HostsStr.usesKey(name))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HelmBadge(HostsStr.hostKeyMissing, tint: .orange)
            }
        case .elsewhere(let path):
            // Outside `~/.ssh`, which this module does not list. Saying so is
            // not the same as saying the key is gone.
            Text(HostsStr.usesKey(path))
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The four directives Helm edits, in a grid whose keyword column is as
    /// wide as the longest keyword and no wider.
    ///
    /// **Only fields that exist are drawn.** Adding a directive a block does
    /// not have is a different act, with a place in the file to argue about,
    /// and `SSHConfigFile.set` refuses it — so offering an empty box for every
    /// one of the four would be offering three controls that silently do
    /// nothing.
    private func grid(of fields: [SSHConfigFile.Field], ofHost index: Int) -> some View {
        Grid(alignment: .leading, horizontalSpacing: HelmSpace.s3,
             verticalSpacing: HelmSpace.s2) {
            ForEach(fields, id: \.index) { field in
                GridRow {
                    // **The keyword is not translated.** `HostName` is what the
                    // file says and what `ssh`'s own manual says; a localised
                    // label over a field that writes that word would be
                    // teaching somebody a name their config does not use.
                    Text(field.name.rawValue)
                        .font(HelmText.figureFont)
                        .foregroundStyle(HelmText.quiet)
                    TextField(field.name.rawValue, text: Binding(
                        get: { field.value },
                        set: { hvm.setSSHField($0, of: field.name, ofHost: index) }))
                        .textFieldStyle(.roundedBorder)
                        .font(HelmText.figureFont)
                        .disabled(!hvm.sshWritable)
                        // The label beside it is drawn, so the field's own is
                        // hidden rather than absent: a control with no name is
                        // what `NamedControlsTests` exists to catch, and a
                        // screen reader needs the pair.
                        .accessibilityLabel("\(field.name.rawValue), \(index)")
                }
            }
        }
    }
}

/// One line of `known_hosts`, under the host it belongs to or under «other».
///
/// One view for both places rather than two that drift: the only difference is
/// whether the line has to say which host it is about, which it does not when
/// it is drawn under that host's own name.
private struct TrustLine: View {
    @ObservedObject var hvm: HostsViewModel
    let entry: KnownHostsFile.Entry
    let naming: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s2) {
            VStack(alignment: .leading, spacing: 2) {
                if naming { names }
                fingerprint
            }
            Spacer(minLength: HelmSpace.s2)
            Button(HostsStr.forgetHost) { Task { await hvm.forget(entry) } }
                .disabled(!hvm.knownHostsWritable || hvm.forgetting != nil)
        }
        .opacity(hvm.forgetting == entry.index ? 0.5 : 1)
    }

    /// A hashed line names nothing, and that is the file's own doing — macOS
    /// ships `HashKnownHosts yes`. The row says which fact it is short of
    /// rather than drawing a blank.
    private var names: some View {
        HStack(spacing: HelmSpace.s2) {
            Text(entry.isHashed ? HostsStr.hashedHost : entry.hosts.joined(separator: ", "))
                .font(HelmText.rowTitle)
                .foregroundStyle(entry.isHashed ? HelmText.quiet : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if entry.marker == "@revoked" { HelmBadge(HostsStr.revokedHost, tint: .orange) }
            if entry.marker == "@cert-authority" { HelmBadge(HostsStr.certificateAuthority) }
            Spacer(minLength: 0)
        }
    }

    private var fingerprint: some View {
        HStack(spacing: HelmSpace.s2) {
            Text(entry.keyType)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
            if let fingerprint = entry.fingerprint {
                // **Middle truncation, so both ends stay comparable**: what a
                // person does with a fingerprint is check it against one
                // somewhere else.
                Text(fingerprint)
                    .font(HelmText.figureFont)
                    .foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel(HostsStr.keyFingerprint)
            }
            Spacer(minLength: 0)
        }
    }
}
