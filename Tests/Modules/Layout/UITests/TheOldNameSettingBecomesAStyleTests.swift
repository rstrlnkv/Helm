import XCTest
@testable import Module_Layout_UI
@testable import Module_Layout_Engine
import HelmRuntime
import HelmTestSupport

/// «Show Input Source Name» was a stored key of its own, flipped from the status
/// item's menu. It is `BadgeStyle.sourceName` now.
///
/// **Deleting a key is taking somebody's choice away unless something carries
/// it.** Their menu bar would go back to a badge on the next launch with nothing
/// said — the same failure the three trigger switches would have had if the
/// engine had gone on reading keys no control could change.
///
/// The carry-over writes once and erases the old key in the same breath, so it
/// cannot argue with a style the person picks afterwards. Both halves are
/// asserted: that it carries, and that it then stops.
@MainActor
final class TheOldNameSettingBecomesAStyleTests: XCTestCase {

    private func store() -> NamespacedStore {
        NamespacedStore(namespace: "layout", backing: InMemoryKeyValueStore())
    }

    private func style(_ store: NamespacedStore) -> String {
        store.string(LayoutKey.badgeStyle, default: BadgeStyle.default.rawValue)
    }

    func testTheOldSettingBecomesTheStyle() {
        let store = store()
        store.set(true, for: LayoutKey.indicatorShowsName)
        _ = LanguageIndicator(store: store)
        XCTAssertEqual(style(store), BadgeStyle.sourceName.rawValue,
                       "somebody who had the layout's name showing lost it on this build")
    }

    func testTheOldKeyIsGoneAfterwards() {
        let store = store()
        store.set(true, for: LayoutKey.indicatorShowsName)
        _ = LanguageIndicator(store: store)
        XCTAssertFalse(store.bool(LayoutKey.indicatorShowsName, default: false),
                       "the old key survived the carry-over and will re-apply for ever")
    }

    /// The half that matters more than the carry itself: having carried once,
    /// it must never overrule a later choice. A migration that reads a key it
    /// did not erase is a setting that cannot be changed.
    func testALaterChoiceIsNotOverruled() {
        let store = store()
        store.set(true, for: LayoutKey.indicatorShowsName)
        _ = LanguageIndicator(store: store)
        store.set(BadgeStyle.flagDrawn.rawValue, for: LayoutKey.badgeStyle)
        _ = LanguageIndicator(store: store)
        XCTAssertEqual(style(store), BadgeStyle.flagDrawn.rawValue,
                       "the carry-over ran a second time and put the name back")
    }

    func testAStoreThatNeverHadTheOldKeyIsLeftAlone() {
        let store = store()
        _ = LanguageIndicator(store: store)
        XCTAssertEqual(style(store), BadgeStyle.default.rawValue,
                       "the carry-over wrote a style for somebody who never asked for one")
    }
}
