import AppKit
import Foundation
import HelmRuntime
import HelmUI

extension Notification.Name {
    /// Posted when the host menu-bar icon style changes so the status item redraws.
    static let helmMenuBarStyleChanged = Notification.Name("helmMenuBarStyleChanged")
    /// Posted when the language override changes. Strings are computed on
    /// every read, so what needs telling is not the values but the views: a
    /// window already drawn keeps whatever it built.
    static let helmLanguageChanged = Notification.Name("helmLanguageChanged")
}

/// App-level (not per-module) settings, e.g. the menu-bar icon shape.
@MainActor enum AppSettings {
    /// The literal stays a literal, and `StoreNamespacesAreModuleIdsTests` says
    /// why: it is the host's own namespace, it names no module, and it is the
    /// one place that scan has left to find. A migration that needs the same
    /// namespace over another store asks this one for it (`over(_:)`) rather
    /// than spelling «app» a second time.
    static let store = NamespacedStore(namespace: "app", backing: UserDefaults.standard)

    /// Light, dark, or the system's choice. Applied to `NSApp`, which covers
    /// every window Helm owns, including the menu-bar panel.
    static var appearance: AppAppearance {
        get { AppAppearance.from(store.string("appearance", default: AppAppearance.system.rawValue)) }
        set {
            store.set(newValue.rawValue, for: "appearance")
            applyAppearance()
        }
    }

    /// Whether the sidebar draws each module on its own colour or as a plain
    /// glyph. Defaulted through `SidebarStyle(stored:)` rather than a literal
    /// here, so the fallback for an unknown value is written once and tested
    /// once — see `SidebarStyleTests`.
    static var sidebarStyle: SidebarStyle {
        get { SidebarStyle(stored: store.string(SidebarStyle.storageKey, default: "")) }
        set {
            store.set(newValue.rawValue, for: SidebarStyle.storageKey)
            NotificationCenter.default.post(name: .helmSidebarStyleChanged, object: nil)
        }
    }

    /// The language the interface is drawn in, or nil for the Mac's own.
    ///
    /// **Dev builds only** — `AppBuild.isDev` gates the row that writes it, and
    /// `apply()` below refuses to read a stored value on any other build, so a
    /// beta that once ran a dev build cannot come up in Japanese.
    ///
    /// It exists because checking a translation against the running app
    /// otherwise costs a logout: eight languages, and the only way to see the
    /// seventh was to change the Mac's own preference and start again.
    static var language: AppLanguage? {
        get { AppLanguage.override }
        set {
            AppLanguage.override = newValue
            store.set(newValue?.rawValue, for: languageKey)
            NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        }
    }

    private static let languageKey = "interfaceLanguage"

    /// Read once at launch, before anything draws a string.
    static func applyStoredLanguage() {
        guard AppBuild.isDev else { return }
        let stored = store.string(languageKey, default: "")
        AppLanguage.override = stored.isEmpty ? nil : AppLanguage(rawValue: stored)
    }

    static func applyAppearance() {
        NSApp.appearance = appearance.appearanceName.flatMap {
            NSAppearance(named: NSAppearance.Name($0))
        }
    }

    /// nil = follow the build type (dev builds log, stable builds don't);
    /// true/false = the user overrode it in Diagnostics.
    static var loggingOverride: Bool? {
        get {
            // -1 = follow the build type, 0/1 = explicit user choice.
            let raw = store.int("loggingOverride", default: -1)
            return raw < 0 ? nil : raw == 1
        }
        set {
            store.set(newValue.map { $0 ? 1 : 0 } ?? -1, for: "loggingOverride")
        }
    }

    /// What is off before anybody has said anything.
    ///
    /// Declared once because three readers want it: the getter's own "nothing
    /// stored" answer, the consent section on the General page, and the tests
    /// that hold the two together.
    static let defaultDisabledScans: Set<String> = ["disk"]

