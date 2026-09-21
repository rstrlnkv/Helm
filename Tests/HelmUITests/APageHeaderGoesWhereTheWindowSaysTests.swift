import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **A page's header is drawn in exactly one place, and the window decides
/// which.**
///
/// `helmPageHeader` used to draw a row at the top of the page, always. The
/// settings window now has a toolbar and puts the header there, in one of two
/// drafted shapes (`PageBarStyle`); a sheet, and a page mounted on its own, have
/// no toolbar and must go on drawing the row. The environment is the one
/// question: nil means «draw it yourself».
///
/// Three things this can get wrong, each a separate case: the row drawn under a
/// bar that already says the same thing (two headers), no row where there is no
/// bar (no header at all), and the window told the wrong name or a status the
/// chosen shape does not draw under the title.
///
/// The toolbar item the module-name shape adds is not in this render — a page
/// drawn in an `NSHostingView` has no window toolbar to bridge into — so the
/// shape's own item is not asserted here; what is asserted is that the page
/// drew no row of its own and told the window its name without a subtitle.
@MainActor
final class APageHeaderGoesWhereTheWindowSaysTests: XCTestCase {

    /// What the page last told its window, caught the way the settings window
    /// catches it.
    @MainActor private final class Told {
        var title: HelmPageTitle?
    }

    /// The header's own strip: `HelmSpace.s5` of padding around a 28 pt plate.
    private static let headerBand = 0...51

    private func mount(_ bar: PageBarStyle?, told: Told) -> MountedRender {
        let page = ScrollView { Color.clear.frame(height: 400) }
            .helmPageHeader(symbol: "gearshape", tint: .gray,
                            title: "Header Probe", subtitle: "Idle")
            .environment(\.helmPageBar, bar)
            .onPreferenceChange(HelmPageTitleKey.self) { title in
                MainActor.assumeIsolated { told.title = title }
            }
        let mount = MountedRender(page, width: 600, height: 300, appearance: .aqua)
        mount.settle(20)
        return mount
    }

    func testWithNoWindowBarThePageDrawsItsOwnRow() throws {
        let told = Told()
        let mount = mount(nil, told: told)
        defer { mount.drop() }

        XCTAssertGreaterThan(try XCTUnwrap(mount.ink(Self.headerBand)), 0, """
            a page with no window toolbar drew no header row — a sheet, or a page in a window \
            without the bar, would open with nothing saying what it is
            """)
        XCTAssertNil(told.title, "the page named itself to a window that is not listening for it")
    }

    func testInTheWindowTitleShapeThePageDrawsNoRowAndNamesItselfWithItsStatus() throws {
        let told = Told()
        let mount = mount(.windowTitle, told: told)
        defer { mount.drop() }

        // The subject first: a page that published nothing would also draw no row.
        XCTAssertEqual(told.title, HelmPageTitle(title: "Header Probe", subtitle: "Idle"), """
            the window was told \(String(describing: told.title)) — its title bar would carry the \
            wrong name, or no status under it
            """)
        XCTAssertEqual(try XCTUnwrap(mount.ink(Self.headerBand)), 0, """
            the page drew its own header row under a window title that already says the same — \
            two headers stacked
            """)
    }

    func testInTheModuleNameShapeTheWindowIsNamedWithoutASubtitle() throws {
        let told = Told()
        let mount = mount(.moduleName, told: told)
        defer { mount.drop() }

        XCTAssertEqual(told.title, HelmPageTitle(title: "Header Probe", subtitle: nil), """
            the window was told \(String(describing: told.title)) — in this shape the status is \
            drawn after the name in the bar, and a subtitle would say it a second time
            """)
        XCTAssertEqual(try XCTUnwrap(mount.ink(Self.headerBand)), 0,
                       "the page drew its own header row as well as the bar's plate and name")
    }

    func testAnythingUnknownStoredIsTheModuleNameShape() {
        XCTAssertEqual(PageBarStyle(stored: ""), .moduleName)
        XCTAssertEqual(PageBarStyle(stored: "no such shape"), .moduleName)
        XCTAssertEqual(PageBarStyle(stored: "windowTitle"), .windowTitle)
    }
}
