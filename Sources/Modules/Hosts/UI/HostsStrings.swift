import HelmUI
import Module_Hosts_Engine

/// Every user-visible string this module has.
///
/// **"Host" is about to mean three things on one page** — the module, the
/// system file, and an `~/.ssh/config` block — and one English key means one
/// thing. Seventeen keys in this app already meant two things each and twelve
/// had to be split, so these three are three keys from the first day.
enum HostsStr {
    static var moduleName: String { L("Hosts & Keys") }
    /// The sidebar column is fixed and cuts a long name mid-word.
    static var moduleNameShort: String { L("Hosts") }
    static var summary: String { L("Edit the hosts file, SSH hosts and keys") }

    /// The file, not the module and not an SSH block — the second of the three
    /// meanings, and its own key from the first day.
    static var hostsFile: String { L("hosts file") }
    static var tableView: String { L("Table") }
    /// **Not the bare word, and the collision was already in the tree.** That key
    /// belonged to the panel's tab-label style — a tab labelled with a word
    /// rather than with a glyph — and Japanese and Chinese spell that sense
    /// «文字», which means *characters* and not *this file as it is written*.
    /// One English key means one thing, so this sense got its own; the word
    /// itself is macOS's, read out of TextEdit's and Mail's own tables rather
    /// than translated a second time. The tab-label setting is gone since
    /// 2026-08-21 — the strip measures its own names — and the key with it, so
    /// the collision is now only the reason this property is spelled the way it
    /// is.
    static var textView: String { L("Plain text") }
    /// The two tabs. **`hostsFile` is not reused for the tab**: it is the
    /// file's name in a sentence («the hosts file could not be read»), and a
    /// tab is a title. One English key means one thing.
    static var hostsTab: String { L("Hosts file") }
    static var sshTab: String { L("SSH config") }
    /// The third meaning of «host» — a block in `~/.ssh/config`, not the module
    /// and not the system file.
    static var noHostBlocks: String { L("No SSH hosts in this file") }
    static var sshUnreadable: String { L("The SSH config could not be read") }
    static var sshNotWritable: String { L("Helm will not write this file: it is outside your home folder") }
    static var sshApplied: String { L("Saved") }
    static var sshFailed: String { L("The SSH config could not be saved") }
    static var sshNotVerified: String { L("The save reported success and the file did not change") }

    // MARK: - Tab 1, the keys

    /// The first tab, and the reason the module was rebuilt: the question
    /// somebody arrives with is «what are my keys and which of them still do
    /// anything».
    static var keysTab: String { L("Keys") }

    // MARK: - Tab 2, the hosts

    /// The second tab. **Not `moduleNameShort`, which is also «Hosts»**: that
    /// one is the module's name in a sidebar of module names, and this is a
    /// title over the blocks of `~/.ssh/config`. One English key means one
    /// thing, so the tab says which hosts it is about.
    static var sshHostsTab: String { L("SSH hosts") }
    /// The trusts that belong to no block in the config — most of anybody's
    /// `known_hosts`, and every hashed line, since a hashed line names nobody.
    static var otherTrustedHosts: String { L("Other trusted hosts") }
    /// The mark on a host whose key this Mac has already accepted.
    static var trustedHost: String { L("Trusted") }
    static var knownHostsUnreadable: String { L("The known hosts file could not be read") }
    /// **Not `L("Remove")`.** `ssh` calls this forgetting a host, the manual
    /// page calls it that, and what happens next is that the next connection
    /// asks again — which «remove» does not say.
    static var forgetHost: String { L("Forget") }
    /// A hashed line names no host, and the row says which fact it is short of
    /// rather than drawing an empty column.
    static var hashedHost: String { L("Name hidden — this file is hashed") }
    static var knownHostsFailed: String { L("The known hosts file could not be saved") }
    static var revokedHost: String { L("Revoked") }
    static var certificateAuthority: String { L("Certificate authority") }

    /// «3 off» beside the count of mappings, for the day the hosts file has an
    /// editor on this page again. It interpolates a count, so it keeps an
    /// inline table: the interpolation runs before a lookup would, which is why
    /// there is no English key to be the key. The rule and its reason are
    /// CLAUDE.md's.
    static func entriesOff(_ count: Int) -> String {
        switch AppLanguage.current {
        case .ru: return "\(count) выкл."
        case .es: return "\(count) desactivadas"
        case .fr: return "\(count) désactivées"
        case .de: return "\(count) aus"
        case .pt: return "\(count) desativadas"
        case .ja: return "\(count) 件オフ"
        case .zh: return "\(count) 条已关闭"
        case .en: return "\(count) off"
        }
    }

    // MARK: - Which key opens which host

