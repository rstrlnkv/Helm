import Foundation

/// How a package is named once, everywhere.
///
/// A formula and a cask can share a name (`docker` is both), so neither the
/// row identity nor the description cache can be keyed by the name alone. Every
/// spelling of the key goes through here: a disagreement is silent, with
/// descriptions filed under keys the rows never ask for.
public enum BrewKey {
    public static func of(name: String, isCask: Bool) -> String {
        (isCask ? "c:" : "f:") + name
    }
}

/// What the UI hands over to name one package. A formula and a cask can share
/// a name, so the name alone does not say which one is meant.
public struct PackageRef: Equatable, Sendable {
    public let name: String
    public let isCask: Bool
    public init(name: String, isCask: Bool) { self.name = name; self.isCask = isCask }
}

/// A press on the engine: every act that starts a child, or ends one.
///
/// Exhaustive at the one `switch` that runs it (`HomebrewEngine.perform`), so
/// an act added here without an arm is a build error rather than a button that
/// does nothing.
public enum HomebrewAct: Equatable, Sendable {
    case install(PackageRef), uninstall(PackageRef)
    case upgrade(name: String), upgradeAll
    /// The argv itself (`["uninstall", "periphery"]`), which the engine
    /// **judges again** before running it (`HomebrewEngine.runDoctorFix`).
    case doctorFix(argv: [String])
    case installBrew
    /// End the running long operation, if any: operations have no deadline,
    /// because an install may honestly take an hour.
    case stop
}

/// What the engine says while a long operation runs, in the order it said it.
public enum HomebrewNews: Equatable, Sendable {
    /// One line of the tool's output, as it arrives.
    case line(String)
    /// A press refused because another operation holds the gate. A fact, not a
    /// state: the running operation's state is not written over.
    case busy
    /// Where the operation is now: running, done or failed.
    case state(OpState)
    /// Where brew is, said once when the module is switched on: `nil` is no brew.
    /// A reading of the locator only; it takes nothing off the marker
    /// (ARCHITECTURE.md § The model).
    case brew(path: String?)
}

/// The slots the engine files its three announcements in on `EngineNews`; each
/// keeps its own last value for a late subscriber. `HomebrewEngine`'s three `say`
/// calls are the one user.
enum HomebrewSlot: String, Sendable {
    case opLog
    case opState
    case brewFound
}

public struct BrewPackage: Equatable, Sendable, Identifiable {
    public let name: String
    public let version: String
    public let isCask: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
    init(name: String, version: String, isCask: Bool) {
        self.name = name; self.version = version; self.isCask = isCask
    }
}

public struct OutdatedPackage: Equatable, Sendable, Identifiable {
    public let name: String
    public let installed: String
    public let latest: String
    public let isCask: Bool
    /// Held at this version on purpose. brew still reports it as outdated and
    /// `brew upgrade` still refuses it, so a row that offers Upgrade offers a
    /// button that answers "…is pinned".
    public let pinned: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
    init(name: String, installed: String, latest: String, isCask: Bool,
                pinned: Bool = false) {
        self.name = name; self.installed = installed; self.latest = latest
        self.isCask = isCask; self.pinned = pinned
    }
}

public struct SearchHit: Equatable, Sendable, Identifiable {
    public let name: String
    public let isCask: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
    init(name: String, isCask: Bool) { self.name = name; self.isCask = isCask }
}

public struct BrewStatus: Equatable, Sendable {
    public let installed: Bool
    public let brewPath: String?
    /// The label of an operation that was still running when Helm last quit —
    /// the child brew survives the app, so the Cellar may have changed with no
    /// observer. Carried once, by the first `status()` of the next launch.
    public let interruptedOp: String?
    public init(installed: Bool, brewPath: String?, interruptedOp: String? = nil) {
        self.installed = installed; self.brewPath = brewPath
        self.interruptedOp = interruptedOp
    }
}

/// What `brew info --json=v2` knows about one package.
///
/// A formula and a cask disagree about shape in three places (the install
/// facts, the name, the licence), which is why `BrewInfoParser` reads the
/// document by hand.
public struct PackageInfo: Equatable, Sendable {
    public let name: String
    public let isCask: Bool
    let desc: String?
    public let homepage: String?
    /// nil for every cask — the field does not exist in that document at all.
    public let license: String?
    public let tap: String?
    /// What Homebrew would install right now — a formula's `versions.stable`,
    /// a cask's `version`. nil when the document names neither.
    ///
    /// The only version a package that is **not** installed has: `brew search`
    /// answers with names alone.
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

