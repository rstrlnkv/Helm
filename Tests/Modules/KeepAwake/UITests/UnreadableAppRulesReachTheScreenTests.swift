import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// A rules string in the file that nothing can read stops every app rule, and the
/// page went on looking perfectly well.
///
/// `AppTriggerRules.readable` answers `nil` for it and `appTriggers` turns that
/// into «no rules», which fails in the safe direction — the Mac sleeps — and is
/// indistinguishable from having chosen no apps. The engine's `activate()` wrote
/// one line in the log and that was the entire account: somebody's apps stopped
/// holding the Mac awake, and the only screen about app rules drew its empty
/// state as if they had never existed.
///
/// Measured on the render, in the warning signal the banner is drawn in, because
/// what is being pinned is that a person can see it. The store is where the state
/// comes from — this is the one thing on the page that is a fact about the file
/// rather than about the engine.
@MainActor
final class UnreadableAppRulesReachTheScreenTests: XCTestCase {

    private var probes: [SettingsPageProbe] = []

    override func tearDown() {
        probes.forEach { $0.unmount() }
        probes = []
        super.tearDown()
    }

    /// A page whose store holds `rules` under the app-rules key, mounted.
    ///
    /// Both readings draw the empty state, because unreadable rules *are* no rules
    /// as far as everything else on the page is concerned — so the module's own
    /// orange plate in that empty state is in both and cancels.
    private func page(rules: String) -> SettingsPageProbe {
        let probe = SettingsPageProbe()
        probe.store.set(rules, for: KeepAwakeSettings.Key.autoAppRules)
        probes.append(probe)
        _ = probe.mount()
        return probe
    }

    private static let notRules = "{not rules at all"

    func testThePageSaysTheRulesCouldNotBeRead() throws {
        let well = try XCTUnwrap(page(rules: "").read(), "nothing drew — no window server")

        let broken = page(rules: Self.notRules)
        // The subject first: this string really is the state being drawn about.
        XCTAssertTrue(KeepAwakeSettings(store: broken.store).appRulesUnreadable,
                      "the fixture is readable, so the render below is of the well case twice")
        XCTAssertTrue(KeepAwakeSettings(store: broken.store).appTriggers.isEmpty,
                      "precondition: unreadable rules read as no rules, which is the silence")

        let ink = try XCTUnwrap(broken.read())
        XCTAssertGreaterThan(ink.warning, well.warning + 1000,
                             "the file holds a rules string nothing can read, every app rule is "
                             + "dead, and the page draws what it draws with no rules at all: "
                             + "\(well.warning) → \(ink.warning) warning-tinted pixels")
    }

    /// And an *empty* list says nothing, or the banner is on the page for
    /// everybody who has never added an app — which is everybody, at first.
    func testChoosingNoAppsIsNotAnError() throws {
        let empty = page(rules: "[]")
        XCTAssertFalse(KeepAwakeSettings(store: empty.store).appRulesUnreadable,
                       "«no apps» is being read as «rules that could not be read»")
        let quiet = try XCTUnwrap(empty.read(), "nothing drew — no window server")

        let ink = try XCTUnwrap(page(rules: Self.notRules).read())
        XCTAssertGreaterThan(ink.warning, quiet.warning + 1000,
                             "a stored `[]` and a stored non-answer draw the same page, so the "
                             + "banner is either always there or never")
    }
}
