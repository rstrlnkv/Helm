import Foundation

/// How a package is named once, everywhere.
///
/// A formula and a cask can share a name — `docker` is both — so neither the
/// row identity nor the description cache can be keyed by the name alone. The
/// prefixed form was written out eight times across the module: three
/// `Identifiable` conformances, the description lookup, and four more inside
/// the batch that fills it. Nothing tied them together, and the failure of a
/// disagreement is silent — descriptions arrive under keys the rows do not ask
/// for, so every row simply has no description and no error is raised anywhere.
public enum BrewKey {
    public static func of(name: String, isCask: Bool) -> String {
        (isCask ? "c:" : "f:") + name
    }
}

/// What the UI sends to name one package. It crossed the transport as a struct
/// declared **twice** — privately in the engine and privately again in the view
/// model — so the two could drift apart with nothing to catch it: a renamed
/// field fails the decode, the handler returns `Data()`, and the button does
/// nothing at all. `LeftoversToggle` is the shape this follows.
public struct PackageRef: Codable, Sendable {
    public let name: String
    public let isCask: Bool
    public init(name: String, isCask: Bool) { self.name = name; self.isCask = isCask }
}

/// One `brew desc` batch: a list of names of one kind.
public struct DescriptionsRequest: Codable, Sendable {
    public let names: [String]
    public let isCask: Bool
    public init(names: [String], isCask: Bool) { self.names = names; self.isCask = isCask }
}

public struct BrewPackage: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let version: String
    public let isCask: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
    public init(name: String, version: String, isCask: Bool) {
        self.name = name; self.version = version; self.isCask = isCask
    }
}

public struct OutdatedPackage: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let installed: String
    public let latest: String
    public let isCask: Bool
    /// Held at this version on purpose. brew still reports it as outdated and
    /// `brew upgrade` still refuses it, so a row that offers Upgrade offers a
    /// button that answers "…is pinned".
    public let pinned: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
    public init(name: String, installed: String, latest: String, isCask: Bool,
                pinned: Bool = false) {
        self.name = name; self.installed = installed; self.latest = latest
        self.isCask = isCask; self.pinned = pinned
    }
}

public struct SearchHit: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let isCask: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
    public init(name: String, isCask: Bool) { self.name = name; self.isCask = isCask }
}

public struct BrewStatus: Codable, Equatable, Sendable {
    public let installed: Bool
    public let brewPath: String?
    /// The label of an operation that was still running when Helm last quit —
    /// the child brew survives the app, so the Cellar may have changed with no
    /// observer. Carried once, by the first `status()` of the next launch.
    /// Optional, so the synthesized decode reads an older payload without it.
    public let interruptedOp: String?
    public init(installed: Bool, brewPath: String?, interruptedOp: String? = nil) {
        self.installed = installed; self.brewPath = brewPath
        self.interruptedOp = interruptedOp
    }
}

/// What `brew info --json=v2` knows about one package.
///
/// A formula and a cask disagree about shape in three places — the install
/// facts, the name, the licence — which is why `BrewInfoParser` reads the
/// document by hand rather than through a synthesized decode: see that file's
/// doc comment for why a struct here does not save the work it looks like it
/// would.
public struct PackageInfo: Codable, Equatable, Sendable {
    public let name: String
    public let isCask: Bool
    public let desc: String?
    public let homepage: String?
    /// nil for every cask — the field does not exist in that document at all.
    public let license: String?
    public let tap: String?
    /// What Homebrew would install right now — a formula's `versions.stable`,
    /// a cask's `version`. nil when the document names neither.
    ///
    /// The only version a package that is **not** installed has: the lists the
    /// page draws its first tier from carry a version for an installed package
    /// and an outdated one, and `brew search` answers with names alone, so a
    /// search hit has no version anywhere else in this module.
    public let latestVersion: String?
    public let installedVersion: String?
    public let installedAt: Date?
    /// nil when not installed, and also nil for a cask, which never records
    /// who asked for it.
    public let installedOnRequest: Bool?
    /// nil unless the package is actually deprecated.
    public let deprecationReason: String?
    /// What to use instead, when Homebrew names one.
    public let replacement: String?
    public let siblings: [String]
    public let dependencies: [String]
    public let caveats: String?

