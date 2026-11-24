import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp
import HelmAppStrings

/// A release found while nobody is looking is announced, not only logged.
///
/// Without it the check's answer reaches only the settings window, which a
/// menu-bar app does not open by itself.
/// `UpdateNews` is the rule, held next door; what is held here is that the
/// service asks it, posts what it says, and does not say it twice.
@MainActor
final class AnUpdateNobodyIsLookingForSaysSoTests: XCTestCase {

    private var notices: FakeAutomationNotice!
    private var service: UpdateService!

    /// The store is a namespace of the app's own over an in-memory backing: the
    /// stamp this writes is a real setting, and `UserDefaults.standard` is the
    /// shared test domain.
    private var store: NamespacedStore!

    private func build(_ port: FakeAutomationNotice = FakeAutomationNotice(state: .authorized)) {
        notices = port
        store = AppSettings.store.over(InMemoryKeyValueStore())
        service = UpdateService(notices: port, store: store,
                                feed: { _ in throw URLError(.notConnectedToInternet) },
                                channelBacking: InMemoryKeyValueStore())
    }

    // The banner is posted from a task of its own — the check does not wait for macOS — so a read taken
    // straight afterwards would pass an absence for free; every `grace()` below is paired with a control that
    // proves the same path still speaks. **Posted is not finished:** the stamp that makes the next check quiet is
    // written after `NoticeChannel.tell` returns, so each wait below is on the record as well as on the banner,
    // or a second call fits through the window between them.

    func testAReleaseFoundWithNobodyWatchingIsAnnounced() async throws {
        build()

        service.tellSomebodyAboutIt("v0.12.0", startedByHand: false)
        await waitUntil("1 banner(s) and the announcement recorded") {
            notices.posted.count >= 1 && store.object(UpdateService.lastAnnouncedKey) as? String == "v0.12.0"
        }

        let said = try XCTUnwrap(notices.posted.first)
        // The card's own words, not a second spelling of them.
        XCTAssertEqual(said.title, AppStr.updateReady)
        XCTAssertTrue(said.body.contains("v0.12.0"),
                      "the banner said an update was ready and not which one: \(said.body)")
    }

    /// The launch check runs every day against a release that may sit there for
    /// a fortnight. The same offer every morning is how a person learns to
    /// switch a channel off.
    func testTheSameReleaseIsAnnouncedOnce() async {
        build()

        service.tellSomebodyAboutIt("v0.12.0", startedByHand: false)
        await waitUntil("1 banner(s) and the announcement recorded") {
            notices.posted.count >= 1 && store.object(UpdateService.lastAnnouncedKey) as? String == "v0.12.0"
        }
        service.tellSomebodyAboutIt("v0.12.0", startedByHand: false)
        await grace()

        XCTAssertEqual(notices.posted.count, 1)

        // The control: silence above is a decision about that version, not a
        // channel that has stopped working.
        service.tellSomebodyAboutIt("v0.12.1", startedByHand: false)
        await waitUntil("2 banner(s) and the announcement recorded") {
            notices.posted.count >= 2 && store.object(UpdateService.lastAnnouncedKey) as? String == "v0.12.1"
        }
        XCTAssertEqual(notices.posted.count, 2)
    }

    /// A check somebody pressed is answered on the card they pressed it on, with
    /// the button that installs it. macOS is not even asked: a permission prompt
    /// raised by a button that already answered is the worst moment to spend the
    /// one prompt macOS allows.
    func testACheckSomebodyPressedSaysNothing() async {
        build()

        service.tellSomebodyAboutIt("v0.12.0", startedByHand: true)
        await grace()

        XCTAssertEqual(notices.posted, [])
        XCTAssertEqual(notices.reads, 0, "macOS was asked about banners for a check somebody was watching")

        // The control, and the second thing this holds: pressing the button did
        // not spend the announcement either.
        service.tellSomebodyAboutIt("v0.12.0", startedByHand: false)
        await waitUntil("1 banner(s) and the announcement recorded") {
            notices.posted.count >= 1 && store.object(UpdateService.lastAnnouncedKey) as? String == "v0.12.0"
        }
        XCTAssertEqual(notices.posted.count, 1)
    }

    /// **A refusal is not an announcement.** Recording one as if it were means
    /// the person who grants Helm notifications tomorrow is never told about the
    /// release that was waiting for them today.
    func testARefusalDoesNotSpendTheAnnouncement() async {
        build(FakeAutomationNotice(state: .denied))

        service.tellSomebodyAboutIt("v0.12.0", startedByHand: false)
        await grace()
        XCTAssertEqual(notices.posted, [])

        // System Settings, the only way this ever changes.
        notices.state = .authorized
        service.tellSomebodyAboutIt("v0.12.0", startedByHand: false)
        await waitUntil("1 banner(s) and the announcement recorded") {
            notices.posted.count >= 1 && store.object(UpdateService.lastAnnouncedKey) as? String == "v0.12.0"
        }

        XCTAssertEqual(notices.posted.count, 1)
    }

    /// **The check runs after launch too.** Helm is launched at login and runs
    /// for weeks, so a check once per launch happens once, and a banner behind
    /// it would be dead for the people who never quit.
    func testTheCheckGoesOnHappeningAfterLaunch() {
        let store = AppSettings.store.over(InMemoryKeyValueStore())
        // Stamped as checked a moment ago, so arming the tick asks GitHub
        // nothing: a unit test that reaches the network is a test of the
        // network. The daily guard itself is `UpdateCheck.lastChecked`, held
        // next door.
        store.set(Int(Date().timeIntervalSince1970), for: UpdateService.lastCheckKey)
        // The feed fails the test if it is asked: the stamp above is why it is not.
        let service = UpdateService(notices: FakeAutomationNotice(), store: store,
                                    feed: { _ in XCTFail("the hourly tick asked GitHub inside the day"); throw URLError(.badURL) },
                                    channelBacking: InMemoryKeyValueStore())

        service.startChecking()
        XCTAssertTrue(service.isWatchingForUpdates, "the check happened once and never again")
        XCTAssertEqual(UpdateService.recheckEvery, 3600, "the tick is hourly; the check is daily")

        // A test leaves nothing behind, and the run loop holds a `Timer` whether
        // or not anybody still wants it.
        service.stopChecking()
        XCTAssertFalse(service.isWatchingForUpdates)
    }
}
