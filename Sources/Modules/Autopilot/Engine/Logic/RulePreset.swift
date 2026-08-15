import Foundation

/// A rule somebody can have without writing one.
///
/// **A preset is an ordinary rule with a fixed id, and deliberately nothing
/// else.** Everything this module already does is keyed to a `Rule` — the stamp
/// that stops a rule acting twice, the thirty-day history, the return, the dry
/// run — and a preset that were its own entity would need a second copy of all
/// of it. So there is no "preset" in storage: what is stored is the rule, and
/// the id is what makes «already added» answerable, survives the rule being
/// renamed and edited, and lets the same preset be offered again after it is
/// deleted.
///
/// Only transit folders, and only their own contents. Both of these are the
/// module's existing rules read from the other side: a rule that reaches into
/// subfolders is how a tidy Downloads folder becomes a rearranged project tree,
/// and a preset that pointed at somebody's Documents would be a stranger's
/// judgement about files they never showed anyone.
public struct RulePreset: Equatable, Sendable, Identifiable {
    public let kind: PresetKind
    public let folder: PresetFolder
    public let match: RuleMatch
    public let conditions: [RuleCondition]
    public let action: PresetAction

    /// The rule's id as well as the preset's, which is the whole mechanism.
    public var id: String { kind.rawValue }

    /// This preset as the rule it is, under the name the reader's language gives
    /// it and inside the folder this Mac keeps.
    ///
    /// The name is the one part that is not the engine's: five names in eight
    /// languages are `HelmUI`'s work, and an engine that spelled them would be
    /// the second place they live. Nothing else about the rule depends on it —
    /// the id does not, so renaming a preset in the editor leaves it the same
    /// preset.
    public func rule(named name: String, in folderPath: String) -> Rule {
        Rule(id: id, name: name, enabled: true, match: match,
             conditions: conditions, action: action.action(in: folderPath))
    }
}

/// The five, named. A case rather than a bare string so the switches that build
/// them and name them are exhaustive: a sixth preset is then a build error in
/// both places rather than an id with nothing behind it.
public enum PresetKind: String, CaseIterable, Sendable {
    /// The one condition pair that is about what a file *is* rather than what it
    /// is called. macOS names a screenshot in the language of the system and
    /// nothing in the Screenshot bundle or in `screencapture` publishes that
    /// prefix, so a rule matching the name would work on one Mac and silently
    /// never fire on the next.
    case screenshots = "preset.screenshots"
    case downloadsByKind = "preset.downloads-by-kind"
    case oldInstallers = "preset.old-installers"
    case largeDownloads = "preset.large-downloads"
    case desktopByMonth = "preset.desktop-by-month"
}

/// Which of the person's own folders a preset watches.
///
/// Two, and both are transit: things arrive there on their way to somewhere
/// else, which is the only place an unattended rule earns its keep.
public enum PresetFolder: String, CaseIterable, Sendable {
    case desktop, downloads
}

/// What a preset does, before the folder it runs in is known.
///
/// `RuleAction.move` names an absolute path, and a preset cannot: the folder it
/// moves into is inside the folder it watches, and where that folder is, is this
/// Mac's answer rather than a constant. So the destination is a *name* here and
/// becomes a path when the folder does.
///
/// Exhaustive at `action(in:)` on purpose, like every other switch over
/// something this module defines.
public enum PresetAction: Equatable, Sendable {
    /// A folder of this name beside the files. The name is English and never
    /// translated — the same law `SortBucket` keeps for the buckets a sorting
    /// rule makes, and for the same reason: a name that changed with the app's
    /// language would make a second folder the day somebody switches.
    case moveIntoFolderNamed(String)
    case sortIntoSubfolder(SortScheme)
    case addTag(String)
    case trash

    public func action(in folderPath: String) -> RuleAction {
        switch self {
        case let .moveIntoFolderNamed(name):
            .move(to: URL(fileURLWithPath: folderPath).appendingPathComponent(name).path)
        case let .sortIntoSubfolder(scheme): .sortIntoSubfolder(scheme)
        case let .addTag(tag): .addTag(tag)
        case .trash: .trash
        }
    }
}

public extension RulePreset {

    /// The five, in the order they are offered.
    ///
    /// Screenshots stands above «Desktop sorted by month» because both watch the
    /// Desktop and the first match wins: a screenshot older than thirty days
    /// belongs in `Screenshots`, and a person who adds both sees exactly that in
    /// the dry run.
    static let all: [RulePreset] = PresetKind.allCases.map(RulePreset.init(kind:))

