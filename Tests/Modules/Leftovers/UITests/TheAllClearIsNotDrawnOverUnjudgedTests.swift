import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **The green check over «No leftovers found» is the strongest claim this
/// module makes about somebody's Mac, and a scan that could not judge everything
/// was drawing it.**
///
/// The engine already chooses the safe direction — a `systemextensionsctl` or
/// `launchctl` read that did not answer leaves the row `.undetermined`, a file
/// that would not open leaves it `.unreadable` — and already says so in the log.
/// Nothing carried it to the screen: neither status is `.orphaned`, so the
/// default filter drops both, and what was left was an empty list under a tick.
///
/// Two sentences, not one, and they are in different places: the label goes
/// beside «Found: N» in a strip whose own comment says it holds controls and no
/// prose, and the sentence is the **message** of the empty state rather than a
/// note under the all-clear — a headline with a footnote invites the reader to
/// trust the headline.
@MainActor
final class TheAllClearIsNotDrawnOverUnjudgedTests: XCTestCase {

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private func item(_ name: String, status: ItemStatus) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096, status: status)
    }

    // MARK: - What the page decides

    /// The state as it arrives from a real scan: settings files in use, a couple
    /// of rows nobody could judge, and nothing left over. The list is empty, and
    /// «No leftovers found» is the claim the scan cannot back.
    func testAnEmptyListWithUnjudgedRowsDoesNotDrawTheAllClear() async {
        let wire = LeftoversWire(items: [item("com.vendor.settings", status: .inUse),
                                         item("com.vendor.extension", status: .undetermined),
                                         item("com.vendor.broken", status: .unreadable)])
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await lvm.scan()

        XCTAssertTrue(lvm.visibleItems.isEmpty, "precondition: the filtered list is empty")
        XCTAssertEqual(lvm.uncheckedCount, 2, """
            the two rows the scan never reached a verdict on are not counted, so nothing on the \
            page can say they were skipped.
            """)
        XCTAssertEqual(lvm.nothingToShow, .notEverythingChecked(2), """
            the page draws its all-clear — a green check over «No leftovers found» — while two \
            items sat unjudged: \(String(describing: lvm.nothingToShow)).
            """)
    }

    /// And the half that keeps it from being always true: a scan that judged
    /// every row and found nothing still says so.
    func testAScanThatJudgedEverythingStillDrawsTheAllClear() async {
        let wire = LeftoversWire(items: [item("com.vendor.settings", status: .inUse)])
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await lvm.scan()

        XCTAssertEqual(lvm.uncheckedCount, 0, "precondition: every row was judged")
        XCTAssertEqual(lvm.nothingToShow, .nothingFound)
    }

    // MARK: - What it says, and what it draws over it

    /// The message is the sentence about the unfinished scan, not the all-clear
    /// with something added to it.
    func testTheEmptyMessageIsTheSentenceAboutTheScan() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertEqual(LfStr.emptyMessage(.notEverythingChecked(3)), LfStr.couldNotCheck(3),
                           "\(language.rawValue): the message is not the sentence built for it")
            XCTAssertNotEqual(LfStr.emptyMessage(.notEverythingChecked(3)), LfStr.nothingFound, """
                \(language.rawValue): the screen still claims no leftovers were found, which is \
                the claim this scan could not reach.
                """)
        }
    }

    /// **The mark must not be the tick.** A green check over «Helm could not
    /// check 3 items» is the symbol contradicting the sentence beneath it, and
    /// the symbol is what a person reads first.
    func testTheMarkOverItIsAQuestionAndNotACheck() {
        XCTAssertNotEqual(LeftoversSettingsPage.symbol(for: .notEverythingChecked(3)),
                          LeftoversSettingsPage.symbol(for: .nothingFound),
                          "an unfinished scan wears the all-clear's own green check")
        XCTAssertEqual(LeftoversSettingsPage.symbol(for: .notEverythingChecked(3)),
                       "questionmark.circle")
    }

    /// The caption beside the filter carries the count, in every language, and it
    /// opens with the same word the badge on such a row wears — so the number,
    /// the pill and the delete question cannot come to mean different things.
    func testTheCaptionCarriesTheCountInTheBadgesOwnWord() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let line = LfStr.uncheckedLine(3)
            XCTAssertTrue(line.hasPrefix(LfStr.statusUndetermined), """
                \(language.rawValue): «\(line)» does not open with «\(LfStr.statusUndetermined)», \
                which is what the badge on one of these rows says.
                """)
            XCTAssertNotEqual(LfStr.uncheckedLine(1), line, """
                \(language.rawValue): the caption reads the same for one item and for three, so \
                it is not carrying the count: \(line)
                """)
        }
    }

    /// And the two are not one string wearing two jobs: the label belongs in a
    /// strip that holds no prose, the sentence stands alone on an empty screen.
    func testTheLabelAndTheSentenceAreNotTheSameLine() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertNotEqual(LfStr.uncheckedLine(3), LfStr.couldNotCheck(3),
                              "\(language.rawValue): one line is doing both jobs")
        }
    }

    /// It invites, so the Scan button is drawn — and it is drawn once, because
    /// the toolbar asks the same rule before drawing its own.
    func testTheScreenOffersTheScanAgain() {
        XCTAssertTrue(LeftoversEmpty.invites(.notEverythingChecked(3)),
                      "a screen reporting an unfinished scan with no way to run it again")
    }
}
