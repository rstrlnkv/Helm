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
        // **Two, and each departure is recorded.** The source-name switch left
        // on 2026-08-30 and became `BadgeStyle.sourceName`: it was the one item
        // here that changed how the indicator *looks*, reachable from nowhere
        // else, so switching it on left the settings page's Style picker and
        // preview grid describing a badge that had stopped being drawn.
        //
        // The emoji palette left next. It was the only part of this menu that
        // needed Accessibility — an AX press of *another* app's Edit-menu item,
        // matched by title out of `InputManager.loctable` — while the settings
        // page draws «the language indicator below works without this
        // permission» directly above the section offering it. In exactly the
        // state that sentence was written for, one of three items beeped. Every
        // Mac opens the same palette with Globe+E.
        XCTAssertEqual(tail.count, 2, """
            the menu is two sections under one separator: the layouts and the \
            keyboard settings — what macOS's own input menu draws, minus the \
            Keyboard Viewer (see the class doc for why that door cannot be \
            opened), minus the source-name switch, which is a style on the \
            settings page now, and minus the emoji palette, which was the one \
            door here that needed a permission this menu promises not to need.
            """)
        XCTAssertEqual(try section(menu, 1).map(\.title), [LyStr.openKeyboardSettings],
                       "and the menu ends with the keyboard settings door")
        for item in tail.dropFirst().flatMap({ $0 }) {
            XCTAssertTrue(item.target === built.indicator,
                          "«\(item.title)» is aimed at nobody: pressing it would do nothing")
            XCTAssertNotNil(item.action,
                            "«\(item.title)» has no action: pressing it would do nothing")
        }
    }

    /// **The emoji door and its icon test are gone.** It carried the palette's
    /// own icon, the one TIS hands out for `com.apple.CharacterPaletteIM`, and
    /// the test said so — but the door itself needed Accessibility on a menu
    /// whose section on the settings page promises to work without it.

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

    /// The switch that used to live in section 2 was tested here for flipping
    /// its own stored key. It is `BadgeStyle.sourceName` now — chosen from the
    /// settings page's Style picker like every other look — so what needs
    /// covering is the carry-over, not a menu item that no longer exists:
    /// `TheOldNameSettingBecomesAStyleTests`.

    /// The item this pinned against `TextInputMenuCore` is gone: «Show Input
    /// Source Name» left the menu and became `BadgeStyle.sourceName`, and the
    /// style is named «Layout name» rather than the system's phrase.
    ///
    /// **Deliberate, and the rule it looks like it breaks it does not.** The
    /// house rule is to read macOS's spelling for a thing macOS also names —
    /// and macOS names a *switch* there. Here the words are the value of a
    /// «Style» picker, so the row read «Вид: Показывать имя источника ввода»,
    /// an instruction standing where a noun belongs. The rule covers the same
    /// thing, not the same words in a different grammatical role.
    ///
    /// The system's phrases are still read for the two doors that remain, and
    /// the tests for those are below.

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

    /// **The palette name went with the door.** It was AppKit's own, read from
    /// `InputManager.loctable` (key `Emoji & Symbols`), and pinned here per
    /// language so a drift in the name could not hide behind a drift in the
    /// template that wrapped it. Both are gone: the item needed Accessibility on
    /// a menu whose section promises to work without it, and Globe+E opens the
    /// same palette on every Mac.
}
