import SwiftUI
import HelmUI
import Module_Hosts_Engine

/// The hosts this Mac has already trusted, and the one button they need.
///
/// **A list, not an editor.** The job people come here for is forgetting a host
/// whose key changed — `ssh` refuses to connect and prints a wall of text with
/// `ssh-keygen -R` at the bottom that nobody remembers. Everything else in this
/// file is a public key, which is not a thing to hand somebody a text field
/// over.
struct KnownHostsTable: View {
    @ObservedObject var hvm: HostsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            ForEach(hvm.knownHosts) { entry in
                row(entry)
                if entry.index != hvm.knownHosts.last?.index { Divider() }
            }
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s3)
    }

    private func row(_ entry: KnownHostsFile.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s2) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: HelmSpace.s2) {
                    // A hashed line names nothing, and that is the file's own
                    // doing — macOS ships `HashKnownHosts yes`. The row says
                    // which fact it is short of rather than drawing a blank.
                    Text(entry.isHashed ? HostsStr.hashedHost
                                        : entry.hosts.joined(separator: ", "))
                        .font(HelmText.rowTitle)
                        .foregroundStyle(entry.isHashed ? HelmText.quiet : .primary)
                    if entry.marker == "@revoked" { HelmBadge(HostsStr.revokedHost, tint: .orange) }
                    if entry.marker == "@cert-authority" {
                        HelmBadge(HostsStr.certificateAuthority)
                    }
                }
                HStack(spacing: HelmSpace.s2) {
                    Text(entry.keyType)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                    if let fingerprint = entry.fingerprint {
                        Text(fingerprint)
                            .font(HelmText.figureFont)
                            .textSelection(.enabled)
                            .foregroundStyle(HelmText.quiet)
                    }
                }
            }
            Spacer()
            Button(HostsStr.forgetHost) { Task { await hvm.forget(entry) } }
                .disabled(!hvm.knownHostsWritable || hvm.forgetting != nil)
        }
        .opacity(hvm.forgetting == entry.index ? 0.5 : 1)
    }
}
