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
/// So a key's usage is one of four states rather than a count, and a host's
/// identity is one of three rather than a path. Folding either would be the
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
        /// Nothing **in the file Helm read** names it, and the file hands part
        /// of itself to files Helm has not read — an `Include`.
        ///
        /// **Its own answer rather than `unused`, and that is a decision.**
        /// `KeyUsage` already names one limit — `IdentitiesOnly yes` is not
        /// parsed — and settles it by pointing the safe way: overstating use
        /// keeps a key that could have gone. `Include` is the same limit
        /// pointing the *unsafe* way, because it makes the module understate
        /// use, and the sentence it understates into is the one somebody
        /// deletes a key on. So the reading that cannot be completed says so,
        /// which is the same shape as `AgentList.unreachable` and
        /// `KeyRow.Permission.unknown`: «cannot say» is not «nothing».
        case cannotSay
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

    /// The identities named before the first `Host` line.
    ///
    /// Asked separately from `ofHosts` because what they mean *to a key* is a
    /// different answer: a preamble key is not «named by these two blocks», it
    /// is lent to every connection the file describes — including one to a host
    /// the file never mentions, which is why a config with a preamble key and
    /// no `Host` block at all still has a key in use.
    static func ofPreamble(_ document: SSHConfigFile.Document,
                           keys: [String], home: String) -> [Identity] {
        let known = Set(keys)
        return document.fields
            .filter { $0.scope == .preamble && $0.name == .identityFile }
            .map { identity(of: $0.value, keys: known, home: home) }
    }

    /// What each key in the inventory is used for. **Every key gets an answer**
    /// — a dictionary missing one is a row with nothing to draw.
    public static func ofKeys(_ document: SSHConfigFile.Document,
                              keys: [String], home: String) -> [String: OfKey] {
        let identities = ofHosts(document, keys: keys, home: home)
        var everywhere: Set<String> = []
        var namedBy: [String: [String]] = [:]
        // The preamble is `Host *` by another spelling — it reaches every
        // connection — so its keys go straight into `everywhere`, which
        // outranks any block that also happens to name them.
        for identity in ofPreamble(document, keys: keys, home: home) {
            if case .named(let name) = identity { everywhere.insert(name) }
        }
        for host in document.hosts {
            let names = (identities[host.index] ?? []).compactMap { identity -> String? in
                if case .named(let name) = identity { return name } else { return nil }
            }
            for name in names {
                if isEveryHost(host.patterns) {
                    everywhere.insert(name)
                } else if !(namedBy[name] ?? []).contains(host.patterns) {
                    // Once per host, not once per line that mentions the key.
                    // Two blocks with the same patterns are ordinary — people
                    // keep a second `Host box` for an override — and the row
                    // said «Used by box, box». A host is not two hosts because
                    // its file says so twice.
                    namedBy[name, default: []].append(host.patterns)
                }
            }
        }
        return keys.reduce(into: [:]) { out, key in
            if everywhere.contains(key) {
                // A `*` block outranks a named one: a key lent to everything is
                // not described by listing the one block that also mentions it.
                out[key] = .everyHost
            } else if let blocks = namedBy[key] {
                out[key] = .namedBy(blocks)
            } else if defaultNames.contains(key) {
                // Independent of the config: `ssh` tries this name whatever any
                // included file says, so an `Include` takes nothing away from
                // it.
                out[key] = .byDefaultName
            } else {
                out[key] = document.includesOtherFiles ? .cannotSay : .unused
            }
        }
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
