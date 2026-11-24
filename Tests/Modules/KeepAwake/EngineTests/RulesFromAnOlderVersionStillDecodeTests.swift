import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The app rules are the one document this module keeps that really does cross
/// builds, and `AppTrigger` decodes it with a synthesised `Decodable`.
///
/// A synthesised `Decodable` requires every key whatever a property's initial
/// value is, and this type has no repair for that. It matters here because the
/// state is rebuilt by the engine a moment later, while this string sits in `~/Library/Preferences` and is read by whatever build is
/// installed next. A field added without `decodeIfPresent` does not lose one
/// rule — `JSONDecoder` refuses the whole array, `readable` answers nil, and
/// `KeepAwakeSettings.AppRulesReading.unreadable` drops **every** rule the
/// person ever chose. The Mac stops being held awake and the page says the file
/// cannot be read.
///
/// A fence: it fails on the first field that arrives without a default.
final class RulesFromAnOlderVersionStillDecodeTests: XCTestCase {

    /// A document as `AppTriggerRules.encode` writes it, three keys. A build
    /// that cannot read this silently forgets somebody's rules.
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
        XCTAssertEqual((AppTriggerRules.readable(oneFieldShort) ?? []), [],
                       "and the rule beside it, which is perfectly readable, goes with it")
    }
}