    init(name: String, isCask: Bool, desc: String?, homepage: String?, license: String?,
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

public enum OpPhase: String, Sendable { case idle, running, done, failed }

/// Why a failed operation failed, when the engine knows more than an exit code.
///
/// A named outcome, never silence or a bare exit code. The engine names the
/// reason; the UI owns the words, so the languages live where `L()` reaches.
public enum OpFailureReason: String, Sendable, CaseIterable {
    /// brew vanished between `status()` and the press — Homebrew's own
    /// uninstaller ran in a terminal while Helm's window sat open.
    case brewMissing
    /// The person pressed Stop; the exit code is the signal, not a defect.
    /// (A timed-out *query* never comes through here: an operation state about
    /// no operation would loop the view model's refresh-on-failure.)
    case stopped
    /// A `brew doctor` fix the engine re-judged and would not run: the name
    /// left the Cellar before the press, the argv is not on
    /// `DoctorFix.Allowed`, or the Cellar could not be read.
    case fixRefused
    /// Homebrew's installer needs Apple's Command Line Tools and they never
    /// arrived: Apple's window was closed without installing, or the request
    /// was refused. Nothing was changed; Install Homebrew asks again.
    case toolsNotInstalled
    /// The administrator dialog was answered no: a person's answer, not a
    /// defect.
    case authorizationDeclined
    /// Root was asked to create and hand over `/opt/homebrew` and the script
    /// failed. The exit code is on the state.
    case prefixNotPrepared
    /// Homebrew's own `install.sh` ended non-zero. The exit code is on the
    /// state; the last lines of its output are in the console.
    case installerFailed
    /// `installBrew` refused the account name before any dialog: it is not a
    /// plausible short name, and a root shell would evaluate it.
    case unsupportedAccount
}

/// What a running operation is waiting for, when it is waiting and not working.
///
/// A field on `OpState` and not an `OpPhase`: to everything that reads the
/// phase — the busy gate, Stop, Clear — waiting *is* running. What reads the
/// field itself is what draws the wait differently: the pill, Stop's title, and
/// the console, which says one line as the wait begins and another as it ends
/// (`HomebrewViewModel.consoleLine`).
public enum OpWait: String, Sendable, CaseIterable {
    /// Apple's Command Line Tools are being installed in Apple's own window.
    case commandLineTools
}

public struct OpState: Equatable, Sendable {
    public let phase: OpPhase
    public let label: String
    public let exitCode: Int?
    public let reason: OpFailureReason?
    public let waiting: OpWait?
    init(phase: OpPhase, label: String, exitCode: Int? = nil,
                reason: OpFailureReason? = nil, waiting: OpWait? = nil) {
        self.phase = phase; self.label = label; self.exitCode = exitCode
        self.reason = reason; self.waiting = waiting
    }
    public static let idle = OpState(phase: .idle, label: "")
}

/// How bad `brew doctor` thinks a finding is — the two prefixes it prints,
/// `Warning:` and `Error:`, named rather than reused as raw strings past
/// `DoctorParser`.
public enum DoctorSeverity: String, Sendable {
    case caution
    case danger
}

/// One block from `brew doctor`'s answer, produced by `DoctorParser.parse`.
///
/// `fix` is left nil by the parser: a command parsed out of a tool's output
/// is data, not an instruction, and judging one runnable is `DoctorFix.judge`'s
/// job alone.
public struct DoctorIssue: Equatable, Sendable, Identifiable {
    public let severity: DoctorSeverity
    public let title: String
    public let body: String
    public let fix: DoctorFix?
    /// Built from content rather than position: two blocks with the same text
    /// are the same issue, which `DoctorParser` collapses.
    public var id: String { severity.rawValue + "\u{0}" + title + "\u{0}" + body }
    init(severity: DoctorSeverity, title: String, body: String, fix: DoctorFix? = nil) {
        self.severity = severity; self.title = title; self.body = body; self.fix = fix
    }
}

/// Which heading one `brew config` line is drawn under.
///
/// **Ours, not Homebrew's.** `brew config` prints one flat list of
/// `key: value` lines with no headings; the three groups are Helm's reading,
/// which is why their names are translated and the keys never are. The
/// mapping is `BrewConfigParser.sections`.
public enum ConfigSection: String, Sendable, CaseIterable {
    /// Homebrew's own installation: its version, its prefix, its checkout, the
    /// Ruby it vendors.
    case brew
    /// The Mac underneath it: macOS, the processor, Rosetta.
    case machine
    /// The other programs Homebrew builds and downloads with — the compiler,
    /// git, curl, the Command Line Tools.
    case tools
}

/// One `key: value` line of `brew config`, and the heading it belongs under.
///
/// The key keeps Homebrew's own spelling and is never translated: `CLT`,
/// `HOMEBREW_PREFIX` and `Rosetta 2` are Homebrew's words for these things, and
/// a translated key would name something a person could not then look up.
public struct ConfigLine: Equatable, Sendable, Identifiable {
    public let key: String
    /// Everything after the **first** `: `: values carry colons of their own
    /// (`https://github.com/Homebrew/brew`, `4.0.6 => /opt/homebrew/…/ruby`).
    public let value: String
    public let section: ConfigSection
    /// The key, because `brew config` prints each key once; it lets a
    /// `ForEach` draw the lines without an index.
    public var id: String { key }
    init(key: String, value: String, section: ConfigSection) {
        self.key = key; self.value = value; self.section = section
    }
}

/// What `brew config` answered: the reading, **and the document it was read
/// from**.
///
/// The lines are a reading, regrouped under Helm's headings and short of what
/// the parser could not read. `text` is the document byte for byte, and it is
/// what «Copy for a bug report» copies: a bug report asks for what the tool
/// said, not for Helm's reading of it.
public struct BrewConfig: Equatable, Sendable {
    public let lines: [ConfigLine]
    public let text: String
    init(lines: [ConfigLine], text: String) { self.lines = lines; self.text = text }
}
