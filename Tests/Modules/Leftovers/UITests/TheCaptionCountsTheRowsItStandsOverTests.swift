import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// «Found: N» stands beside the control that decides what is shown, over the list
/// that control produced — so the number is about that list.
///
/// It was `leftoverCount`, which is `visibleItems.filter(\.removable).count`: *how
/// many you may tick*. Measured on this Mac: 542 items with 3 leftovers, filter
/// «All» → «Found: 3 items» over 542 rows; filter «Leftovers» with four leftovers
/// of which one is removable → «Found: 1 item» over four rows every one of which is
/// badged «Leftover». The two quantities are both wanted and they are not the same
/// question: `leftoverCount` goes on gating «Select all», which really is about
/// what may be ticked.
@MainActor
final class TheCaptionCountsTheRowsItStandsOverTests: XCTestCase {

    /// A row the list draws and nobody may tick: a daemon in the system domain is
    /// a leftover whose unloading needs root, so `available` withholds `.delete`
    /// and the checkbox is a blank slot.
    private func daemon(_ name: String) -> StaleItem {
        StaleItem(path: "/Library/LaunchDaemons/\(name).plist", identifier: name,
                  kind: .launchDaemon, sizeBytes: 4_096)
    }

    private func agent(_ name: String, status: ItemStatus = .orphaned) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096, status: status)
    }

    private func model(_ items: [StaleItem]) async -> LeftoversViewModel {
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: LeftoversWire(items: items)))
        await lvm.scan()
        return lvm
    }

    /// Four leftovers, one of them removable: the caption is about the four.
    ///
    /// Every language, because the caption is a sentence and this suite runs in
    /// whichever one this Mac is set to.
    func testTheCaptionCountsEveryRowRatherThanTheTickableOnes() async {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        let lvm = await model([agent("com.vendor.gone"), daemon("com.vendor.d1"),
                               daemon("com.vendor.d2"), daemon("com.vendor.d3")])
        XCTAssertEqual(lvm.visibleItems.count, 4, "precondition: the list draws four rows")
        XCTAssertEqual(lvm.leftoverCount, 1, "precondition: one of them may be ticked")

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertEqual(LeftoversSettingsPage.foundCaption(lvm), LfStr.foundLine(4),
                           "«Found» counts what may be ticked, over a list of four rows, "
                           + "in \(language.rawValue)")
        }
    }

    /// And with the filter on «All» it is about everything the list shows —
    /// the reading that put «Found: 3 items» over 542 rows.
    func testWithTheFilterOnAllTheCaptionIsAboutEverythingShown() async {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = .en

        let lvm = await model([agent("com.vendor.gone"), agent("com.vendor.busy", status: .inUse),
                               agent("com.apple.system", status: .protectedItem)])
        lvm.showAll = true
        XCTAssertEqual(lvm.visibleItems.count, 3, "precondition: the list draws all three")
        XCTAssertEqual(lvm.leftoverCount, 1, "precondition: only one of them may be ticked")

        XCTAssertEqual(LeftoversSettingsPage.foundCaption(lvm), LfStr.foundLine(3))
    }

    /// The other half, and the reason the two quantities both stay: «Select all»
    /// is gated on what may be ticked, which is not what the caption says.
    func testWhatMayBeTickedIsStillItsOwnQuestion() async {
        let lvm = await model([agent("com.vendor.gone"), daemon("com.vendor.d1")])

        XCTAssertEqual(lvm.selectablePaths.count, 1)
        XCTAssertEqual(lvm.leftoverCount, 1,
                       "the count that gates «Select all» followed the caption")
    }
}
