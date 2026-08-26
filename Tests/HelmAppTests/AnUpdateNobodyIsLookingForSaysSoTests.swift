import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import HelmApp

/// The other half of the update check.
///
/// `UpdateCheck` decides what a GitHub response means and eight suites hold it —
/// and the answer went into a published property that exactly one view reads, on
/// the About page, inside a settings window a menu-bar app does not open by
/// itself. The daily check could find a release and the only trace of it was a
/// line in the log. `UpdateNews` is the rule, held next door; what is held here
/// is that the service asks it, posts what it says, and does not say it twice.
@MainActor
final class AnUpdateNobodyIsLookingForSaysSoTests: XCTestCase {

    private var notices: FakeAutomationNotice!
    private var service: UpdateService!

    /// The store is a namespace of the app's own over an in-memory backing: the
    /// stamp this writes is a real setting, and `UserDefaults.standard` is the
    /// shared test domain that had 3028 keys in it.
    private func build(_ port: FakeAutomationNotice = FakeAutomationNotice(state: .authorized)) {
        notices = port
        service = UpdateService(notices: port,
                                store: AppSettings.store.over(InMemoryKeyValueStore()))
    }

    /// The banner is posted from a task of its own — the check does not wait for
    /// macOS — so a read taken straight afterwards would pass an absence for
    /// free. Every `grace()` below is paired with a control that proves the same
    /// path still speaks.
    private func waitForPosts(_ wanted: Int) async {
        await waitUntil("\(wanted) banner(s)") { self.notices.posted.count >= wanted }
    }

    func testAReleaseFoundWithNobodyWatchingIsAnnounced() async throws {
        build()

        service.tellSomebodyAboutIt("v0.12.0", startedByHand: false)
        await waitForPosts(1)

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
        await waitForPosts(1)
        service.tellSomebodyAboutIt("v0.12.0", startedByHand: false)
        await grace()

        XCTAssertEqual(notices.posted.count, 1)

        // The control: silence above is a decision about that version, not a
        // channel that has stopped working.
        service.tellSomebodyAboutIt("v0.12.1", startedByHand: false)
        await waitForPosts(2)
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
        await waitForPosts(1)
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
        await waitForPosts(1)

        XCTAssertEqual(notices.posted.count, 1)
    }

    /// **Launch was the only moment there was.** Helm is launched at login and
    /// then runs for weeks, so a check that happens once per launch happens
    /// once — and a banner behind it would be dead for exactly the people who
    /// never quit.
    func testTheCheckGoesOnHappeningAfterLaunch() {
        let store = AppSettings.store.over(InMemoryKeyValueStore())
        // Stamped as checked a moment ago, so arming the tick asks GitHub
        // nothing: a unit test that reaches the network is a test of the
        // network. The daily guard itself is `UpdateCheck.lastChecked`, held
        // next door.
        store.set(Int(Date().timeIntervalSince1970), for: UpdateService.lastCheckKey)
        let service = UpdateService(notices: FakeAutomationNotice(), store: store)

        service.startChecking()
        XCTAssertTrue(service.isWatchingForUpdates, "the check happened once and never again")
        XCTAssertEqual(UpdateService.recheckEvery, 3600, "the tick is hourly; the check is daily")

        // A test leaves nothing behind, and the run loop holds a `Timer` whether
        // or not anybody still wants it.
        service.stopChecking()
        XCTAssertFalse(service.isWatchingForUpdates)
    }

    /// The words, in every language rather than in whichever one this Mac is set
    /// to — `AppleLanguages` here is `("ru-RU","en-US")`, so a bare assertion
    /// reads Russian and an English mutation passes.
    func testTheBannerNamesTheVersionAndTheWayToItInEveryLanguage() {
        let english = AppStr.updateFoundBody(version: "v0.12.0", language: .en)
        for language in AppLanguage.allCases {
            let body = AppStr.updateFoundBody(version: "v0.12.0", language: language)
            XCTAssertTrue(body.contains("v0.12.0"),
                          "\(language) named no version: \(body)")
            XCTAssertTrue(body.contains("→"),
                          "\(language) said where to go without saying where: \(body)")
            if language != .en {
                XCTAssertNotEqual(body, english,
                                  "\(language) is the English sentence — the path is untranslated")
            }
        }
    }
}