    /// What each one is. The switch has no `default`, so a sixth kind cannot be
    /// declared without being described.
    init(kind: PresetKind) {
        switch kind {
        case .screenshots:
            self.init(kind: kind, folder: .desktop, match: .all,
                      conditions: [.kind(.image), .fileExtension(["png"])],
                      action: .moveIntoFolderNamed("Screenshots"))
        case .downloadsByKind:
            // Seven days, so a download somebody is still working with this week
            // is left where they put it.
            self.init(kind: kind, folder: .downloads, match: .all,
                      conditions: [.dateAdded(.olderThan, days: 7)],
                      action: .sortIntoSubfolder(.kind))
        case .oldInstallers:
            self.init(kind: kind, folder: .downloads, match: .all,
                      conditions: [.fileExtension(["dmg", "pkg"]),
                                   .dateAdded(.olderThan, days: 30)],
                      action: .trash)
        case .largeDownloads:
            // The one preset that moves nothing. A tag is reversible by hand and
            // visible in Finder, which makes it the right first thing to hand
            // somebody who has never let an app tidy anything.
            self.init(kind: kind, folder: .downloads, match: .all,
                      conditions: [.size(.largerThan, megabytes: 500)],
                      action: .addTag("Large"))
        case .desktopByMonth:
            self.init(kind: kind, folder: .desktop, match: .all,
                      conditions: [.dateAdded(.olderThan, days: 30)],
                      action: .sortIntoSubfolder(.month))
        }
    }
}

/// Where this Mac keeps the two folders the presets are about.
///
/// A port, because it is the one part of a preset that is not a constant:
/// `~/Downloads` can be moved, and a Mac in another language keeps it under the
/// same path with a different display name. Reading the path out of
/// `FileManager` is the only way to be right about both — and a seam is what
/// lets a test stand a moved Downloads, or one that leads out of the home
/// directory, in front of the gate.
public protocol PresetFolderPort: Sendable {
    /// The folder's path, or nothing when the system will not say — which is
    /// not «the default place»: guessing `~/Downloads` for a Mac that keeps it
    /// elsewhere is how a rule comes to watch a folder nobody meant.
    func path(of folder: PresetFolder) -> String?
}

/// The production answer: whatever `FileManager` says, resolved for this user.
public struct SystemPresetFolders: PresetFolderPort {
    public init() {}

    public func path(of folder: PresetFolder) -> String? {
        let directory: FileManager.SearchPathDirectory = switch folder {
        case .desktop: .desktopDirectory
        case .downloads: .downloadsDirectory
        }
        return try? FileManager.default
            .url(for: directory, in: .userDomainMask, appropriateFor: nil, create: false)
            .path
    }
}

/// A preset the person may actually be offered, with the folder it would run in.
public struct OfferedPreset: Equatable, Sendable, Identifiable {
    public let preset: RulePreset
    /// The folder as it would be watched: the one already in the list when Helm
    /// is watching it, and otherwise a new one that is not stored anywhere yet.
    public let folder: WatchedFolder
    /// Whether Helm is not watching that folder yet.
    ///
    /// **The one condition under which a save is followed by a sweep.** Adding a
    /// rule to a folder somebody already watches and then sweeping it would run
    /// *their* other rules over everything in it, which is not what pressing
    /// Done on a preset asked for.
    public let folderIsNew: Bool

    public var id: String { preset.id }

    public init(preset: RulePreset, folder: WatchedFolder, folderIsNew: Bool) {
        self.preset = preset
        self.folder = folder
        self.folderIsNew = folderIsNew
    }
}

/// Which presets are worth putting on screen.
public enum PresetOffer {

    /// The presets not already added, whose folder this Mac will name and a rule
    /// may watch.
    ///
    /// Refusals are silent by design: a preset whose folder fails `WatchScope`
    /// is not offered at all rather than offered and refused on press. There is
    /// nothing for the person to do about it — the gate is positional, and a
    /// `~/Downloads` that leads outside the home directory is a decision
    /// somebody made about their own Mac — and a button that cannot work is
    /// worse than no button.
    ///
    /// **One draft folder per path.** Two of the five watch Downloads, and a
    /// separate `WatchedFolder` value for each would carry a separate id: adding
    /// both would then store the same folder twice, with one rule in each, and
    /// the second copy's rules would never be reached.
    public static func offered(_ presets: [RulePreset] = RulePreset.all,
                               watching folders: [WatchedFolder],
                               paths: some PresetFolderPort,
                               home: String = NSHomeDirectory()) -> [OfferedPreset] {
        let added = Set(folders.flatMap { $0.rules.map(\.id) })
        var drafts: [String: WatchedFolder] = [:]
        return presets.compactMap { preset in
            // By id, so a preset that was renamed, edited or moved down the list
            // is still the preset that was added.
            guard !added.contains(preset.id),
                  let path = paths.path(of: preset.folder),
                  WatchScope.allows(path, home: home)
            else { return nil }
            if let watched = folders.first(where: { $0.path == path }) {
                return OfferedPreset(preset: preset, folder: watched, folderIsNew: false)
            }
            let draft = drafts[path] ?? WatchedFolder(path: path)
            drafts[path] = draft
            return OfferedPreset(preset: preset, folder: draft, folderIsNew: true)
        }
    }
}