    /// Background scans the person switched off, by module id.
    ///
    /// An off-list rather than an on-list, so a scan added by a future version
    /// arrives switched on without a migration — the same shape the module
    /// enable flags use.
    ///
    /// Disk starts in it. The other two answer a question the person asked by
    /// installing the module; Disk builds and refreshes an 8 MB index of every
    /// filename on the volume, on machines whose owner never ran a disk scan.
    ///
    /// **Sealed, because it decides whether an unattended reader reads at all.**
    /// Any process running as this user can rewrite this plist, and taking Disk
    /// out of the off-list turns on a walk of every filename on the volume with
    /// nobody at the desk. A value that is not Helm's own is not "the person
    /// changed their mind": it refuses every scan, which is the safe direction
    /// and the one a person can see in the log.
    static var disabledScans: Set<String> {
        get {
            guard let stored = store.object("disabledScans") as? [String] else {
                // Nothing stored, and this is where the seal's one door used to
                // stand open: `.adopt` is granted while the keychain item does
                // not exist, and returning here never created it. So no
                // installation ever spent its own first use, and the first value
                // the app saw — `defaults write com.helm.app disabledScans
                // -array`, a full-volume walk switched on unattended — was
                // adopted and sealed as Helm's own. Day one is Helm's.
                scanGuard.establishKey()
                return defaultDisabledScans
            }
            switch scanGuard.verdict(payload: Self.payload(of: stored),
                                     mac: store.string(SettingGuard.macKey(for: "disabledScans"),
                                                       default: "")) {
            case .sealed:
                return Set(stored)
            case .adopt:
                // This installation has never sealed anything: the value predates
                // sealing, so it is accepted once and sealed on the way out.
                disabledScans = Set(stored)
                return Set(stored)
            case .broken:
                HelmLog.shared.warn("scan", "the list of disabled scans is not Helm's own; "
                                    + "every background scan is off until it is set again")
                return Set(ScanRunner.scannableModules)
            }
        }
        set {
            let sorted = Array(newValue).sorted()
            store.set(sorted, for: "disabledScans")
            store.set(scanGuard.seal(Self.payload(of: sorted)) ?? "",
                      for: SettingGuard.macKey(for: "disabledScans"))
        }
    }

    /// The same off-list, but only if answering it is free.
    ///
    /// **The getter above cannot be read from the thread that draws**, and this
    /// type is `@MainActor`, so every reader of it is on that thread. Verifying
    /// the seal needs the key, the key comes from the login keychain, and on an
    /// ad-hoc build a keychain read is a modal authorization dialog: measured on
    /// the owner's Mac as `HelmApp_2026-08-19-235500_MacBook.hang`, 19,09 s of a
    /// settings window that could not answer a mouse-up while `warmKey()` sat in
    /// securityd (`SealKeyCache` § Two locks has the other half of that story).
    ///
    /// Nil is **«not yet»**, a third answer beside `.sealed` and `.broken`, and
    /// the screens hold it as `Set<String>?` for exactly that reason: an empty
    /// set means every scan is on, and standing in for "not read" with it would
    /// show a whole-volume walk switched on to somebody who never said so.
    /// `SettingGuard.warmKey()` is what turns nil into an answer.
    ///
    /// One line rather than a second copy of the branches above, and that is the
    /// point: `isWarm` is only ever false → true, so once it is true every ask
    /// the getter makes — the verdict, the key `.adopt` seals with, the item the
    /// fresh-install branch establishes — is a memory read.
    static var disabledScansIfWarm: Set<String>? {
        scanGuard.isWarm ? disabledScans : nil
    }

    /// The bytes the seal is over. Sorted before sealing, so the same set never
    /// hashes two ways and a re-ordering by anything else is not mistaken for a
    /// forgery.
    private static func payload(of ids: [String]) -> Data {
        Data(ids.sorted().joined(separator: "\n").utf8)
    }

    /// One keychain item for the settings Helm seals in its own namespace.
    /// Autopilot keeps its own — that item is deployed, and moving it would read
    /// as "somebody rewrote your rules" on every Mac that has run it.
    ///
    /// A `var` for one reason, stated so nobody has to guess at it: a test must
    /// not write to the person's login keychain, and this type is reached
    /// statically from every page in the app. Nothing in the app assigns it.
    ///
    /// Behind `SealKeyCache`, so the keychain is asked once for the whole
    /// process rather than once per verdict: the getter above is read on every
    /// coordinator tick and, until 2026-08-15, inside the settings window's own
    /// construction — where the round trip is a modal authorization dialog on
    /// every ad-hoc build. `warmKey()` is how a screen pays for it off the main
    /// thread before it needs the answer.
    static var scanGuard = SettingGuard(
        keys: SealKeyCache(KeychainSealKey(service: "com.helm.app",
                                           account: "settings-seal",
                                           category: "scan")))

    /// When each background scan last **completed** — came back with a report.
    ///
    /// The comment used to say this while the coordinator wrote it at the start
    /// of every attempt, which is what made the day's second run unreachable:
    /// see `lastScanAttemptAt`.
    static var lastScanAt: [String: Date] {
        get { store.doubleTable("lastScanAt").mapValues(Date.init(timeIntervalSince1970:)) }
        set { store.set(newValue.mapValues(\.timeIntervalSince1970), for: "lastScanAt") }
    }

