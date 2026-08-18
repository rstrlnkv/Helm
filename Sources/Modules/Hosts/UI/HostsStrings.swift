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
    /// **Not `L("Text")`, and the collision was already in the tree.** That key
    /// belongs to the panel's tab-label style — a tab labelled with a word
    /// rather than with a glyph — and Japanese and Chinese spell that sense
    /// «文字», which means *characters* and not *this file as it is written*.
    /// One English key means one thing, so this sense gets its own; the word
    /// itself is macOS's, read out of TextEdit's and Mail's own tables rather
    /// than translated a second time.
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
