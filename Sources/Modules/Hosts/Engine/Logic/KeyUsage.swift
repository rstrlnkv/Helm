import Foundation

/// Which key opens which host — the join the module reads three files to know
/// and, until now, never said.
///
/// **It is not a string comparison.** `ssh` accepts the same key written five
/// ways, lends a `Host *` block's key to every host in the file, and reaches for
/// keys nobody named at all. Each of those is a way to answer «used by nothing»
/// about the key somebody logs in with, and on screen that answer reads as «safe
/// to delete».
///
/// So a key's usage is a state rather than a count, and a host's identity is a
/// state rather than a path — read `OfKey` and `Identity` for how many each is
/// now, because that number has already gone stale in this sentence once.
/// Folding either would be the
/// defect ARCHITECTURE.md § A nil from a system read can be folding two
/// questions into one is about, arriving in a module that has no system read:
/// «named nowhere» and «not used» are different facts, and so are «points at a
/// key that is gone» and «points at no key».
public enum KeyUsage {

    /// What one `IdentityFile` line resolves to.
    public enum Identity: Equatable, Sendable {
        /// A key this module lists, by the private half's file name.
        case named(String)
        /// A name in `~/.ssh` with no key behind it. A host pointing at a key
        /// that has been deleted is broken, and a host pointing at no key at
        /// all is ordinary; a row that drew them alike would hide the first.
        case missing(String)
        /// A path outside `~/.ssh`, resolved. Not this module's to judge — it
        /// lists one directory — and saying so is not the same as saying the
        /// key is missing.
        case elsewhere(String)
    }

    /// How a key comes to be used.
    public enum OfKey: Equatable, Sendable {
        /// Named by these blocks, written as their patterns are written: a
        /// `Host web1 web2` is one block and the row says so.
        case namedBy([String])
        /// Lent to every host in the file by a `*` block.
        case everyHost
        /// Nothing names it, and `ssh` will try it anyway because of what it is
        /// called. **The state that must not collapse into `unused`.**
        case byDefaultName
        /// Nothing names it and nothing will reach for it.
        case unused
        /// **The reading could not be completed, and by what.**
        ///
        /// The reason is carried rather than folded away because the row draws
        /// a sentence from it, and the two sentences are about different files:
        /// «an included file may use it» is false of a config with no
        /// `Include`, and telling somebody that about a key their `Match all`
        /// block lends to every connection is a claim about their machine that
        /// is not true.
        ///
        /// **Its own answer rather than `unused`, and that is a decision.**
        /// `KeyUsage` already names one limit — `IdentitiesOnly yes` is not
        /// parsed — and settles it by pointing the safe way: overstating use
        /// keeps a key that could have gone. `Include` is the same limit
        /// pointing the *unsafe* way, because it makes the module understate
        /// use, and the sentence it understates into is the one somebody
        /// deletes a key on. A `Match` is that same limit pointing the same
        /// way, and it was left standing for a day after `Include` was
        /// settled. So the reading that cannot be completed says so,
        /// which is the same shape as `AgentList.unreachable` and
        /// `KeyRow.Permission.unknown`: «cannot say» is not «nothing».
        case cannotSay(Unread)
    }

    /// What stopped a reading that could not be completed — one of the two
    /// things in an `ssh_config` this module deliberately does not read.
    ///
    /// Beside `OfKey` rather than inside it: nested one level further the type
    /// is past what this house's linter allows, and a reason that stands on its
    /// own is what a third one would be added to.
    public enum Unread: Equatable, Sendable {
        /// The config `Include`s files Helm never opened, and one of them may
        /// name the key.
        case includedFile
        /// The key is named here, under a `Match` block whose condition this
        /// module can neither show nor evaluate (`SSHConfigFile.Scope.match`).
        /// `ssh` offers it every time that condition holds.
        case matchCondition
    }

