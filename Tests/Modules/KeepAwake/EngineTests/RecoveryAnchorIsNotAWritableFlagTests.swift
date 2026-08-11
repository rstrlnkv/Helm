import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The launch-time recovery hung on a value any process running as this user can
/// erase.
///
/// `recoverAtLaunch()` opened on `store.bool(clamshellGuard)`, and that flag
/// lives in `~/Library/Preferences/…helm.plist`, writable by anything running as
/// the person. Clear it — a tidy-up script, a defaults write, a restored backup,
/// a hand edit — and Helm never looks again: system sleep stays off machine-wide,
/// every screen says Keep Awake is idle, and the Mac does not sleep until
/// somebody works out what `pmset -g` is saying. It is the one setting in this
/// module that steers privileged work with nobody watching, and CLAUDE.md's seal
/// cannot be used on it (`clamshellEnabled`'s own doc comment has the reason: an
/// ad-hoc signed bundle meets a keychain dialog at every install).
///
/// So the recovery gains a second anchor that is **not** user-writable:
/// `/etc/sudoers.d/helm-keepawake` is installed 0440 root:wheel, and clearing it
/// needs root. Measured from this account: the existence check answers from uid
/// 501 without any grant, while removing the file asks for a password. Either
/// anchor is enough to go and read `pmset -g`; the report is still what decides
/// whether anything is put back.
final class RecoveryAnchorIsNotAWritableFlagTests: XCTestCase {
    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var clamshell: FakeClamshell!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        clamshell = FakeClamshell()
    }

    private var guardFlag: Bool {
        store.bool(KeepAwakeSettings.Key.clamshellGuard, default: false)
    }

    private func launch() {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(), power: FakePower(),
                        apps: FakeApps(), pointer: FakePointer(),
                        clamshell: clamshell, clock: FakeClock()).activate()
    }

    /// Sleep is off machine-wide, Helm's own rule is on disk, and the note in the
    /// plist is gone. This is the state the whole file is about.
    func testARuleOnDiskIsEnoughToGoAndLook() {
        store.set(false, for: KeepAwakeSettings.Key.clamshellGuard)
        clamshell.sudoersInstalled = true
        clamshell.pmset = "SleepDisabled 1"

        launch()

        XCTAssertEqual(clamshell.disableSleepCalls, [false],
                       "the note was cleared behind Helm's back, so nothing ever looked again — "
                       + "and the rule that says this app installed a way to turn sleep off was "
                       + "sitting in /etc/sudoers.d the whole time")
        XCTAssertFalse(guardFlag, "…and the note is written off once sleep is really back")
    }

    /// The other anchor still works on its own: Helm crashed with sleep off and
    /// the rule has since been taken out by an admin or a migration.
    func testTheNoteAloneIsStillEnoughToGoAndLook() {
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        clamshell.sudoersInstalled = false
        clamshell.pmset = "SleepDisabled 1"

        launch()

        XCTAssertEqual(clamshell.disableSleepCalls, [false])
    }

    // MARK: - The controls, which are what keep this from being a launch that
    // always shells out

    /// A Mac where Helm has never touched sleep: no note, no rule. Nothing is
    /// asked of `pmset` at all — the reason the flag short-circuited the read in
    /// the first place, and `||` keeps it, because the second half of the guard
    /// is only reached when one of the two anchors holds.
    func testAnOrdinaryLaunchReadsNothingAndRestoresNothing() {
        launch()

        XCTAssertEqual(clamshell.pmsetReads, 0,
                       "every launch on every Mac now runs `pmset -g` to find out that this app "
                       + "has never been near the setting")
        XCTAssertTrue(clamshell.disableSleepCalls.isEmpty)
    }

    /// And the report is still what decides. An anchor says «look», not «put it
    /// back»: sleep is on, so there is nothing to restore, and a launch that
    /// called `pmset disablesleep 0` here would be spending the grant for
    /// nothing.
    func testAnAnchorWithSleepAlreadyOnRestoresNothing() {
        clamshell.sudoersInstalled = true
        clamshell.pmset = "SleepDisabled 0"

        launch()

        XCTAssertEqual(clamshell.pmsetReads, 1, "precondition: the report was read")
        XCTAssertTrue(clamshell.disableSleepCalls.isEmpty,
                      "the rule is on disk because the lid option is switched on, which is the "
                      + "ordinary state — sleep is not off and nothing needs restoring")
    }
}
