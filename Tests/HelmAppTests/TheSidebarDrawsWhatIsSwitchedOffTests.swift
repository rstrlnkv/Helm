import HelmTestSupport
import XCTest
@testable import HelmApp

/// The other half of finding 7, which is a fact about the window rather than
/// about the arithmetic.
///
/// `SidebarLayout.off(enabled:)` answers which modules are switched off, and
/// `TheSidebarKeepsADoorToAnOffModuleTests` holds that answer. Nothing in
/// it would notice the sidebar going back to dropping them — which is exactly
/// what it did before, and it left `ModuleDetailView`'s empty state unreachable
/// from all four routes to `.module(id)`. The door is one `Section` in one file,
/// so this reads that file.
@MainActor
final class TheSidebarDrawsWhatIsSwitchedOffTests: XCTestCase {

    private let file = "Sources/HelmApp/SettingsWindow.swift"

    func testTheSidebarAsksForTheModulesThatAreOff() throws {
        let code = try RepoSource.lines(of: file).map(RepoSource.code)
        XCTAssertTrue(code.contains { $0.contains("layout.off(") },
                      "the sidebar no longer asks which modules are switched off, so a module "
                      + "somebody turns off has no page again — and the empty state written for "
                      + "that case is unreachable from every route to .module(id)")
    }

    /// And that those rows are a *selection*: a dimmed row that cannot be
    /// chosen is the composer's tooltip again, one window over.
    func testThoseRowsOpenTheModulesOwnPage() throws {
        let text = try RepoSource.text(of: file)
        let section = try XCTUnwrap(text.range(of: "Section(AppStr.switchedOffSection)"),
                                    "the section that draws them is gone")
        let body = text[section.lowerBound...].prefix(700)
        XCTAssertTrue(body.contains(".tag(SettingsSelection.module(descriptor.idRaw))"),
                      "the off rows are drawn and not tagged, so selecting one goes nowhere")
    }
}