    /// The names `ssh` tries when a host names no identity of its own.
    ///
    /// From `ssh_config`'s own default `IdentityFile` list. A key called one of
    /// these is in use whatever the config says, which is why the list is here
    /// rather than in a comment.
    ///
    /// **Known limit:** `IdentitiesOnly yes` switches these off, and this module
    /// does not parse that directive — `SSHConfigFile.FieldName` carries four
    /// keywords and that is not one of them. A Mac using it would see a key
    /// called «used by default» that `ssh` will not in fact try. Overstating use
    /// is the safe direction: the wrong answer is a key kept, not a key deleted.
    static let defaultNames: Set<String> = [
        "id_rsa", "id_ecdsa", "id_ecdsa_sk", "id_ed25519", "id_ed25519_sk", "id_dsa",
    ]

    /// The identities each host uses, by the block's index, in the order the
    /// file writes them — **the preamble's included.** A host that reaches none
    /// answers with an empty list.
    ///
    /// A field before the first `Host` line applies to every connection, so a
    /// block naming no identity of its own still logs in with the preamble's
    /// key; a row that left the line blank would say «this host names no key»,
    /// which is a different fact from the one the file carries.
    public static func ofHosts(_ document: SSHConfigFile.Document,
                               keys: [String], home: String) -> [Int: [Identity]] {
        let known = Set(keys)
        var out: [Int: [Identity]] = [:]
        for host in document.hosts {
            out[host.index] = document.fieldsReaching(host: host.index)
                .filter { $0.name == .identityFile }
                .map { identity(of: $0.value, keys: known, home: home) }
        }
        return out
    }

    /// The identities named in one scope, for the two scopes that name no
    /// `Host` block — and they mean opposite things to a key.
    ///
    /// Asked separately from `ofHosts` because what they mean *to a key* is a
    /// different answer: a preamble key is not «named by these two blocks», it
    /// is lent to every connection the file describes — including one to a host
    /// the file never mentions, which is why a config with a preamble key and
    /// no `Host` block at all still has a key in use. A `Match` key is the
    /// other limit: it is named, in this file, by a block whose condition this
    /// parser does not read — so what it cannot be is «named by nothing».
    static func identities(in scope: SSHConfigFile.Scope,
                           of document: SSHConfigFile.Document,
                           keys: [String], home: String) -> [Identity] {
        let known = Set(keys)
        return document.fields
            .filter { $0.scope == scope && $0.name == .identityFile }
            .map { identity(of: $0.value, keys: known, home: home) }
    }

    /// What each key in the inventory is used for. **Every key gets an answer**
    /// — a dictionary missing one is a row with nothing to draw.
    public static func ofKeys(_ document: SSHConfigFile.Document,
                              keys: [String], home: String) -> [String: OfKey] {
        let naming = Naming(document, keys: keys, home: home)
        return keys.reduce(into: [:]) { out, key in out[key] = naming.verdict(for: key) }
    }

    /// Everything the config says about the keys, gathered once — so the
    /// verdict for one key is a reading rather than another walk of the file.
    private struct Naming {
        /// Keys lent to every connection the file describes: a `*` block, or
        /// the preamble, which is `Host *` by another spelling.
        var everywhere: Set<String> = []
        /// For every other key, the blocks that name it, by their patterns as
        /// they are written.
        var namedBy: [String: [String]] = [:]
        /// Keys named under a `Match`, whose condition this module reads
        /// neither for the row nor for itself.
        var underAMatch: Set<String> = []
        /// Whether the file hands part of itself to files Helm never opened.
        ///
        /// A question about the document, asked once, where it used to be asked
        /// again for every key in the inventory — and it is not a stored flag
        /// being read: `Document.includesOtherFiles` walks every line and parses
        /// each one that is not a directive this module edits.
        var includesOtherFiles = false

