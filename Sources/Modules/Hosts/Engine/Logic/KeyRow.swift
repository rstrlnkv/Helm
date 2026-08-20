import Foundation

/// The four readings a key's row is made of, before anything has been decided
/// about them.
///
/// A struct rather than four arguments because the port gathers them together
/// and every one of them can be missing: `stat` fails on a key in a directory
/// this process may not search, `ssh-keygen -l` refuses a file it cannot read,
/// and the public half may simply not be there. **The private half is never
/// among them** — nothing in this module opens it.
public struct KeyFacts: Sendable, Equatable {
    public let pair: KeyInventory.Pair
    /// One `ssh-keygen -l` line, or nil when the tool said nothing this build
    /// could use.
    public let describeLine: String?
    public let mode: mode_t?
    public let modified: Date?
    /// The `.pub` file's text. Public by definition, which is why it may travel
    /// in the state at all — Copy is then a pasteboard write in the UI and no
    /// engine command.
    public let publicText: String?
    /// **Whether the name is a directory**, which the mode cannot say: it
    /// carries permission bits and no type. `KeyInventory.Listing` keeps a
    /// directory from becoming a row at all; this is the second half, so that a
    /// row reached any other way is still never offered a private key's
    /// `chmod 600` — which on a directory locks its owner out of it.
    public let isDirectory: Bool

    public init(pair: KeyInventory.Pair, describeLine: String? = nil, mode: mode_t? = nil,
                modified: Date? = nil, publicText: String? = nil, isDirectory: Bool = false) {
        self.pair = pair
        self.describeLine = describeLine
        self.mode = mode
        self.modified = modified
        self.publicText = publicText
        self.isDirectory = isDirectory
    }
}

/// One key, as tab 3 draws it.
public struct KeyRow: Codable, Sendable, Equatable, Identifiable {

    /// What a key's mode came to — **three answers, not two.**
    ///
    /// «Could not be read» is not «fine». `stat` fails on a key inside a
    /// directory this process may not search, and that is the very machine this
    /// module exists for; a row that folded the two would draw a verdict
    /// meaning «ssh will use this key» over a file nobody could look at, and
    /// offer no Fix beside it. This is `AgentList`'s shape one layer up, and
    /// `PowerSource.supply()`'s two modules over.
    public enum Permission: Codable, Sendable, Equatable {
        case unknown
        case ok
        /// Too open, and the mode that fixes it — carried rather than
        /// recomputed, so the sentence on screen and the `chmod` that runs
        /// cannot disagree about the number.
        case tooOpen(fix: mode_t)
    }

    /// The private half's file name. It is the row's identity because it is
    /// what `IdentityFile` names, and because **a name is all that crosses the
    /// wire**: an act arrives naming one of these and the engine matches it
    /// against the list it just read, so no payload ever becomes a path.
    public let name: String
    public var id: String { name }
    public let hasPublicHalf: Bool
    /// What `ssh-keygen -l` said, or nil for a line this build could not read.
    /// Nil rather than a row of empty strings: a fingerprint column that is
    /// blank because the parse failed and one that is blank because the key has
    /// no comment are different facts.
    public let described: KeyInventory.Description?
    public let modified: Date?
    public let permission: Permission
    public let publicText: String?
    /// Whether the agent is holding this key right now.
    public let inAgent: Bool

    public init(name: String, hasPublicHalf: Bool, described: KeyInventory.Description?,
                modified: Date?, permission: Permission, publicText: String?, inAgent: Bool) {
        self.name = name
        self.hasPublicHalf = hasPublicHalf
        self.described = described
        self.modified = modified
        self.permission = permission
        self.publicText = publicText
        self.inAgent = inAgent
    }

    /// The assembly, and the only place the four readings meet.
    ///
    /// The badge is asked **by fingerprint**, so a key whose description could
    /// not be parsed is out of the agent whatever the agent holds — the
    /// alternative is a claim about somebody's agent built out of a parse
    /// failure, which is the thing `AgentList.read` refuses one layer down.
    public static func row(from facts: KeyFacts, agent: AgentList) -> KeyRow {
        let described = facts.describeLine.flatMap(KeyInventory.described)
        return KeyRow(name: facts.pair.name,
                      hasPublicHalf: facts.pair.hasPublicHalf,
                      described: described,
                      modified: facts.modified,
                      permission: permission(of: facts.mode, isDirectory: facts.isDirectory),
                      publicText: facts.publicText,
                      inAgent: described.map { agent.holds($0.fingerprint) } ?? false)
    }

    /// **A directory is judged as a directory.** The two verdicts differ in the
    /// number they carry, and the private key's is destructive here: 0600 on a
    /// folder is a folder nobody, its owner included, can enter — so every
    /// multiplexed connection through a `ControlPath` in it stops, and so does
    /// the `Include` a `config.d` was made for.
    private static func permission(of mode: mode_t?, isDirectory: Bool) -> Permission {
        guard let mode else { return .unknown }
        let verdict = isDirectory ? KeyPermissions.directory(mode) : KeyPermissions.privateKey(mode)
        switch verdict {
        case .ok: return .ok
        case .tooOpen(let fix): return .tooOpen(fix: fix)
        }
    }
}