    public init(name: String, isCask: Bool, desc: String?, homepage: String?, license: String?,
                tap: String?, latestVersion: String?, installedVersion: String?,
                installedAt: Date?, installedOnRequest: Bool?, deprecationReason: String?,
                replacement: String?, siblings: [String], dependencies: [String],
                caveats: String?) {
        self.name = name; self.isCask = isCask; self.desc = desc; self.homepage = homepage
        self.license = license; self.tap = tap; self.latestVersion = latestVersion
        self.installedVersion = installedVersion
        self.installedAt = installedAt; self.installedOnRequest = installedOnRequest
        self.deprecationReason = deprecationReason; self.replacement = replacement
        self.siblings = siblings; self.dependencies = dependencies; self.caveats = caveats
    }
}

public enum OpPhase: String, Codable, Sendable { case idle, running, done, failed }

/// Why a failed operation failed, when the engine knows more than an exit code.
///
/// A named outcome, never silence: each of these used to be a bare `return` (a
/// press that did nothing, visibly forever) or an exit code indistinguishable
/// from a build failure. The engine names the reason; the UI owns the words, so
/// the eight languages live where `L()` can reach them.
public enum OpFailureReason: String, Codable, Sendable, CaseIterable {
    /// brew vanished between `status()` and the press — Homebrew's own
    /// uninstaller ran in a terminal while Helm's window sat open.
    case brewMissing
    /// The person pressed Stop; the exit code is the signal, not a defect.
    /// (A timed-out *query* never comes through here: queries answer nil and
    /// the log names the outcome — an operation state about no operation
    /// would loop the view model's refresh-on-failure.)
    case stopped
    /// A `brew doctor` fix the engine re-judged and would not run.
    ///
    /// The ordinary cause is the race this design exists for: the page drew a
    /// button for `uninstall <name>` and the name left the Cellar before the
    /// press — a terminal, or Helm's own uninstall of it. It also covers an
    /// argv no entry on `DoctorFix.Allowed` admits, and a Cellar the engine
    /// could not read at all, which is not a Cellar the name is in. A refusal
    /// is an outcome and it is named: a press that answered nothing at all is
    /// the defect `AVanishedBrewIsNotASilentPressTests` was written against.
    case fixRefused
}

public struct OpState: Codable, Equatable, Sendable {
    public let phase: OpPhase
    public let label: String
    public let exitCode: Int?
    /// Optional, so the synthesized decode reads an older payload without it.
    public let reason: OpFailureReason?
    public init(phase: OpPhase, label: String, exitCode: Int? = nil,
                reason: OpFailureReason? = nil) {
        self.phase = phase; self.label = label; self.exitCode = exitCode
        self.reason = reason
    }
    public static let idle = OpState(phase: .idle, label: "")
}

/// How bad `brew doctor` thinks a finding is — the two prefixes it prints,
/// `Warning:` and `Error:`, named rather than reused as raw strings past
/// `DoctorParser`.
public enum DoctorSeverity: String, Codable, Sendable {
    case caution
    case danger
}

/// One block from `brew doctor`'s answer, produced by `DoctorParser.parse`.
///
/// `fix` is left nil by the parser — a command parsed out of a tool's output
/// is data, not an instruction, and judging one runnable is `DoctorFix.judge`'s
/// job alone (the module's security surface for this feature), not something
/// this struct or its parser may decide on construction.
public struct DoctorIssue: Codable, Equatable, Sendable, Identifiable {
    public let severity: DoctorSeverity
    public let title: String
    public let body: String
    public let fix: DoctorFix?
    /// Built from content rather than position: two blocks with the same text
    /// are the same issue, which is exactly the case `DoctorParser` collapses
    /// before this is ever read.
    public var id: String { severity.rawValue + "\u{0}" + title + "\u{0}" + body }
    public init(severity: DoctorSeverity, title: String, body: String, fix: DoctorFix? = nil) {
        self.severity = severity; self.title = title; self.body = body; self.fix = fix
    }
}
