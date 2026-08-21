import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp

/// **The three footer switches and the tab-label pop-up are settings again, and
/// nobody's answer was lost on the way back.**
///
/// They were folded into one `showPanelFooter` for one unreleased build, and the
/// four keys went into `ObsoleteDefaults.retired` — which really deletes. So the
/// way back has two halves that fail differently: the keys must leave that list,
/// or the next launch purges what a person has just chosen; and the fold has to
/// be read before it is retired in its turn, or somebody who hid their footer is
/// handed one back.
///
/// **The asymmetry is the whole of it.** `showPanelFooter == false` is the one
/// state that was a deliberate choice — three switches turned off by hand — and
/// it is the only one the migration writes anything for. True, or never written,
/// is what the fold produced for everybody who never touched them, and that is
/// the shipped default: all three on.
///
/// Every store here is an `InMemoryKeyValueStore`. `migrateAndPurge` takes the
/// store it works on rather than defaulting to one, so a forgetful call cannot
/// reach into this Mac's own `com.helm.app` domain and rewrite the settings
/// these tests are about — and what is read back is `AppSettings.store.over(_:)`,
/// the app's own namespaced view pointed at that store, so an assertion here is
/// about the keys a panel really reads.
@MainActor
final class ThreeSwitchesComeBackFromOneTests: XCTestCase {

    // MARK: - The list that deletes

    /// A restored setting still named in `retired` is a setting purged at the
    /// next launch, which is indistinguishable from never having restored it.
    func testTheRestoredKeysAreNoLongerRetired() {
        for key in ["module.app.showSettingsButton", "module.app.showPanelEditButton",
                    "module.app.showQuitButton", "module.app.tabLabelStyle"] {
            XCTAssertFalse(ObsoleteDefaults.retired.contains(key), """
                \(key) is a setting again and is still on the purge list, so the launch \
                after the one that saves it deletes it.
                """)
        }
    }

    /// And the key that replaced them is on it, spelled the way `ObsoleteDefaults`
    /// has to spell it — namespaced, from the one place `HelmApp` names it. The
    /// two targets cannot see each other's constant, so this is where the two
    /// spellings are put side by side.
    func testTheFoldedKeyIsRetiredInTheirPlace() {
        XCTAssertTrue(
            ObsoleteDefaults.retired.contains("module.app." + PanelFooterSetting.foldedKey),
            "the fold's own key outlives the fold, and is read once more at every launch")
    }

    // MARK: - Both directions, through the store the app reads

    /// The person who hid their footer. Three switches off by hand became one
    /// `false`, and the three keys were then erased — so `false` is all that is
    /// left of the only deliberate answer in the whole migration.
    func testAHiddenFooterComesBackAsThreeButtonsHidden() {
        let store = migrated(["module.app.showPanelFooter": false])
        for button in PanelFooterSetting.Button.allCases {
            XCTAssertFalse(PanelFooterSetting.shows(button, in: store),
                           "\(button.rawValue) came back on for somebody who had hidden it")
        }
    }

    /// The person who never touched them — which is everybody else, because the
    /// fold wrote `true` whenever it found nothing to fold.
    func testAFooterThatWasShownComesBackAsThreeButtonsShown() {
        let store = migrated(["module.app.showPanelFooter": true])
        for button in PanelFooterSetting.Button.allCases {
            XCTAssertTrue(PanelFooterSetting.shows(button, in: store),
                          "\(button.rawValue) came back off for somebody who had a footer")
        }
    }

    /// A clean install, and a machine that never ran the folded build: nothing
    /// stored anywhere, and the shipped default is a footer.
    func testAFreshInstallHasAllThree() {
        let store = migrated([:])
        for button in PanelFooterSetting.Button.allCases {
            XCTAssertTrue(PanelFooterSetting.shows(button, in: store))
        }
    }

    /// The migration writes nothing it does not have to. A `true` fold is the
    /// default said out loud, so the three keys stay unwritten — and somebody
    /// who turns one off later is turning off a key, not correcting one.
    func testAShownFooterLeavesTheThreeKeysUnwritten() {
        let raw = migratedRaw(["module.app.showPanelFooter": true])
        for button in PanelFooterSetting.Button.allCases {
            XCTAssertNil(raw["module.app." + button.rawValue],
                         "the default was written out as though it were a choice")
        }
    }

    /// Somebody who is already back on a build with the three switches, and has
    /// used them. A fold left over from a build in between must not overwrite
    /// what they have since chosen.
    func testAnswersGivenSinceTheRestorationSurvive() {
        let store = migrated(["module.app.showPanelFooter": false,
                              "module.app.showQuitButton": true])
        XCTAssertTrue(PanelFooterSetting.shows(.quit, in: store),
                      "a switch turned on after the restoration was folded back off")
        XCTAssertTrue(PanelFooterSetting.shows(.settings, in: store),
                      "and its two siblings were pulled down with it")
    }

    /// Run twice, as a second launch runs it: the fold's key is purged in the
    /// same pass that reads it, so there is nothing left to migrate from.
    func testASecondLaunchChangesNothing() {
        let store = InMemoryKeyValueStore()
        store.raw = ["module.app.showPanelFooter": false]
        AppSettings.migrateAndPurge(in: store)
        AppSettings.migrateAndPurge(in: store)
        let app = AppSettings.store.over(store)
        for button in PanelFooterSetting.Button.allCases {
            XCTAssertFalse(PanelFooterSetting.shows(button, in: app),
                           "the second launch handed \(button.rawValue) back")
        }
        XCTAssertNil(store.raw["module.app.showPanelFooter"],
                     "the fold's key survived the purge that is meant to end it")
    }

    // MARK: - The pop-up

    /// `tabLabelStyle` was deleted outright rather than folded, so there is
    /// nothing to migrate from: what it comes back as is its own default, and
    /// that is the one it shipped with.
    func testAPurgedTabLabelStyleComesBackAsNames() {
        let store = migrated(["module.app.showPanelFooter": true])
        XCTAssertEqual(TabLabelStyle(stored: store.string("tabLabelStyle", default: "")), .text,
                       "a panel that had never been asked came back drawing something else")
    }

    /// And a stored answer survives the launch that restores the setting — the
    /// half that fails if the key is left on the purge list.
    func testAChosenTabLabelStyleSurvivesTheLaunch() {
        let store = migrated(["module.app.tabLabelStyle": TabLabelStyle.glyph.rawValue])
        XCTAssertEqual(TabLabelStyle(stored: store.string("tabLabelStyle", default: "")), .glyph)
    }

    // MARK: - Benches

    private func migratedRaw(_ planted: [String: Any]) -> [String: Any] {
        let store = InMemoryKeyValueStore()
        store.raw = planted
        AppSettings.migrateAndPurge(in: store)
        return store.raw
    }

    /// The app's own view of the store after a launch, so what is asserted is
    /// what a settings page and the panel would read.
    private func migrated(_ planted: [String: Any]) -> NamespacedStore {
        let store = InMemoryKeyValueStore()
        store.raw = planted
        AppSettings.migrateAndPurge(in: store)
        return AppSettings.store.over(store)
    }
}
