import AppKit
import HelmRuntime
import HelmUI
import XCTest
@testable import Module_Layout_UI
import Module_Layout_Engine

/// The indicator's menu follows macOS's own input menu, section by section:
/// the layouts each wearing their badge, then the emoji palette door, then the
/// «show input source name» switch, then the keyboard settings door — three
/// separators, in the system's order.
///
/// No Keyboard Viewer item, deliberately: every route to opening it was
/// measured dead on macOS 27 (`TISSelectInputSource` of
/// `com.apple.inputmethod.AssistiveControl` answers success and draws nothing,
/// launching the input-method bundle is refused by launchd, and the system's
/// own menu item exists only while the system indicator is on — the indicator
/// Helm's hint tells people to switch off). A menu item that does nothing is
/// worse than a missing one.
///
/// The assertion is on structure, not on how many layouts sit above the first
/// separator: that count is whatever this machine has installed. Building the
/// menu through `menuNeedsUpdate` on a plain `NSMenu` is deliberate — no
/// `NSStatusItem` is built, so the test decorates nothing
/// (see `BuildingAnEngineDoesNotDecorateTheMenuBarTests`).
@MainActor
final class TheIndicatorMenuFollowsTheSystemInputMenuTests: XCTestCase {

    /// A struct, not a tuple: the indicator must stay named at the call site —
    /// `NSMenuItem.target` is weak, so a discarded indicator turns every press
    /// into a silent no-op, which the first draft of the switch test proved by
    /// accident.
    private struct Built {
        let menu: NSMenu
        let indicator: LanguageIndicator
        let store: NamespacedStore
    }

    private func builtMenu(store: NamespacedStore? = nil) -> Built {
        let store = store ?? NamespacedStore(namespace: LayoutDescriptor.id.rawValue,
                                            backing: InMemoryKeyValueStore())
        let indicator = LanguageIndicator(store: store)
        let menu = NSMenu()
        indicator.menuNeedsUpdate(menu)
        return Built(menu: menu, indicator: indicator, store: store)
    }

    private func sections(of menu: NSMenu) -> [[NSMenuItem]] {
        var result: [[NSMenuItem]] = [[]]
        for item in menu.items {
            if item.isSeparatorItem { result.append([]) } else { result[result.count - 1].append(item) }
        }
        return result
    }

    /// The section at `index`, or a failure — not a trap. A dropped separator
    /// under the plain subscript took the whole process down with it, which
    /// reads as a crash rather than as the structural failure it is.
    private func section(_ menu: NSMenu, _ index: Int,
                         file: StaticString = #filePath, line: UInt = #line) throws -> [NSMenuItem] {
        let all = sections(of: menu)
        guard all.indices.contains(index) else {
            XCTFail("the menu has \(all.count) sections, no section \(index)", file: file, line: line)
            throw XCTSkip("structure already failed above")
        }
        return all[index]
    }

    func testTheTailIsTheSystemMenusOwnOrder() throws {
        let built = builtMenu()
        let menu = built.menu

        let tail = sections(of: menu)
        XCTAssertEqual(tail.count, 4, """
            the menu is four sections under three separators: layouts, the emoji \
            palette, the source-name switch, the keyboard settings — the sections \
            macOS's own input menu draws, minus the Keyboard Viewer (see the class \
            doc for why that door cannot be opened).
            """)
        XCTAssertEqual(try section(menu, 1).map(\.title), [LyStr.showEmojiPanel()],
                       "the first section under the layouts is the emoji palette door alone")
        XCTAssertEqual(try section(menu, 2).map(\.title), [LyStr.showInputSourceName],
                       "then the source-name switch, in a section of its own")
        XCTAssertEqual(try section(menu, 3).map(\.title), [LyStr.openKeyboardSettings],
                       "and the menu ends with the keyboard settings door")
        for item in tail.dropFirst().flatMap({ $0 }) {
            XCTAssertTrue(item.target === built.indicator,
                          "«\(item.title)» is aimed at nobody: pressing it would do nothing")
            XCTAssertNotNil(item.action,
                            "«\(item.title)» has no action: pressing it would do nothing")
        }
    }

    /// The system menu draws the emoji door with the palette's own icon — the
    /// one TIS hands out for `com.apple.CharacterPaletteIM` — and so does Helm.
    /// Nil here means macOS moved the icon, and the door went bare silently.
    func testTheEmojiDoorWearsThePalettesOwnIcon() throws {
        let built = builtMenu()
        let emoji = try section(built.menu, 1).first
        XCTAssertNotNil(emoji?.image,
                        "the emoji door lost the palette's icon TIS hands out for it")
        XCTAssertEqual(emoji?.image?.isTemplate, true,
                       "the icon is a template, or it draws black on a dark menu")
    }

    /// Every layout row wears the same badge the menu bar draws for it — the
    /// system menu puts a layout icon on every row, and a row without one reads
    /// as a different kind of entry.
    func testEveryLayoutRowWearsItsBadge() throws {
        let built = builtMenu()
        let layouts = try section(built.menu, 0)
        XCTAssertFalse(layouts.isEmpty, "this machine has keyboard layouts installed")
        for row in layouts {
            XCTAssertNotNil(row.image, "«\(row.title)» has no badge beside it")
        }
    }

