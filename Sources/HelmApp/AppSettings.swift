import AppKit
import Foundation
import HelmRuntime
import HelmUI
import Module_Disk_UI

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

    /// The stored look of the window's bar (`HelmBarAppearance`): flat unless Liquid Glass is stored. 
    /// Nothing unattended reads it, so it is not sealed; the two functions
    /// take the store the property hands them.
    static var barAppearance: HelmBarAppearance {
        get { barAppearance(in: store) }
        set { setBarAppearance(newValue, in: store) }
    }

    static func barAppearance(in store: NamespacedStore) -> HelmBarAppearance {
        HelmBarAppearance(stored: store.string(HelmBarAppearance.storageKey, default: ""))
    }

    static func setBarAppearance(_ value: HelmBarAppearance, in store: NamespacedStore) {
        store.set(value.rawValue, for: HelmBarAppearance.storageKey)
        NotificationCenter.default.post(name: .helmBarAppearanceChanged, object: nil)
    }

    /// How the header row names its page (`PageBarStyle`): with its plate unless Without Icon is stored.
    /// Nothing unattended reads it, so it is not sealed. A write equal to the stored value is refused, so
    /// nothing is posted for it.
    static var pageBarStyle: PageBarStyle {
        get { pageBarStyle(in: store) }
        set { setPageBarStyle(newValue, in: store) }
    }

    static func pageBarStyle(in store: NamespacedStore) -> PageBarStyle {
        PageBarStyle(stored: store.string(PageBarStyle.storageKey, default: ""))
    }

    static func setPageBarStyle(_ value: PageBarStyle, in store: NamespacedStore) {
        guard value != pageBarStyle(in: store) else { return }
        store.set(value.rawValue, for: PageBarStyle.storageKey)
        NotificationCenter.default.post(name: .helmHeaderChoicesChanged, object: nil)
    }

    /// How the header row's tabs are labelled (`HeaderTabLabels`): by text unless another is stored.
    /// Nothing unattended reads it, so it is not sealed; writes equal to the stored value are refused.
    static var tabLabels: HeaderTabLabels {
        get { tabLabels(in: store) }
        set { setTabLabels(newValue, in: store) }
    }

    static func tabLabels(in store: NamespacedStore) -> HeaderTabLabels {
        HeaderTabLabels(stored: store.string(HeaderTabLabels.storageKey, default: ""))
    }

    static func setTabLabels(_ value: HeaderTabLabels, in store: NamespacedStore) {
        guard value != tabLabels(in: store) else { return }
        store.set(value.rawValue, for: HeaderTabLabels.storageKey)
        NotificationCenter.default.post(name: .helmHeaderChoicesChanged, object: nil)
    }

    /// **Whether the header row's search rests as a 36 pt magnifier** while it is empty and nobody is editing it
    /// (`HelmHeaderSearch.rests`): chosen from the row's right-click menu (`HeaderBarMenu`). Off unless somebody
    /// turns it on. A query left in the field keeps it open. A `Bool` is bounded by its type and nothing
    /// unattended reads it, so it is not sealed; a write equal to the stored value is refused, so nothing is posted
    /// for it. The key is the toolbar's day one (`HelmHeaderChoices`), spelt here so `ObsoleteDefaultsTests`' scan covers it.
    static var alwaysCollapseSearch: Bool {
        get { alwaysCollapseSearch(in: store) }
        set { setAlwaysCollapseSearch(newValue, in: store) }
    }

    static func alwaysCollapseSearch(in store: NamespacedStore) -> Bool {
        store.bool("alwaysCollapseSearch", default: false)
    }

    static func setAlwaysCollapseSearch(_ value: Bool, in store: NamespacedStore) {
        guard value != alwaysCollapseSearch(in: store) else { return }
        store.set(value, for: "alwaysCollapseSearch")
        NotificationCenter.default.post(name: .helmHeaderChoicesChanged, object: nil)
    }

    /// The three choices as the header row reads them.
    static var headerChoices: HelmHeaderChoices {
        HelmHeaderChoices(pageBar: pageBarStyle, tabLabels: tabLabels,
                          collapseSearch: alwaysCollapseSearch)
    }

    /// **Whether the settings window's sidebar is folded to the rail**, as a person last left it
    /// (`SettingsShellViewController.flipSidebar`). A stored string, or a number other than 0 and 1, reads as
    /// expanded; a stored number 1 reads as folded. Read once, when a window is built, and nothing unattended reads it, so it is not
    /// sealed; the two functions take the store `SettingsShellViewController` holds (`AppSettings.store`).
    static func sidebarCollapsed(in store: NamespacedStore) -> Bool {
        store.bool("sidebarCollapsed", default: false)
    }

    static func setSidebarCollapsed(_ value: Bool, in store: NamespacedStore) {
        store.set(value, for: "sidebarCollapsed")
    }

    /// The language the interface is drawn in, or nil for the Mac's own.
    ///
    /// **Dev builds only** — `AppBuild.isDev` gates the row that writes it, and
    /// `applyStoredLanguage()` below refuses to read a stored value on any other build, so a
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
    /// true/false = the user overrode it in the Log page's toolbar menu.
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
    /// Declared once because two readers want it: the getter's own "nothing
    /// stored" answer (the warm read that never waits for the keychain goes
    /// through the getter), and the tests that hold them together.
    static let defaultDisabledScans: Set<String> = [DiskDescriptor.id.rawValue]

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
                // the app saw — `defaults write com.helm.app
                // module.app.disabledScans -array`, a full-volume walk switched
                // on unattended — was adopted and sealed as Helm's own. Day one
                // is Helm's.
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
                Self.setDisabledScans(Set(stored))
                return Set(stored)
            case .broken:
                HelmLog.shared.warn("scan", "the list of disabled scans is not Helm's own; "
                                    + "every background scan is off until it is set again")
                return Set(ScanRunner.scannableModules)
            }
        }
        set { Self.setDisabledScans(newValue) }
    }

    private static func setDisabledScans(_ newValue: Set<String>) {
        let sorted = Array(newValue).sorted()
        store.set(sorted, for: "disabledScans")
        store.set(scanGuard.seal(Self.payload(of: sorted)) ?? "",
                  for: SettingGuard.macKey(for: "disabledScans"))
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
    /// Behind `SettingsSealKey.overScanSettings`, so the keychain is asked once for the
    /// whole process rather than once per verdict: the getter above is read on
    /// every coordinator tick and, until 2026-08-15, inside the settings
    /// window's own construction — where the round trip is a modal
    /// authorization dialog on every ad-hoc build. `warmKey()` is how a screen
    /// pays for it off the main thread before it needs the answer.
    ///
    /// **Shared with the duplicate finder's guard, rather than a cache of its
    /// own.** It is the same item, and a cache serialises only the callers that
    /// share it — two caches over one item are two round trips, and the second
    /// is a second dialog for anyone who answers the first with "Allow".
    static var scanGuard = SettingGuard(keys: SettingsSealKey.overScanSettings)

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
    /// `PanelFooterSetting` holds their keys and their default.
    static func shows(_ button: PanelFooterSetting.Button) -> Bool {
        PanelFooterSetting.shows(button, in: store)
    }

    static func setShows(_ button: PanelFooterSetting.Button, _ on: Bool) {
        store.set(on, for: button.rawValue)
        NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
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
    /// string — and the next person to drop that literal for the type's own fallback would have
    /// moved everybody from L to M without touching a number. The answer is `MenuBarIconSize`'s, once.
    static var menuBarIconSize: MenuBarIconSize {
        get { MenuBarIconSize(stored: store.string("menuBarIconSize", default: "")) }
        set {
            store.set(newValue.rawValue, for: "menuBarIconSize")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }
}
