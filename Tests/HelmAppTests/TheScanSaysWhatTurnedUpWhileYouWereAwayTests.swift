import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import HelmApp

/// The other half of the journal.
///
/// Three modules walk the volume twice a day, `ScanJournal.change(module:)`
/// computes what turned up since last time — and nothing in `Sources/` ever
/// called it. The entire user-visible product of all that reading was a relative
/// date on a settings page. This is the call that was missing, and the silences
/// around it: the rule itself is `ScanNews`', held next door, and what is held
/// here is that the coordinator asks it and posts what it says.
@MainActor
final class TheScanSaysWhatTurnedUpWhileYouWereAwayTests: XCTestCase {

    private var journal: ScanJournal!
    private var notices: FakeAutomationNotice!
    private var coordinator: ScanCoordinator!

    private func build(_ port: FakeAutomationNotice = FakeAutomationNotice(state: .authorized)) {
        notices = port
        // A journal of this test's own: the owner's real one lives in
        // Application Support and names every path their Mac has been scanned
        // for.
        journal = ScanJournal(directory: scratchDirectory("scan-journal"))
        coordinator = ScanCoordinator(host: ModuleHost.shared, journal: journal, notices: port)
    }

    private func record(_ items: [ScanItem], for module: String = "duplicates") {
        journal.record(ScanEntry(at: Date(), bytes: items.reduce(0) { $0 + $1.bytes },
                                 count: items.count, seconds: 1),
                       items: items, module: module)
    }

    private func item(_ path: String, _ bytes: Int) -> ScanItem {
        ScanItem(path: path, bytes: bytes)
    }

    /// The banner is posted from a task of its own — the coordinator does not
    /// wait for macOS — so a read taken straight afterwards would pass an
    /// absence for free. `waitUntil` and `grace` are the harness's; the second
    /// is always paired with a control that proves the same path still speaks.
    private func waitForPosts(_ wanted: Int) async {
        await waitUntil("\(wanted) banner(s)") { self.notices.posted.count >= wanted }
    }

    /// A module that has scanned once has nothing to compare against, and the
    /// journal refuses to invent a previous list. Without this the first
    /// unattended scan of a full disk arrives as news about the whole disk.
    func testTheFirstScanAModuleEverRanIsSilent() async {
        build()
        record([item("/a", 90_000_000_000)])

        coordinator.tellSomebodyWhatAppeared(in: "duplicates")
        await grace()

        XCTAssertEqual(notices.posted, [])
        XCTAssertEqual(notices.reads, 0, "macOS was asked about banners for a scan with no delta")
    }

    /// The ordinary day: the same things are still there.
    func testAScanThatFoundTheSameThingsAgainIsSilent() async {
        build()
        let same = [item("/a", 90_000_000_000)]
        record(same)
        record(same)

        coordinator.tellSomebodyWhatAppeared(in: "duplicates")
        await grace()

        XCTAssertEqual(notices.posted, [])
    }

    /// And the day something did turn up. The title names the module, because a
    /// notification with no title is drawn as «Helm» and a body, which does not
    /// say which of ten modules is speaking.
    func testSomethingLargeThatTurnedUpIsAnnouncedWithTheModulesName() async throws {
        build()
        record([item("/a", 90_000_000_000)])
        record([item("/a", 90_000_000_000), item("/new", 4_000_000_000)])

        coordinator.tellSomebodyWhatAppeared(in: "duplicates")
        await waitForPosts(1)

        XCTAssertEqual(notices.posted.count, 1)
        let said = try XCTUnwrap(notices.posted.first)
        XCTAssertEqual(said.title, ModuleRegistry.descriptor("duplicates")?.moduleMetadata.name)
        XCTAssertFalse(said.body.isEmpty, "the banner named the module and said nothing")
    }

    /// **The floor, and the control beside it.** A few megabytes between two
    /// scans is the disk working; the same coordinator with something worth
    /// saying still speaks, so the silence is a decision rather than a channel
    /// that has stopped working.
    func testALittleThatTurnedUpIsSilentAndSomethingLargeStillSpeaks() async {
        build()
        record([item("/a", 90_000_000_000)])
        record([item("/a", 90_000_000_000), item("/small", 4_000_000)])

        coordinator.tellSomebodyWhatAppeared(in: "duplicates")
        await grace()
        XCTAssertEqual(notices.posted, [], "a banner arrived about four megabytes")

        record([item("/a", 90_000_000_000), item("/small", 4_000_000),
                item("/big", 8_000_000_000)])
        coordinator.tellSomebodyWhatAppeared(in: "duplicates")
        await waitForPosts(1)
        XCTAssertEqual(notices.posted.count, 1,
                       "the control: with something large the same path still speaks")
    }