    /// The switch writes the setting and reads it back: pressing it flips
    /// `LayoutKey.indicatorShowsName`, and the rebuilt menu shows the new state
    /// — the same round trip the system's own item makes.
    func testTheSourceNameSwitchFlipsTheStoredSetting() throws {
        let built = builtMenu()
        let store = built.store
        let toggle = try XCTUnwrap(try section(built.menu, 2).first)
        XCTAssertEqual(toggle.state, .off, "the name is off until somebody asks for it")

        _ = toggle.target?.perform(toggle.action, with: toggle)
        XCTAssertTrue(store.bool(LayoutKey.indicatorShowsName, default: false),
                      "pressing the switch did not write the setting")

        let rebuilt = builtMenu(store: store)
        let after = try XCTUnwrap(try section(rebuilt.menu, 2).first)
        XCTAssertEqual(after.state, .on, "the rebuilt menu does not show the switch as on")

        _ = after.target?.perform(after.action, with: after)
        XCTAssertFalse(store.bool(LayoutKey.indicatorShowsName, default: false),
                       "pressing the switch again did not clear the setting")
    }

    /// The words on the items are macOS's own, read from the system's
    /// `TextInputMenuCore` table (`Localizable.loctable`) — not translated
    /// again. Pinned per language against that table's spellings, because the
    /// `.strings` files are where a retranslation would creep in; a check on
    /// `LyStr` alone would read the same constant from both sides. Helm's zh
    /// follows `zh_CN` and its pt follows `pt_BR`, the variants the rest of
    /// the app follows.
    func testTheSourceNameSwitchSpeaksTheSystemsOwnWords() {
        let system: [AppLanguage: String] = [
            .en: "Show Input Source Name",
            .ru: "Показывать имя источника ввода",
            .es: "Mostrar nombre de fuentes de entrada",
            .fr: "Afficher le nom de la source de saisie",
            .de: "Name der Eingabequelle einblenden",
            .ja: "入力ソース名を表示",
            .zh: "显示输入法名称",
            .pt: "Mostrar Nome do Layout de Teclado",
        ]
        for language in AppLanguage.allCases {
            XCTAssertEqual(L("Show Input Source Name", language: language), system[language], """
                \(language) does not say what macOS's own input menu says \
                (`TextInputMenuCore.bundle`, key `Show Name of Source in Menu Bar`).
                """)
        }
    }

    /// The emoji door's full title is built the way the system builds it: the
    /// `Show palette class IM` template around the palette's own name — so the
    /// sentence cannot drift from the palette it opens. Pinned against the
    /// system's construction per language.
    func testTheEmojiDoorSpeaksTheSystemsOwnWords() {
        let system: [AppLanguage: String] = [
            .en: "Show Emoji & Symbols",
            .ru: "Показать панель «Эмодзи и символы»",
            .es: "Mostrar Emojis y símbolos",
            .fr: "Afficher Emoji et symboles",
            .de: "Emoji & Symbole einblenden",
            .ja: "絵文字と記号を表示",
            .zh: "显示表情与符号",
            .pt: "Mostrar Emoji e Símbolos",
        ]
        for language in AppLanguage.allCases {
            XCTAssertEqual(LyStr.showEmojiPanel(language: language), system[language], """
                \(language) does not build the title the way macOS's own input menu \
                does (`TextInputMenuCore.bundle`, key `Show palette class IM`, around \
                AppKit's name for the palette).
                """)
        }
    }

    /// The settings door too: the system spells it `Open Keyboard Settings…`
    /// (`TextInputMenuCore.bundle`, key `Open Keyboard Settings`), German with
    /// a no-break space before the ellipsis — read, not retranslated.
    func testTheSettingsDoorSpeaksTheSystemsOwnWords() {
        let system: [AppLanguage: String] = [
            .en: "Open Keyboard Settings…",
            .ru: "Открыть настройки клавиатуры…",
            .es: "Abrir ajustes del teclado…",
            .fr: "Ouvrir les réglages Clavier…",
            .de: "Tastatureinstellungen öffnen\u{00A0}…",
            .ja: "キーボード設定を開く…",
            .zh: "打开键盘设置…",
            .pt: "Abrir Ajustes de Teclado…",
        ]
        for language in AppLanguage.allCases {
            XCTAssertEqual(L("Open Keyboard Settings…", language: language), system[language], """
                \(language) does not say what macOS's own input menu says \
                (`TextInputMenuCore.bundle`, key `Open Keyboard Settings`).
                """)
        }
    }

    /// The words on the emoji item are macOS's own, read from AppKit's
    /// `InputManager.loctable` (key `Emoji & Symbols`) — the palette name the
    /// template above wraps. Pinned separately: the full title's test would
    /// pass a drifted name if the pinned construction drifted with it.
    func testThePaletteNameSpeaksTheSystemsOwnWords() {
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