    /// What a key is used for, in six sentences — **and they are six, not
    /// three.**
    ///
    /// `byDefaultName` is the one that must never read as `unused`: `ssh` tries
    /// `id_ed25519` and its siblings without being told to, so a key nothing
    /// mentions may be the one somebody logs in with everywhere. Collapsing the
    /// pair writes «you can delete this» over it.
    ///
    /// `cannotSay` is the same distinction one step further out: something in
    /// the config was not read, so «nothing names it» is a claim about an
    /// incomplete reading and must not be spelled as a fact. Its two reasons
    /// get two sentences, because each names a different place to go and look —
    /// and «an included file may use it» said over a `Match` block would be a
    /// claim about a file the person does not have.
    ///
    /// Exhaustive down to the reason, with no `default`: a state added to
    /// `KeyUsage.OfKey` — or a reason added to `OfKey.Unread` — is a build
    /// error here rather than a row that says nothing.
    static func usage(of usage: KeyUsage.OfKey,
                      language: AppLanguage = AppLanguage.current) -> String {
        switch usage {
        case .namedBy(let hosts): return usedBy(hosts, language: language)
        case .everyHost: return L("Used by every host", language: language)
        case .byDefaultName: return L("Used by default — ssh tries this name", language: language)
        case .unused: return L("Not used by anything here", language: language)
        case .cannotSay(.includedFile):
            return L("Not named here — an included file may use it", language: language)
        case .cannotSay(.matchCondition):
            return L("Named under a Match — used when its condition holds", language: language)
        }
    }

    /// The hosts by name. Interpolated, so it keeps an inline table: the
    /// interpolation runs before a lookup would, which is why there is no
    /// English key to be the key.
    private static func usedBy(_ hosts: [String], language: AppLanguage) -> String {
        let named = hosts.joined(separator: ", ")
        return L("Used by \(named)", [.ru: "Используется: \(named)", .es: "Usada por \(named)", .fr: "Utilisée par \(named)", .de: "Verwendet von \(named)", .ja: "\(named) が使用", .zh: "由 \(named) 使用", .pt: "Usada por \(named)"], language: language)
    }

    /// The key a host uses, on the host's own row. Interpolated for the reason
    /// above; the name is the file's, which is what `IdentityFile` writes.
    static func usesKey(_ name: String, language: AppLanguage = AppLanguage.current) -> String {
        L("Key: \(name)", [.ru: "Ключ: \(name)", .es: "Clave: \(name)", .fr: "Clé\u{00A0}: \(name)", .de: "Schlüssel: \(name)", .ja: "鍵: \(name)", .zh: "密钥：\(name)", .pt: "Chave: \(name)"], language: language)
    }

    /// **A host pointing at a key that is gone is not a host pointing at
    /// none.** The first is broken — the connection will fail and the file says
    /// nothing about why — and the second is ordinary, which is why only one of
    /// them is marked.
    static var hostKeyMissing: String { L("This key is missing") }

    /// **Not «No keys».** The sentence names the folder, because the two
    /// answers a person needs to tell apart are «this Mac has none» and «Helm
    /// could not look», and a bare «No keys» reads as the first while being
    /// drawn for either.
    static var noKeys: String { L("No keys in this folder") }
    static var keysUnreadable: String { L("The .ssh folder could not be read") }
    static var keyFingerprint: String { L("Fingerprint") }
    static var keyType: String { L("Type") }
    static var keyUnreadable: String { L("Helm could not read this key") }

    /// The verdict, and it names the consequence rather than the number: the
    /// mode is what a person cannot remember, and «ssh will refuse it» is what
    /// they came to the page about.
    static var keyTooOpen: String { L("Others can read this key — ssh will refuse to use it") }
    static var keyModeUnknown: String { L("Helm could not read this key’s permissions") }
    static var directoryTooOpen: String { L("Others can write to this folder — ssh keys in it are not safe") }
    /// **Not `L("Fix")`, and the collision was already in the tree.** That key
    /// is Layout's `ruleOn` — a rule that fixes as you type — and Russian
    /// spells that sense «Исправлять», the imperfective: a behaviour that goes
    /// on. This is a button that does one thing once, which is «Исправить».
    /// One English key means one thing, so this sense gets its own — and the
    /// longer name is better copy beside the verdict anyway.
    static var fixPermissions: String { L("Fix permissions") }

    /// The agent. **Three sentences, because the port answers three states** —
    /// and «no keys loaded» drawn over an agent that is not running is an
    /// invitation to press something that cannot work.
    static var agentHolding: String { L("The agent is holding these keys") }
    static var agentEmpty: String { L("The agent is running and holding no keys") }
    static var agentMissing: String { L("No agent is running") }
    static var agentCheck: String { L("Check the agent") }
    static var inAgent: String { L("In the agent") }
    static var addToAgent: String { L("Add to the agent") }
    static var removeFromAgent: String { L("Take out of the agent") }

    /// Asked in the row, under the control that was pressed.
    static var keyIsLocked: String { L("This key has a passphrase") }
    static var passphraseRefused: String { L("That passphrase was not accepted") }
    static var unlockAndAdd: String { L("Unlock and add") }

    static var copyPublicKey: String { L("Copy public key") }
    static var noPublicHalf: String { L("This key’s public half is missing") }

