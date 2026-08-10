import XCTest
import HelmTestSupport
@testable import Module_KeepAwake_UI

/// The panel and the settings page each have one slot under their buttons, and
/// two things can want it: a rule that has been paused, and the battery guard
/// having stopped everything.
///
/// Both can be true at once, and of the two only the guard explains why nothing
/// at all is running — «Resume» while it is in force is a control that cannot do
/// what it says. So the guard wins on both surfaces, and it carries no button:
/// the notice goes by itself when the charger goes in.
///
/// A source check on purpose. Both spellings compile, both draw the same card
/// in every state a runtime test could construct without a live engine, and
/// what this pins is the *precedence* — which is a decision, and decisions are
/// what rot when somebody edits one of two files.
final class BothNoticesShareOneSlotTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let url = RepoSource.root
            .appendingPathComponent("Sources/Modules/KeepAwake/UI/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The panel says it at all. It was the settings page only — the surface
    /// somebody opens deliberately — while the panel, which is the one they
    /// actually use, kept the silence the whole change was about.
    func testThePanelDrawsTheBatteryNotice() throws {
        let tile = try source("KeepAwakePanelTile.swift")
        XCTAssertGreaterThan(tile.count, 1000, "the file was not read at all")
        XCTAssertTrue(tile.contains("KAStr.stoppedByBattery"),
                      "the panel does not say the battery guard stopped anything, so pressing "
                      + "«15 min» at 5 % is silence again")
    }

    /// The guard wins over the paused rule, on both surfaces and in the same
    /// direction.
    func testTheBatteryWinsOnBothSurfaces() throws {
        for name in ["KeepAwakePanelTile.swift", "KeepAwakeHero.swift"] {
            let text = try source(name)
            guard let battery = text.range(of: "if vm.batteryStopped")
                    ?? text.range(of: "if batteryStopped") else {
                XCTFail("\(name) has no battery branch at all"); continue
            }
            let paused = try XCTUnwrap(text.range(of: "KAStr.automationPaused"),
                                       "\(name) has no paused branch")
            XCTAssertLessThan(battery.lowerBound, paused.lowerBound,
                              "\(name) draws the paused-rule notice ahead of the battery one, "
                              + "so the surface says a rule is paused while the real reason "
                              + "nothing runs is the charge")
        }
    }

    /// And the battery notice carries no verb. `HelmBanner`'s action slot is
    /// what a caller passes a button in; this one uses the initialiser that has
    /// none, so there is nothing to press that cannot work.
    func testTheBatteryNoticeHasNoButton() throws {
        for name in ["KeepAwakePanelTile.swift", "KeepAwakeHero.swift"] {
            let text = try source(name)
            let line = try XCTUnwrap(text.components(separatedBy: "\n")
                .first { $0.contains("KAStr.stoppedByBattery") },
                                     "\(name) does not draw the battery notice")
            XCTAssertFalse(line.hasSuffix("{"),
                           "\(name) opens an action block on the battery banner — a «Resume» "
                           + "there cannot do what it says while the guard is in force: \(line)")
        }
    }
}
