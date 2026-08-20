import SwiftUI
import HelmUI
import Module_Hosts_Engine

/// The entries, one row each.
///
/// **Every field is bound straight to the document, and that only works because
/// an edit that changes nothing publishes nothing.** A field bound through a
/// validating editor is re-read from the model on every body pass, so each
/// publication writes the model's spelling back into the field under the caret:
/// `10.` is not an address and would snap back to what was there before it
/// could become `10.0.0.1`, and the space between two names would vanish as
/// fast as it was typed. `HostsViewModel.edit` publishes only what it actually
/// changed — refused *and* applied-to-no-effect are both silent — and that is
/// what leaves a half-typed value on screen while the model keeps the last
/// thing it could read.
///
/// Every control here carries a name even where a glyph is its whole face —
/// `NamedControlsTests` scans the source for both the empty label and the
/// glyph-only shape, because the defect is invisible at runtime to anyone not
/// using a screen reader.
struct HostsTable: View {
    @ObservedObject var hvm: HostsViewModel

    var body: some View {
        // The parse is asked for once. `entries` re-parses the document on
        // every read, so a body that asked it per row would parse the file as
        // many times as the file has rows.
        let entries = hvm.entries
        // **Lazy, because this page shows files it cannot write.** `HostsWrite.fits`
        // stops the privileged sentence at roughly 390 KB and the page says so on
        // open, so an ad-blocking file of 1–4 MB is displayed on purpose and this
        // table is handed every row of it. Eagerly that was not slow, it was
        // fatal — a few thousand rows aborted the process outright.
        // `TheTableDoesNotGrowWithTheFileTests` holds the measurement and the
        // guard, which is written about growth rather than about a number.
        LazyVStack(spacing: 0) {
            ForEach(entries) { entry in
                row(entry)
                Divider()
            }
            addRow
        }
    }

    private func row(_ entry: HostsFile.Entry) -> some View {
        HStack(spacing: HelmSpace.s3) {
            Toggle(isOn: Binding(
                get: { entry.enabled },
                set: { hvm.setEnabled($0, entry: entry.index) }
            )) {
                Text(HostsStr.entryIsOn)
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            // Dimmed together, and the switch beside them is not: a row drawn
            // at half ink whose own way back is the dimmest thing in it is a
            // control asking to be found before it can be pressed.
            Group {
                // **No width in points, on either field.** The address column
                // was pinned at 220 pt so the name fields would start at one x
                // down the table; two fields that each take an equal share of
                // whatever the row has do that too, and they still do it at the
                // 490 pt the settings pane comes down to, where 220 was half
                // the row. `HostsRowsFitTheMinimumPaneTests` holds the rule.
                TextField(HostsStr.address, text: Binding(
                    get: { entry.address },
                    set: { hvm.setAddress($0, entry: entry.index) }
                ))

                TextField(HostsStr.names, text: Binding(
                    get: { entry.names.joined(separator: " ") },
                    set: { hvm.setNames($0.split(separator: " ").map(String.init),
                                        entry: entry.index) }
                ))
            }
            // The file's own face. A hosts file is read in a terminal as often
            // as it is read here, and an address is a column of digits somebody
            // compares down the table.
            .font(.system(.body, design: .monospaced))
            .opacity(entry.enabled ? 1 : 0.55)

            Button {
                hvm.remove(entry: entry.index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(HostsStr.removeEntry)
            .help(HostsStr.removeEntry)
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s2)
    }

    /// The address a new row starts on is the loopback and a name in the
    /// `.local` space macOS reserves for it — a row that is already a legal
    /// entry, so the table never holds one the engine would refuse.
    private var addRow: some View {
        HStack {
            Button {
                hvm.append(address: "127.0.0.1", names: ["example.local"])
            } label: {
                Label(HostsStr.addEntry, systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s3)
    }
}
