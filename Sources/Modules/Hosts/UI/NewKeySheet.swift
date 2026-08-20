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
    /// Empty until `KeyComment.value()` answers, and it answers from a task
    /// this view does not wait for — see `KeyComment`. An initial value here is
    /// an `init` on the thread that draws.
    @State private var comment = ""
    /// A `String` because `SecureField` binds to nothing else. It is dropped as
    /// soon as the call returns — see `HostsViewModel.generate`, which carries
    /// the whole reasoning about what this app can and cannot promise here.
    @State private var passphrase = ""

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
        .task {
            // The field is somebody's to type in, so it is filled only while it
            // is still the default — an answer arriving late must not land on
            // top of what they wrote.
            if comment.isEmpty { comment = await KeyComment.value() }
        }
        .onDisappear { hvm.forgetGeneration() }
    }
}

/// `user@host` — the comment `ssh-keygen` writes when it is given none — read
/// **off the thread that draws**, and once.
///
/// `ProcessInfo.processInfo.hostName` asks the network stack what this Mac is
/// called; it is a reverse lookup and it was measured at 43 ms cold. It sat in
/// the sheet's `@State` initial value, which SwiftUI evaluates while it
/// installs the view's state — on the main thread, every time the sheet is
/// built. That is the shape CLAUDE.md records for the settings page and a
/// keychain: **a `@State` initial value is an `init`**, and moving the read
/// into a `.task` is not by itself the fix, because the continuation is drained
/// by the same layout pass that draws the view. What moves it is the thread.
///
/// There is no `warm()` to call at launch and no caller to forget one: the
/// first ask does the work on a detached task and every later ask is answered
/// out of memory. The name is not asked again — a Mac renamed while the app is
/// running keeps the comment this session started with, which is a default in
/// an editable field and not a fact anything is decided from.
///
/// A class with a `shared` rather than an enum with a `static var`, which is the
/// shape `SealKeyCache` has one target over and the shape Swift 6 allows: a
/// nonisolated mutable static is global shared state the compiler refuses, and
/// `nonisolated(unsafe)` would be the author promising by hand what the lock
/// below promises by construction.
final class KeyComment: @unchecked Sendable {

    static let shared = KeyComment()

    private let lock = NSLock()
    private var held: String?

    /// The value, read on a detached task the first time and out of memory
    /// afterwards. The lock is never held across the read — that was the whole
    /// finding of the keychain hang: warming off the main thread is not the
    /// same as the main thread not waiting for it.
    static func value() async -> String { await shared.value() }

    func value() async -> String {
        if let held = lock.withLock({ held }) { return held }
        let read = await Task.detached(priority: .userInitiated) {
            "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"
        }.value
        lock.withLock { held = read }
        return read
    }
}
