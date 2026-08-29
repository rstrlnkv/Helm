import Foundation
import HelmRuntime

/// The personal vocabulary, its salt, and the rule that neither may cost
/// anybody a dialog at launch.
///
/// **The salt is fetched off the launch path, and its absence is not a
/// refusal.** Helm is ad-hoc signed, so its identity changes with every build
/// and a keychain ACL written by one never matches the next — that is not a
/// one-off prompt, it is every install. The closed-lid setting was sealed for
/// exactly one commit before the installed build sat behind a system dialog
/// having drawn nothing, and the rule written down afterwards is: seal what is
/// read occasionally, never what `init` reads.
///
/// So this warms in the background and, until the key arrives, answers «no
/// personal vocabulary» — which is the module as it was yesterday, not a broken
/// one. No key ever means no learning, and never a wait.
public final class VocabularyStore: @unchecked Sendable {

    private let url: URL
    private let persists: Bool
    private let keys: SealKeyPort
    private let queue = DispatchQueue(label: "helm.layout.vocabulary")
    private var salt: SealKey?
    private var vocabulary = PersonalVocabulary()
    private var loaded = false

    /// A directory named is a directory written to; nothing named outside the
    /// app means nothing on disk, the same arrangement `LedgerStore` arrived at
    /// after leaving 91 folders in `$TMPDIR`.
    public init(directory: URL? = nil, keys: SealKeyPort) {
        let home = directory
            ?? HelmSupport.directory.appendingPathComponent("Layout", isDirectory: true)
        url = home.appendingPathComponent("vocabulary.json")
        persists = directory != nil || AppBuild.isBundledApp
        self.keys = keys
    }

    /// Fetch the key and read the file, off whatever thread called. Safe to
    /// call more than once; the second call is a no-op.
    ///
    /// Detached rather than merely asynchronous: the continuation of a `.task`
    /// is drained by the layout pass that draws the page, so a blocking
    /// keychain read inside one still delays the first frame — measured, and
    /// the reason `SettingGuard.warmKey` exists.
    public func warm() {
        queue.async { [self] in
            guard !loaded else { return }
            loaded = true
            salt = keys.key()
            guard persists, salt != nil,
                  let data = try? Data(contentsOf: url),
                  let stored = try? JSONDecoder().decode(PersonalVocabulary.self, from: data)
            else { return }
            vocabulary = stored
        }
    }

    /// Whether this word is one the person has put back twice.
    ///
    /// **False while the key is still coming**, and false for ever without one.
    /// This is on the tap's thread for every confirmed word, so it never waits
    /// for anything: `keyIfWarm`'s whole reason for existing is that a read
    /// which might block must not be asked here.
    func leavesAlone(_ word: String) -> Bool {
        queue.sync {
            guard let salt, let print = WordFingerprint.of(word, salt: salt) else { return false }
            return vocabulary.leavesAlone(print)
        }
    }

    /// The person put this word back. The one thing that teaches this file.
    func putBack(_ word: String) {
        queue.async { [self] in
            guard let salt, let print = WordFingerprint.of(word, salt: salt) else { return }
            vocabulary.putBack(print)
            guard persists else { return }
            guard !PrivateFile.writeMakingTheFolder(vocabulary, at: url) else { return }
            guard !warned else { return }
            warned = true
            // No word and no count: this file's whole point is that its
            // contents do not appear anywhere they can be read back.
            HelmLog.shared.warn(LayoutEngine.moduleID,
                                "the personal vocabulary could not be written — words put "
                                + "back will not be remembered after this launch")
        }
    }

    private var warned = false
}
