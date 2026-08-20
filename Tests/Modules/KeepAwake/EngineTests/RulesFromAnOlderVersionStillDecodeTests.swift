import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The app rules are the one document this module keeps that really does cross
/// builds, and `AppTrigger` decodes it with a synthesised `Decodable`.
///
/// The wire payload next door has a hand-written `init(from:)` because a
/// synthesised one requires every key whatever a property's initial value is.
/// This type has the same exposure and none of the repair, and the difference
/// matters more here: the payload is re-sent by the engine a moment later, while
/// this string sits in `~/Library/Preferences` and is read by whatever build is
/// installed next. A field added without `decodeIfPresent` does not lose one
/// rule — `JSONDecoder` refuses the whole array, `readable` answers nil, and
/// `KeepAwakeSettings.AppRulesReading.unreadable` drops **every** rule the
/// person ever chose. The Mac stops being held awake and the page says the file
/// cannot be read.
///
/// Nothing has been added since v0.9.0, so this file is a fence rather than a
/// report: it fails on the first field that arrives without a default. The 0.10
/// plan asked for exactly this file, beside a `Watch` field on `AppTrigger` and
/// a hand-written `init(from:)` to carry it — neither of which was built, so the
/// next person to add one starts where that plan did.
final class RulesFromAnOlderVersionStillDecodeTests: XCTestCase {

    /// What `AppTriggerRules.encode` wrote at v0.9.0 — three keys, checked
    /// against `git show v0.9.0:…/Logic/AppTrigger.swift`. A build that cannot
    /// read this is a build that silently forgets somebody's rules.
    private let asTheLastReleaseWroteThem = """
    [{"bundleID":"com.example.render","needsExternalDisplay":false,"needsPower":true},\
    {"bundleID":"com.example.edit","needsExternalDisplay":true,"needsPower":false}]
    """

    func testTheRulesAShippedBuildWroteAreStillReadable() throws {
        let rules = try XCTUnwrap(AppTriggerRules.readable(asTheLastReleaseWroteThem),
                                  "every rule the person chose was dropped, and the page can "
                                  + "only say the file cannot be read")

        XCTAssertEqual(rules.map(\.bundleID), ["com.example.render", "com.example.edit"])
        XCTAssertEqual(rules[0].condition, .power)
        XCTAssertEqual(rules[1].condition, .externalDisplay)
    }

    /// And through the settings, which is the path the engine actually takes —
    /// `readable` answering nil there is the banner as well as the empty list.
    func testAStoreHoldingThoseRulesIsNotReportedAsUnreadable() {
        let store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        store.set(asTheLastReleaseWroteThem, for: KeepAwakeSettings.Key.autoAppRules)
        let settings = KeepAwakeSettings(store: store)

        XCTAssertFalse(settings.appRulesUnreadable)
        XCTAssertEqual(settings.appTriggers.count, 2)
    }

    /// What it costs, stated once so the fence above has its reason in the file:
    /// one rule the decoder cannot read takes every other rule with it. This is
    /// deliberate — «refused, not truncated» — and it is precisely why the
    /// document's shape may only ever gain optional fields.
    func testOneRuleTheDecoderRefusesTakesAllOfThemDown() {
        let oneFieldShort = """
        [{"bundleID":"com.example.render","needsExternalDisplay":false,"needsPower":true},\
        {"bundleID":"com.example.edit","needsExternalDisplay":true}]
        """

        XCTAssertNil(AppTriggerRules.readable(oneFieldShort),
                     "precondition: a rule missing a required key is refused")
        XCTAssertEqual(AppTriggerRules.decode(oneFieldShort), [],
                       "and the rule beside it, which is perfectly readable, goes with it")
    }
}
