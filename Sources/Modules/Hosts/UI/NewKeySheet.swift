import SwiftUI
import HelmUI
import Module_Hosts_Engine

/// «New key»: the four things `ssh-keygen` needs, and nothing else.
///
/// The default is `ed25519` because it is the right answer for almost everyone;
/// RSA is offered at 4096 bits for the hosts that still insist. The comment
/// defaults to `user@host`, which is what `ssh-keygen` itself would write.
struct NewKeySheet: View {
    @ObservedObject var hvm: HostsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var type: KeyGeneration.KeyType = .ed25519
    @State private var name = "id_ed25519"
    @State private var comment = NewKeySheet.defaultComment
    /// A `String` because `SecureField` binds to nothing else. It is dropped as
    /// soon as the call returns — see `HostsViewModel.generate`, which carries
    /// the whole reasoning about what this app can and cannot promise here.
    @State private var passphrase = ""

    static var defaultComment: String {
        "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            Text(HostsStr.newKeyTitle).font(.headline)

            Form {
                Picker(HostsStr.keyType, selection: $type) {
                    Text("Ed25519").tag(KeyGeneration.KeyType.ed25519)
                    Text("RSA 4096").tag(KeyGeneration.KeyType.rsa)
                }
                .onChange(of: type) { _, new in
                    // The file name follows the type while nobody has typed
                    // their own: a key called `id_ed25519` that is RSA is a
                    // file somebody will misread a year from now.
                    if name == "id_ed25519" || name == "id_rsa" {
                        name = new == .rsa ? "id_rsa" : "id_ed25519"
                    }
                }
                TextField(HostsStr.keyName, text: $name)
                TextField(HostsStr.keyComment, text: $comment)
                SecureField(HostsStr.keyPassphrase, text: $passphrase)
                Text(HostsStr.passphraseNote)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(.secondary)
            }

            if let outcome = hvm.generated, let said = HostsStr.sentence(for: outcome) {
                HelmBanner(said)
            }

            HStack {
                Spacer()
                Button(HostsStr.cancel) { dismiss() }
                Button(HostsStr.create) {
                    Task {
                        await hvm.generate(type: type, name: name,
                                           comment: comment, passphrase: passphrase)
                        // Dropped whatever the answer was: a refusal keeps the
                        // sheet open for the name to be corrected, and it does
                        // not keep the secret.
                        passphrase = ""
                        if hvm.generated == .done { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || hvm.makingKey)
            }
        }
        .padding(HelmSpace.s5)
        .frame(width: 420)
        .onDisappear { hvm.forgetGeneration() }
    }
}