        init(_ document: SSHConfigFile.Document, keys: [String], home: String) {
            let perHost = ofHosts(document, keys: keys, home: home)
            everywhere = Set(named(in: identities(in: .preamble, of: document,
                                                  keys: keys, home: home)))
            underAMatch = Set(named(in: identities(in: .match, of: document,
                                                   keys: keys, home: home)))
            includesOtherFiles = document.includesOtherFiles
            for host in document.hosts {
                for name in named(in: perHost[host.index] ?? []) {
                    if isEveryHost(host.patterns) {
                        everywhere.insert(name)
                    } else if !(namedBy[name] ?? []).contains(host.patterns) {
                        // Once per host, not once per line that mentions the
                        // key. Two blocks with the same patterns are ordinary —
                        // people keep a second `Host box` for an override — and
                        // the row said «Used by box, box». A host is not two
                        // hosts because its file says so twice.
                        namedBy[name, default: []].append(host.patterns)
                    }
                }
            }
        }

        /// One key's answer, in the order the states outrank each other.
        func verdict(for key: String) -> OfKey {
            if everywhere.contains(key) {
                // A `*` block outranks a named one: a key lent to everything is
                // not described by listing the one block that also mentions it.
                return .everyHost
            }
            if let blocks = namedBy[key] { return .namedBy(blocks) }
            // Independent of the config: `ssh` tries this name whatever any
            // included file says, so an `Include` takes nothing away from it.
            if defaultNames.contains(key) { return .byDefaultName }
            // **Named here, and by nobody this module can print.** A `Match`
            // block's condition is a grammar this parser does not read, so
            // «used by nothing» — which the row spells «Not used by anything
            // here» and a person reads as «safe to delete» — is a claim the
            // reading does not support. `Match all` is the plainest case: it
            // reaches every connection below it, and read as unused it invites
            // deleting the key they all log in with.
            //
            // Said before the `Include` answer, because a config can carry both
            // and this one is about a line the person can go and read.
            if underAMatch.contains(key) { return .cannotSay(.matchCondition) }
            if includesOtherFiles { return .cannotSay(.includedFile) }
            return .unused
        }
    }

    /// The keys among a list of identities, in the order they were written.
    /// A `.missing` or `.elsewhere` names no key in this inventory.
    private static func named(in identities: [Identity]) -> [String] {
        identities.compactMap { if case .named(let name) = $0 { return name } else { return nil } }
    }

    /// Whether a block's pattern list covers every host.
    ///
    /// Split rather than compared to `"*"`, because `Host * !jump` is a `*`
    /// block with an exception and still lends its key to almost everything —
    /// and reading it as a literal host called `* !jump` would name a host that
    /// does not exist.
    static func isEveryHost(_ patterns: String) -> Bool {
        patterns.split(whereSeparator: \.isWhitespace).contains("*")
    }

    /// One `IdentityFile` value, resolved.
    ///
    /// The five spellings `ssh` reads identically: `~/.ssh/k`, `%d/.ssh/k`, an
    /// absolute path, a bare `k` relative to `~/.ssh`, and any of them quoted —
    /// which is how a path with a space in it is written, and the reason the
    /// quotes cannot simply be left on.
    ///
    /// A `.pub` suffix names the same pair. `ssh` accepts the public half as an
    /// identity — the ordinary reason to write it that way is that the private
    /// half is in the agent — so a resolution that kept the suffix would report
    /// the key unused.
    static func identity(of value: String, keys: Set<String>, home: String) -> Identity {
        var path = value.trimmingCharacters(in: .whitespaces)
        if path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") {
            path = String(path.dropFirst().dropLast())
        }
        if path.hasPrefix("%d") {
            path = home + path.dropFirst(2)
        } else if path.hasPrefix("~") {
            path = home + path.dropFirst()
        }
        let sshDirectory = home + "/.ssh"
        if !path.contains("/") { path = sshDirectory + "/" + path }

        let directory = (path as NSString).deletingLastPathComponent
        var name = (path as NSString).lastPathComponent
        if name.hasSuffix(".pub") { name = String(name.dropLast(4)) }
        guard directory == sshDirectory else { return .elsewhere(path) }
        return keys.contains(name) ? .named(name) : .missing(name)
    }
}