    /// Each module is asked about its own journal — the coordinator scans three
    /// of them and a banner naming the wrong one is worse than none.
    func testAModuleIsAskedAboutItsOwnFindings() async {
        build()
        record([item("/a", 90_000_000_000)], for: "disk")
        record([item("/a", 90_000_000_000), item("/new", 9_000_000_000)], for: "disk")

        coordinator.tellSomebodyWhatAppeared(in: "duplicates")
        await grace()
        XCTAssertEqual(notices.posted, [],
                       "one module's finding was announced under another's name")

        coordinator.tellSomebodyWhatAppeared(in: "disk")
        await waitForPosts(1)
        XCTAssertEqual(notices.posted.first?.title,
                       ModuleRegistry.descriptor("disk")?.moduleMetadata.name)
    }

    // MARK: - What it says

    /// Every language Helm ships, including the seven this machine is not set
    /// to: a test that read `AppLanguage.current` would check one of eight and
    /// report on all of them.
    func testTheBannerIsWrittenInEveryLanguage() {
        let finding = ScanNews.Finding(count: 7, bytes: 34_200_000_000)
        var seen: Set<String> = []
        for language in AppLanguage.allCases {
            let body = AppStr.scanFindingBody(finding, language: language)
            XCTAssertTrue(body.contains("7"), "\(language.rawValue) lost the count: \(body)")
            seen.insert(body)
        }
        XCTAssertEqual(seen.count, AppLanguage.allCases.count,
                       "two languages read identically, so one is untranslated: \(seen)")
    }

    /// **A finding, never a claim of action.** The words a banner must not carry
    /// are the ones that say Helm did something to the person's files while they
    /// were away — it looked, and that is all.
    func testTheBannerClaimsNoAction() {
        let finding = ScanNews.Finding(count: 7, bytes: 34_200_000_000)
        for language in AppLanguage.allCases {
            let body = AppStr.scanFindingBody(finding, language: language).lowercased()
            for claim in ["clean", "freed", "removed", "deleted", "trash",
                          "очищ", "удал", "освобо", "корзин"] {
                XCTAssertFalse(body.contains(claim),
                               "\(language.rawValue) claims an act Helm did not perform: \(body)")
            }
        }
    }

    /// The counted noun takes the form its language gives it. A number
    /// interpolated in front of a fixed word reads as a bug in the one place
    /// that must not look buggy.
    func testTheCountedNounFollowsItsLanguagesRules() {
        func body(_ count: Int, _ language: AppLanguage) -> String {
            AppStr.scanFindingBody(ScanNews.Finding(count: count, bytes: 2_000_000_000),
                                   language: language)
        }
        XCTAssertTrue(body(1, .ru).contains("1 объект"))
        XCTAssertTrue(body(3, .ru).contains("3 объекта"))
        XCTAssertTrue(body(5, .ru).contains("5 объектов"))
        XCTAssertTrue(body(1, .en).contains("1 item"))
        XCTAssertFalse(body(1, .en).contains("1 items"))
    }

    /// The size is written the way the language writes it, not the way this
    /// Mac's system locale does — a `Foundation` formatter built with no locale
    /// answers in the system's language, which is the trap `HelmBytes` exists
    /// for.
    func testTheSizeIsInTheBannersOwnLanguage() {
        let finding = ScanNews.Finding(count: 1, bytes: 34_200_000_000)
        XCTAssertTrue(AppStr.scanFindingBody(finding, language: .ru).contains("ГБ"))
        XCTAssertTrue(AppStr.scanFindingBody(finding, language: .en).contains("GB"))
    }

    /// French puts a narrow no-break space before its two-part punctuation.
    func testTheFrenchBannerCarriesNoBareSpaceBeforeTightPunctuation() {
        let body = AppStr.scanFindingBody(ScanNews.Finding(count: 3, bytes: 2_000_000_000),
                                          language: .fr)
        for mark in [":", ";", "?", "!", "»"] {
            XCTAssertFalse(body.contains(" " + mark), "a bare space before \(mark) in: \(body)")
        }
    }

    /// macOS refusing is a silence with a reason, and nothing is posted.
    func testARefusedPermissionPostsNothing() async {
        build(FakeAutomationNotice(state: .denied))
        record([item("/a", 90_000_000_000)])
        record([item("/a", 90_000_000_000), item("/new", 9_000_000_000)])

        coordinator.tellSomebodyWhatAppeared(in: "duplicates")
        await grace()

        XCTAssertEqual(notices.posted, [])
        XCTAssertEqual(notices.requests, 0,
                       "a standing refusal was asked about again")
    }
}
