import XCTest
import HelmTestSupport

/// **A page-bar style chosen for the toolbar has to give the page a new
/// identity, not just a new environment value.**
///
/// Not the SwiftUI-AppKit bridge any more — that reason left with the bridge
/// itself. What is measured today: `GeneralSettingsPage`'s own picker
/// (`pageBarStyle`) reads `AppSettings.pageBarStyle` once into a `@State` var
/// at its own init, so a style chosen through the bar's own right-click menu
/// (`SettingsToolbar.barMenuChosePageBar`) leaves that picker showing the old
/// choice until the page's subtree is torn down and rebuilt — an environment
/// change alone reaches `PageBarContent`'s own `@Environment` read, which
/// redraws on its own, but never reaches a `@State` initial value. Removing
/// the `.id` here (engineer, 2026-09-28, reverted) failed
/// `TheGeneralPickerFollowsTheBarMenuTests
/// .testThePickerOnScreenFollowsAChoiceMadeInTheBarsMenu`, besides this
/// file's own `testThePageBarStyleTrackerKeysItsSubtreeOnTheStyle`, which
/// checks the source directly and fails on any source without the line.
///
/// This file cannot mount `GeneralSettingsPage` under the real bar's own
/// right-click menu, so it cannot see the picker go stale directly — what a
/// test here can hold is only that the tracker keeps the `id` at all.
/// `TheGeneralPickerFollowsTheBarMenuTests
/// .testThePickerOnScreenFollowsAChoiceMadeInTheBarsMenu` does mount that
/// combination, ordered in behind the other windows, through
/// `SettingsSplitViewController`, sends the
/// bar's own menu action and reads the picker back through Vision — that is
/// where the staleness above was actually measured. The switcher style had a
/// tracker of its own under the pane, held here to the opposite; it went on
/// 2026-09-28, when nothing under the pane read the value any more — every
/// switcher is built in the toolbar's own hosting views and handed its style
/// there.
final class AStyleChosenInTheBarReachesTheBarTests: XCTestCase {

    private func trackerBody(_ name: String, in file: String) throws -> String {
        let code = SwiftSource.code(try RepoSource.text(of: file))
        let start = try XCTUnwrap(code.range(of: "struct \(name)"), "\(file) no longer declares \(name)")
        let end = code.range(of: "\nstruct ", range: start.upperBound..<code.endIndex)?.lowerBound
            ?? code.endIndex
        return String(code[start.lowerBound..<end])
    }

    func testThePageBarStyleTrackerKeysItsSubtreeOnTheStyle() throws {
        let body = try trackerBody("HelmPageBarStyleTracker",
                                   in: "Sources/HelmUI/DesignSystem/PageBarStyle.swift")
        XCTAssertTrue(body.contains(".id(style ?? current())"), """
            the page-bar tracker hands the subtree a value and not an identity, so a page's own \
            `@State` captured from `AppSettings.pageBarStyle` at init — General's own picker among \
            them — keeps showing the old choice until the page is reopened
            """)
    }
}