    /// When each background scan was last **started**, answered or not.
    ///
    /// A scan that comes back with nothing has measured nothing — a refused
    /// root, a cancelled walk, a directory it could not read — so it must not
    /// hold the module for a day; it holds it for `ScanSchedule.retryInterval`.
    /// This is also what stops a second scan of the same module starting a
    /// minute later if the app is restarted mid-walk, which `inFlight` cannot
    /// answer for because it dies with the process.
    static var lastScanAttemptAt: [String: Date] {
        get { store.doubleTable("lastScanAttemptAt").mapValues(Date.init(timeIntervalSince1970:)) }
        set { store.set(newValue.mapValues(\.timeIntervalSince1970), for: "lastScanAttemptAt") }
    }

    /// How many times each scan ran today. Reset when the calendar day turns.
    static var scanRunsToday: [String: Int] {
        get { store.intTable("scanRunsToday") }
        set { store.set(newValue, for: "scanRunsToday") }
    }

    /// The calendar day `scanRunsToday` is counting.
    static var scanBudgetDay: Date? {
        get {
            let stored = store.double("scanBudgetDay", default: 0)
            return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
        }
        set { store.set(newValue?.timeIntervalSince1970 ?? 0, for: "scanBudgetDay") }
    }

    /// The three buttons at the foot of the panel, each its own switch.
    /// `PanelFooterSetting` holds their keys, their default and the migration
    /// out of the one key they spent a build folded into.
    static var showSettingsButton: Bool {
        get { PanelFooterSetting.shows(.settings, in: store) }
        set { show(.settings, newValue) }
    }

    static var showPanelEditButton: Bool {
        get { PanelFooterSetting.shows(.edit, in: store) }
        set { show(.edit, newValue) }
    }

    static var showQuitButton: Bool {
        get { PanelFooterSetting.shows(.quit, in: store) }
        set { show(.quit, newValue) }
    }

    private static func show(_ button: PanelFooterSetting.Button, _ on: Bool) {
        store.set(on, for: button.rawValue)
        NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
    }

    /// How the panel's tabs are labelled. App-wide rather than per tab: it is a
    /// question about the strip, and a strip where one tab shows a word and the
    /// next shows a symbol is not a strip. `TabStripFit` turns the answer into
    /// what a tab actually wears, which is not always the same thing.
    static var tabLabelStyle: TabLabelStyle {
        get { TabLabelStyle(stored: store.string("tabLabelStyle", default: "")) }
        set {
            store.set(newValue.rawValue, for: "tabLabelStyle")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }

    /// Reads what the retired keys still have to say, then lets them go.
    ///
    /// **One function because the order is the whole of it.** The unfold reads
    /// `showPanelFooter`, which `ObsoleteDefaults` is about to delete, so a purge
    /// that ran first would hand every panel the default instead of the
    /// arrangement its owner chose — and two calls at the call site is an
    /// ordering somebody has to remember. There is nothing to remember here.
    ///
    /// **The store is a parameter, never a default.** A forgetful call taking
    /// `UserDefaults.standard` would make every test of this an edit of the
    /// settings the test is about.
    static func migrateAndPurge(in backing: KeyValueStore) {
        PanelFooterSetting.restore(in: store.over(backing))
        ObsoleteDefaults.purge(from: backing)
    }

    /// The shape Helm wears in the menu bar. Typed, so the fallback for a value
    /// this build does not know lives on `MenuBarIconStyle` and nowhere else.
    static var menuBarIconStyle: MenuBarIconStyle {
        get { MenuBarIconStyle(stored: store.string("menuBarIconStyle", default: "")) }
        set {
            store.set(newValue.rawValue, for: "menuBarIconStyle")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }

    /// The same, and it is the reason this one is typed too. It read
    /// `default: "small"` here while `MenuBarIconSize(stored:)` fell back to
    /// `.extraSmall`: 15 pt and «L» against 13 pt and «M», two defaults for one
    /// setting. Nobody saw it, because the only reader always passed a non-empty
    /// string — and the next person to follow `sidebarStyle`'s pattern, which is
    /// written one property above, would have moved everybody from L to M
    /// without touching a number. The answer is `MenuBarIconSize`'s, once.
    static var menuBarIconSize: MenuBarIconSize {
        get { MenuBarIconSize(stored: store.string("menuBarIconSize", default: "")) }
        set {
            store.set(newValue.rawValue, for: "menuBarIconSize")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }
}
