import Foundation

public enum StaleKind: String, Codable, Sendable, CaseIterable {
    case launchAgent      // ~/Library/LaunchAgents, /Library/LaunchAgents
    case launchDaemon     // /Library/LaunchDaemons
    case preference       // ~/Library/Preferences/*.plist
    case systemExtension   // an extension whose host app is gone
    case plugin           // QuickLook, PreferencePanes, Internet Plug-Ins, Audio
}

/// Why an item appears in the list. Everything found is shown — hiding what
/// is in use leaves the user trusting a list they cannot check.
public enum ItemStatus: String, Codable, Sendable, Equatable {
    /// The owner is gone: safe to remove.
    case orphaned
    /// Belongs to installed software, or points at a file that exists.
    case inUse
    /// Apple's, shared plumbing, or a system location: never removable.
    case protectedItem
    /// The job's own definition could not be read — corrupt, truncated, an array
    /// at the root, or a file this process may not open. Not a leftover: the
    /// scanner's rule is that anything whose owner cannot be identified stays
    /// put, and a file whose contents nobody could read is the plainest case of
    /// one. It used to be folded into «this job has no `Program`» → «points at
    /// nothing» → `.orphaned`, which is a tick from «Select all» and a place in
    /// the batch (`APlistNobodyCouldReadTests`).
    case unreadable
    /// The file read fine and a reading its verdict depends on did not happen, so
    /// Helm cannot say whether anything still uses it.
    ///
    /// Two readings put a row here, and neither is about this file: the existence
    /// of the program the job points at, when it sits in a directory this process
    /// may not search (`LeftoversFilePort.exists` → nil), and the list of what
    /// macOS has loaded, when the tool that answers it did not
    /// (`LoadedItemsPort.installedExtensions` → nil).
    ///
    /// **Its own case rather than `.unreadable`**, which is the sentence
    /// «Helm could not read this file» — false of both of these, and drawn over a
    /// plist that reads perfectly. ARCHITECTURE.md § A nil from a system read can
    /// be folding two questions into one is the rule being followed: a reason that
    /// needs telling apart gets named, not read out of a shared one.
    case undetermined

    /// Whether this status is a verdict about the item at all.
    ///
    /// Two of the five are the *absence* of one, and the page had no way to ask:
    /// neither is `.orphaned`, so the default filter drops both, the list comes
    /// out empty and «No leftovers found» — this module's strongest claim about
    /// somebody's Mac — was drawn under a green check over items nobody had
    /// judged. `LeftoversEmpty.reason` counts the unjudged ones through this.
    ///
    /// Exhaustive on purpose: a sixth status has to be placed on one side of this
    /// line by whoever adds it, and a `default` here is how one would come to be
    /// counted as a verdict it never reached.
    public var judged: Bool {
        switch self {
        case .orphaned, .inUse, .protectedItem: true
        case .unreadable, .undetermined: false
        }
    }
}

public struct StaleItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let identifier: String
    public let kind: StaleKind
    public let sizeBytes: Int
    /// What the job points at, when it names an executable that is missing.
    public let missingTarget: String?
    /// Loaded at login — worth flagging, since removing it changes behaviour.
    public let runAtLoad: Bool
    public let status: ItemStatus
    /// Switched off through launchd's own disabled list, not deleted.
    public let disabled: Bool
    /// Whether Helm can move this file without an admin password.
    public let writable: Bool

    /// What the checkbox offers: clearing leftovers in bulk. Anything in use
    /// is deleted one at a time, through the row's own menu, so a careless
    /// "select all" can never take out working software.
    ///
    /// Asked of the same rule the row's menu obeys, not a second one written
    /// beside it. The two had already parted: the menu withholds delete from a
    /// launch daemon, because unloading one needs root and a button that always
    /// fails is worse than no button — while the checkbox offered it, "Select
    /// all" ticked it, and `RemovableScope` lets `/Library/LaunchDaemons/*.plist`
    /// through, so the batch went ahead and tried. The safer of two answers has
    /// to be the only answer.
    public var removable: Bool {
        status == .orphaned && actions.contains(.delete)
    }

    public init(path: String, identifier: String, kind: StaleKind, sizeBytes: Int,
                missingTarget: String? = nil, runAtLoad: Bool = false,
                status: ItemStatus = .orphaned, disabled: Bool = false,
                writable: Bool = true) {
        self.path = path
        self.identifier = identifier
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.missingTarget = missingTarget
        self.runAtLoad = runAtLoad
        self.status = status
        self.disabled = disabled
        self.writable = writable
    }

    /// The one call into `LeftoverActions`, and the answer `removable` and
    /// `canToggle` are read off. All three used to call it themselves — the same
    /// question asked three ways, which is how the checkbox and the row's menu
    /// came to disagree about a launch daemon in the first place.
    public var actions: Set<LeftoverAction> {
        LeftoverActions.available(for: self)
    }

    /// Whether Helm can switch this one off without a password.
    /// Asked of the rule the row's menu obeys.
    ///
    /// There were two, and they disagreed about a protected agent — the second
    /// took a `status` and never read it, which is exactly the argument that
    /// would have caught it. Deleted rather than merged: everything it said is
    /// already here, and what it did not say was the bug.
    public var canToggle: Bool { actions.contains(.turnOff) }
}

/// Which login item to switch, and which way.
///
/// **The file comes with the label, because the label alone cannot be checked.** A
/// label is whatever string a `.plist` put in its `Label` key, and a file may claim
/// another job's — so the engine, which is the last word on what happens to
/// somebody's login items, needs the path to ask whether this label is the one that
/// file would register (`LaunchLabel.mayBeSwitched`).
public struct LeftoversToggle: Codable, Sendable {
    public let label: String
    public let path: String
    public let disabled: Bool
    public init(label: String, path: String, disabled: Bool) {
        self.label = label; self.path = path; self.disabled = disabled
    }
}
