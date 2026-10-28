import Carbon.HIToolbox
import HelmRuntime
import HelmTestSupport
import HelmUI
import Module_KeepAwake_UI
import Module_Layout_Engine
import Module_Layout_UI
import Module_Screenshots_UI
import XCTest
@testable import HelmApp

/// **A hotkey wired to a misspelt name is silence with no symptom at all.**
///
/// The *store prefix* is where the recorded combination lives
/// (`<prefix>KeyCode`, `<prefix>Modifiers`, `<prefix>Label`), so the host reading
/// one prefix and the page writing another means somebody records a chord, sees
/// it drawn in the row, and it does nothing — for ever.
///
/// `LayoutDescriptor.hotkeys` declares the chord from `LayoutHotkey.fix` and `LayoutHotkey.storePrefix`; the host registers what it declares.
///
/// The value is frozen because the prefix names **stored data**: a rename
/// silently loses everybody's recorded shortcut.
final class TheHotkeyNamesAreOneDeclarationTests: XCTestCase {

    /// **Stored data, and a shipped default.** `HelmHotkeyRecorder` writes
    /// `convertHotkeyKeyCode`, `convertHotkeyModifiers` and `convertHotkeyLabel`
    /// inside the module's store; `HotkeyManager` reads the first two, the recorder
    /// reads the label back. A rename here is a chord that vanishes from a page that
    /// still draws it.
    func testTheRecordedChordKeepsTheKeysItWasSavedUnder() {
        XCTAssertEqual(LayoutHotkey.storePrefix, "convertHotkey", """
            the recorder's key prefix moved, so every shortcut anybody has already recorded is \
            now read from keys nothing writes: the row draws the stored label and the chord \
            does nothing. A new setting takes a new name; a deployed one never moves.
            """)
    }

    /// **The host registers whatever the descriptors declare, so the declaration is
    /// the one place the stored keys can drift.** The literals below are what the
    /// host registered before descriptors declared them: a slot is what
    /// `HotkeyStatus` and the page ask about, a prefix is where the recorded
    /// chord lives, a fallback is what works before anybody recorded anything.
    /// For each, a chord recorded under exactly that prefix is held while the
    /// module is live and nothing while it is off.
    @MainActor
    func testEveryModuleDeclaresTheKeysItsChordsAreStoredUnder() {
        let shifted = cmdKey | shiftKey
        let expected: [(namespace: String, declared: [ModuleHotkey], want: [ModuleHotkey])] = [
            ("keep-awake", KeepAwakeDescriptor.hotkeys,
             [ModuleHotkey(slot: "keep-awake.toggle", prefix: "hotkey")]),
            ("layout", LayoutDescriptor.hotkeys,
             [ModuleHotkey(slot: "layout.fix", prefix: "convertHotkey")]),
            ("screenshots", ScreenshotsDescriptor.hotkeys, [
                ModuleHotkey(slot: "screenshots.area", prefix: "areaHotkey",
                             fallback: HotkeyFallback(keyCode: 19, modifiers: shifted, label: "⇧⌘2")),
                ModuleHotkey(slot: "screenshots.fullScreen", prefix: "fullScreenHotkey",
                             fallback: HotkeyFallback(keyCode: 18, modifiers: shifted, label: "⇧⌘1")),
                ModuleHotkey(slot: "screenshots.panel", prefix: "panelHotkey",
                             fallback: HotkeyFallback(keyCode: 28, modifiers: shifted, label: "⇧⌘8")),
            ]),
        ]
        for (namespace, declared, want) in expected {
            XCTAssertEqual(declared, want, "\(namespace): the declaration moved off what was registered and stored")
            XCTAssertFalse(want.isEmpty)
            for hotkey in declared {
                let backing = InMemoryKeyValueStore()
                backing.set(21, forKey: "module.\(namespace).\(hotkey.prefix)KeyCode")
                backing.set(shifted, forKey: "module.\(namespace).\(hotkey.prefix)Modifiers")
                let store = NamespacedStore(namespace: namespace, backing: backing)
                XCTAssertNil(HotkeyManager.combination(store: store, prefix: hotkey.prefix,
                                                       fallback: hotkey.fallback, isLive: false),
                             "\(hotkey.slot): a switched-off module held its recorded chord")
                XCTAssertEqual(HotkeyManager.combination(store: store, prefix: hotkey.prefix,
                                                         fallback: hotkey.fallback, isLive: true)?.code, 21,
                               "\(hotkey.slot): the chord recorded under the declared prefix was not read")
            }
        }
    }
}