    static var newKey: String { L("New key…") }
    static var newKeyTitle: String { L("New key") }
    static var keyName: String { L("File name") }
    static var keyComment: String { L("Comment") }
    static var keyPassphrase: String { L("Passphrase") }
    /// **The note under the passphrase field, and it says the cost of an empty
    /// one rather than «optional».** A key with no passphrase is a key anybody
    /// who reaches the file can use, and that is the decision being taken here.
    static var passphraseNote: String { L("A key with no passphrase can be used by anyone who gets the file") }
    static var create: String { L("Create") }
    static var cancel: String { L("Cancel") }
    static var making: String { L("Making the key…") }

    /// Exhaustive over the generator's answers. `.done` says nothing: the new
    /// key appears in the list behind the sheet, which is the sentence.
    static func sentence(for outcome: GenerateOutcome) -> String? {
        switch outcome {
        case .done: return nil
        case .notAPlainName: return L("A file name cannot contain a slash")
        case .nameTaken: return L("There is already a key with that name")
        case .commentHasALineBreak: return L("A comment cannot contain a line break")
        case .failed: return L("The key could not be made")
        case .alreadyRunning: return making
        }
    }

    /// The sentence for an act on a key, and `nil` for the one that needs none.
    ///
    /// Exhaustive, like `sentence(for:)` below it: a case added to `KeyOutcome`
    /// is a build error here rather than an act that comes back saying nothing.
    /// `.done` answers nil because the row redraws — the verdict changes, or
    /// the badge comes on — and that redraw *is* the sentence.
    static func sentence(for outcome: KeyOutcome) -> String? {
        switch outcome {
        case .done: return nil
        case .failed: return L("That did not work")
        case .notFound: return L("That key is no longer there")
        case .agentUnreachable: return agentMissing
        // The row itself asks for the passphrase, so the bar at the top says
        // nothing: two places asking one question is one of them being ignored.
        case .needsPassphrase: return nil
        }
    }

    static var address: String { L("Address") }
    static var names: String { L("Names") }
    static var addEntry: String { L("Add entry") }
    static var removeEntry: String { L("Remove entry") }
    static var entryIsOn: String { L("Use this entry") }
    static var apply: String { L("Apply") }
    static var revert: String { L("Revert") }
    static var restore: String { L("Restore…") }
    static var unsaved: String { L("Unsaved changes") }
    static var needsPassword: String { L("Applying asks for your password") }
    static var unreadable: String { L("The hosts file could not be read") }
    static var tooLarge: String { L("This hosts file is too large for Helm to save") }
    static var tooLargeNote: String { L("Helm can show it, but saving needs another editor") }

    /// When a copy was taken, as this reader's language and time zone write it.
    ///
    /// **The name is not the label.** `2026-08-18T120000Z.hosts` sorts, which is
    /// what it is for, and it says nothing to the person choosing between ten of
    /// them: the stamp is UTC, so its digits are somebody else's afternoon.
    /// `BackupName.date(of:)` reads it back and `HelmDates` writes it — the rule
    /// that everything the language shapes goes through `HelmUI`. A name that is
    /// not one of ours has no date and is drawn as it is, which is the honest
    /// answer for a file this module did not write.
    static func backupTaken(_ name: String) -> String {
        BackupName.date(of: name).map { HelmDates.dayAndMinute($0) } ?? name
    }

    /// **A refused edit says which rule refused it.** `HostsFile.Refusal` is
    /// switched over exhaustively here, so a reason added to the engine is a
    /// build error in the UI rather than a field that snaps back in silence.
    static func sentence(for refusal: HostsFile.Refusal) -> String {
        switch refusal {
        case .noSuchEntry: return L("That entry is no longer there")
        case .unwritableAddress: return L("Not an address Helm can write")
        case .noNames: return L("An entry needs at least one name")
        case .unwritableName: return L("A name cannot contain spaces, # or a line break")
        }
    }

    /// The sentence for an outcome, so the page never spells one by hand — and
    /// `nil` for the one outcome that needs no sentence.
    ///
    /// **The exhaustive switch is the point, and so is the optional.** A case
    /// added to `HostsOutcome` is a build error here rather than an apply that
    /// comes back saying nothing. `.applied` answers `nil` because the bar
    /// carrying this sentence is the bar that closes on a successful apply:
    /// «Applied» written into a view on its way off the screen is a word
    /// nobody reads, and a key nobody reads is a translation the next person
    /// inherits for something else. The closing *is* the sentence.
    static func sentence(for outcome: HostsOutcome) -> String? {
        switch outcome {
        case .applied: return nil
        case .declined: return L("Not applied — the password dialog was cancelled")
        case .failed: return L("The hosts file could not be written")
        case .notVerified: return L("The write reported success, but the file on disk differs")
        case .noBackup: return L("Nothing was written: a backup could not be saved first")
        case .tooLarge: return tooLarge
        }
    }
}
