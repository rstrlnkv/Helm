import Foundation

/// One installed application as the latest catalog read found it. `id` is the bundle
/// identifier — the layout's only key; `path` is what a launch uses, and belongs to this read.
public struct CatalogApp: Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    /// The bundle's own `LSApplicationCategoryType`, raw (`public.app-category.music`), bounded; nil when it has none, an
    /// empty one or one that is not a string. Naming it for a person is the page's.
    public let category: String?
    /// When Finder says the bundle was added to its folder (`addedToDirectoryDateKey`). nil for an app under
    /// `/System/Applications` (a macOS update re-adds them all), a symlinked bundle, and a date that would not read.
    /// An app updated in place is added to its folder again, so it is recent for the 30 days after each update.
    public internal(set) var added: Date?

    init(id: String, name: String, path: String, category: String? = nil, added: Date? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.category = category
        self.added = added
    }
}

/// What a read of the installed applications found. `complete` is false when any directory
/// would not open or the walk stopped at the ceiling on apps, so a missing app may be one this
/// process could not see.
struct CatalogReading: Equatable, Sendable {
    let apps: [CatalogApp]
    let complete: Bool

    init(apps: [CatalogApp], complete: Bool) {
        self.apps = apps
        self.complete = complete
    }
}

/// The installed applications.
///
/// **Collapsed reasons.** A root that does not exist reads as empty and complete; a
/// directory that exists but would not open (`.refused`) makes `complete` false; an
/// application with no readable bundle identifier is skipped and counted in the log.
/// Duplicate ids collapse to one entry. A change in the installed set is seen by a
/// `read(reason:)`; `observeChanges` says when to ask again.
protocol AppCatalogPort: Sendable {
    /// `reason` is only for the `read N apps` line, which says what asked for each walk of the folders.
    func read(reason: CatalogReadReason) -> CatalogReading

    /// The bundle identifier of the application at `path`, read the way `read(reason:)` reads it.
    /// **nil collapses** a bundle that is not there, a property list that will not open or
    /// parse, one over the ceiling, and one with no identifier or an empty one: a caller that
    /// needs the reason has none to ask for, and takes every one of them as "not that app".
    func bundleID(atPath path: String) -> String?

    /// Calls `onChange` (on a queue of its own) when something in the watched folders may
    /// have changed an application, for as long as the returned token is held. Dropping the
    /// token ends it. A watch that could not start is logged and never calls: the next
    /// `read(reason:)` is then the only way to learn of a change.
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject
}

/// Opens an application. Every refusal — the system said no, nothing there to open — is `false`.
protocol AppLauncherPort: Sendable {
    func open(_ url: URL) async -> Bool
}

/// What asking the person to prove they are the Mac's owner came to. Each reason that a caller must tell apart is its own
/// case; nothing folds toward `success`, and only `success` opens anything.
///
/// - `success`: the system accepted Touch ID or the Mac's password.
/// - `failed`: the system said the proof was wrong (`LAError.authenticationFailed`).
/// - `cancelled`: the person cancelled, the system or Helm cancelled the dialog (`userCancel`, `systemCancel`, `appCancel`
///   from an invalidation), or the asking task was cancelled before or during the ask.
/// - `unavailable`: the Mac has no password or biometrics set, biometrics are locked out in a way that is not a plain failure,
///   the dialog could not be shown, no context could be made, this is a test process, or the system answered an error not
///   named here. The person can do nothing about it from inside Helm.
public enum AuthOutcome: Equatable, Sendable { case success, failed, cancelled, unavailable }

/// Asks the system for Touch ID or the Mac's password (`deviceOwnerAuthentication`); Helm never sees either. `reason` is the
/// sentence the system dialog shows.
public protocol LaunchpadAuthPort: Sendable {
    func evaluate(reason: String) async -> AuthOutcome
}

/// What a launch came to. `gone`: a complete read of the installed apps no longer holds the
/// id, or the bundle at its path answers another id. `unreadable`: the read was incomplete and
/// the id is not in it, so it may be an app this process could not see. `failed`: the system
/// refused to open it.
public enum LaunchOutcome: Equatable, Sendable {
    case launched, gone, unreadable, failed
}

/// What starting to watch the trackpads came to: a port answers the first three, and the engine records the fourth. Each reason is its own case, because the page says a different thing for
/// each and a caller that folded them would say the wrong one.
///
/// - `watching`: at least one trackpad is delivering frames; `devices` is how many.
/// - `noTrackpad`: the system lists none (a desktop Mac with a mouse), or this is a test process, which never asks.
/// - `frameworkMissing`: the private framework did not load or a symbol Helm needs is not in it (a macOS that moved it).
/// - `layoutRefused`: it loaded and delivered frames, but too many in a row failed `TouchFrame`'s checks, so the layout
///   Helm assumes is not the one in use; the engine ended the watch, and the person's switch turned off and on (or the
///   module activated again) watches again. A port never answers it from `start`; only the engine records it.
public enum TouchWatchStart: Equatable, Sendable {
    case watching(devices: Int)
    case noTrackpad
    case frameworkMissing
    case layoutRefused
}

/// The trackpads' raw fingers. Frames arrive on a thread of the system's own, about a hundred a second per pad, until
/// `stop()`; `start` while already started stops the first watch. A frame that fails `TouchFrame`'s checks is never
/// delivered; `onStandDown` is called once per start, from any thread, when too many were refused in a row: the port then
/// drops every frame and asks its owner to `stop()` it, which it does not do itself.
/// Helm reads these frames and writes nothing to a trackpad or its settings.
protocol TrackpadTouchPort: Sendable {
    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void, onStandDown: @escaping @Sendable () -> Void) -> TouchWatchStart
    func stop()
}

/// What the system's own four- and five-finger pinch is set to, read and never written.
///
/// **Collapsed reasons.** `unreadable` is every way the answer is not there: a domain that holds no such key (a Mac that never
/// changed it, or a macOS that names it otherwise), a value that is not a number, a read the system refused. A caller that
/// must tell them apart has no entry for it, and takes `unreadable` as "say nothing". `on`: some key in some trackpad domain
/// is a non-zero number. `off`: at least one key was read and every one read is zero.
public enum SystemPinch: Equatable, Sendable {
    case on, off, unreadable
}

protocol SystemPinchPort: Sendable {
    func read() -> SystemPinch
}

/// What asked for a catalog read, named on its log line: the window's first read (`open`), a change in the watched folders (`watch`), the model after
/// a launch (`launch`: when the app opened and a watcher other than the window's own is there, the settings page; when it was gone or unreadable,
/// always; a launch's own check is `launch` too), the model reading again after a refused edit (`refresh`), the settings page's own first read
/// (`settings`), the launch counts' reset (`reset`) and an edit with no read before it (`edit`).
public enum CatalogReadReason: String, Sendable {
    case open, watch, launch, refresh, settings, reset, edit
}
