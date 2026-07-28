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
        status == .orphaned
            && LeftoverActions.available(for: self, writable: writable).contains(.delete)
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

    public var actions: Set<LeftoverAction> {
        LeftoverActions.available(for: self, writable: writable)
    }

    /// Whether Helm can switch this one off without a password.
    /// Asked of the rule the row's menu obeys.
    ///
    /// There were two, and they disagreed about a protected agent — the second
    /// took a `status` and never read it, which is exactly the argument that
    /// would have caught it. Deleted rather than merged: everything it said is
    /// already here, and what it did not say was the bug.
    public var canToggle: Bool {
        LeftoverActions.available(for: self, writable: writable).contains(.turnOff)
    }
}

/// Which login item to switch, and which way.
public struct LeftoversToggle: Codable, Sendable {
    public let label: String
    public let disabled: Bool
    public init(label: String, disabled: Bool) {
        self.label = label; self.disabled = disabled
    }
}
