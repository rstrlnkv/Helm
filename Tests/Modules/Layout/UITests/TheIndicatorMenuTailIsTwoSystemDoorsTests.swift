import AppKit
import HelmRuntime
import HelmUI
import XCTest
@testable import Module_Layout_UI
import Module_Layout_Engine

/// The indicator's menu ends with two doors into the system: the emoji palette
/// and the keyboard settings, below one separator, in that order — the same
/// order macOS's own input menu draws them.
///
/// The assertion is on the tail's structure, not on how many layouts sit above
/// it: that count is whatever this machine has installed. Building the menu
/// through `menuNeedsUpdate` on a plain `NSMenu` is deliberate — no
/// `NSStatusItem` is built, so the test decorates nothing
/// (see `BuildingAnEngineDoesNotDecorateTheMenuBarTests`).
@MainActor
final class TheIndicatorMenuTailIsTwoSystemDoorsTests: XCTestCase {

    private func builtMenu() -> (NSMenu, LanguageIndicator) {
        let store = NamespacedStore(namespace: LayoutDescriptor.id.rawValue,
                                    backing: InMemoryKeyValueStore())
        let indicator = LanguageIndicator(store: store)
        let menu = NSMenu()
        indicator.menuNeedsUpdate(menu)
        return (menu, indicator)
    }

    func testBelowTheSeparatorSitTheEmojiPaletteAndTheKeyboardSettings() {
        let (menu, indicator) = builtMenu()

        let separators = menu.items.enumerated().filter { $0.element.isSeparatorItem }
        XCTAssertEqual(separators.count, 1,
                       "the menu is a list of layouts, one separator, and the system doors")
        let tail = menu.items.suffix(from: separators[0].offset + 1)

        XCTAssertEqual(tail.map(\.title), [LyStr.emojiAndSymbols, LyStr.openKeyboardSettings], """
            below the separator the menu ends with the emoji palette and then the \
            keyboard settings — macOS's own input menu's order. A missing title here \
            is a door removed; a different order is a door moved.
            """)
        for item in tail {
            XCTAssertTrue(item.target === indicator,
                          "«\(item.title)» is aimed at nobody: pressing it would do nothing")
            XCTAssertNotNil(item.action,
                            "«\(item.title)» has no action: pressing it would do nothing")
        }
    }

    /// The words on the item are macOS's own, read from AppKit's
    /// `InputManager.loctable` (key `Emoji & Symbols`) — not translated again.
    /// The test pins all eight against that table's spellings, because the
    /// `.strings` files are where a retranslation would creep in; the check on
    /// `LyStr` alone would read the same constant from both sides.
    func testTheEmojiItemSpeaksTheSystemsOwnWords() {
        let system: [AppLanguage: String] = [
            .en: "Emoji & Symbols",
            .ru: "Эмодзи и символы",
            .es: "Emojis y símbolos",
            .fr: "Emoji et symboles",
            .de: "Emoji & Symbole",
            .ja: "絵文字と記号",
            .zh: "表情与符号",
            .pt: "Emoji e Símbolos",
        ]
        for language in AppLanguage.allCases {
            XCTAssertEqual(L("Emoji & Symbols", language: language), system[language], """
                \(language) does not say what macOS's own Edit menu says. The name is \
                AppKit's, from `InputManager.loctable`; Helm's zh follows `zh_CN` and \
                its pt follows `pt_BR`, the variants the rest of the app follows.
                """)
        }
    }
}
