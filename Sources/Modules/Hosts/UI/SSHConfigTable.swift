import SwiftUI
import HelmUI
import Module_Hosts_Engine

/// The blocks of `~/.ssh/config`, one card each, with the four fields Helm
/// edits.
///
/// **A block is not a row.** The hosts table one file over is a list of like
/// lines and a row is the unit; a config is blocks of unlike lines, and the
/// unit a person thinks in is «this host» — its patterns, and the handful of
/// settings under them. So this draws a card per block rather than a grid, and
/// the fields inside it are the ones that were already there.
///
/// **Only fields that exist are drawn.** Adding a directive a block does not
/// have is a different act, with a place in the file to argue about, and
/// `SSHConfigFile.set` refuses it — so offering an empty box for every one of
/// the four would be offering three controls that silently do nothing.
struct SSHConfigTable: View {

    @ObservedObject var hvm: HostsViewModel

    var body: some View {
        let document = hvm.sshDocument
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            ForEach(document.hosts, id: \.index) { host in
                block(host, fields: document.fields(ofHost: host.index))
            }
            if document.hosts.isEmpty {
                // Not an error and not an empty file — a config can be nothing
                // but `Include` and `Match`, which this table has no rows for
                // and the text view shows in full.
                Text(HostsStr.noHostBlocks)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
            }
        }
        .padding(HelmLayout.formInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block(_ host: SSHConfigFile.Host,
                       fields: [SSHConfigFile.Field]) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            // The patterns as written. Not editable here: renaming a block is
            // a rename of the thing every `ssh` invocation on this Mac names,
            // and it belongs to the text view until it has a considered
            // control of its own.
            Text(host.patterns)
                .font(HelmText.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            ForEach(fields, id: \.index) { field in
                row(field, host: host.index)
            }
        }
        .padding(HelmSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
            .fill(HelmSurface.wellFill))
    }

    private func row(_ field: SSHConfigFile.Field, host: Int) -> some View {
        HStack(spacing: HelmSpace.s4) {
            // **The keyword is not translated.** `HostName` is what the file
            // says and what `ssh`'s own manual says; a localised label over a
            // field that writes that word would be teaching somebody a name
            // their config does not use.
            Text(field.name.rawValue)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HelmText.quiet)
                .frame(width: 96, alignment: .leading)
            TextField(field.name.rawValue, text: Binding(
                get: { field.value },
                set: { hvm.setSSHField($0, of: field.name, ofHost: host) }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .disabled(!hvm.sshWritable)
                // The label above is drawn, so the field's own is hidden rather
                // than absent: a control with no name is what `NamedControlsTests`
                // exists to catch, and a screen reader needs the pair.
                .accessibilityLabel("\(field.name.rawValue), \(host)")
        }
    }
}
