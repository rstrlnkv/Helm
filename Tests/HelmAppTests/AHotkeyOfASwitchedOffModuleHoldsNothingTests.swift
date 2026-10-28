import Carbon.HIToolbox
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import HelmApp

/// **A registered combination that does nothing is a key taken from every other
/// program for no reason.** The host registers every module's declared shortcuts at
/// launch, whether or not the module is on, and the manager is asked at every
/// reload whether the module that owns one is running: a switched-off module
/// holds no combination, even one somebody recorded and even one it ships with.
@MainActor
final class AHotkeyOfASwitchedOffModuleHoldsNothingTests: XCTestCase {

    private let fallback = HotkeyFallback(keyCode: 19, modifiers: cmdKey | shiftKey, label: "⇧⌘2")

    private func store(_ values: [String: Any] = [:]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.test.\(key)") }
        return NamespacedStore(namespace: "test", backing: backing)
    }

    func testASwitchedOffModuleHoldsNothingWhateverIsStored() {
        let recorded = store(["hotkeyKeyCode": 21, "hotkeyModifiers": cmdKey | shiftKey])
        for (what, store) in [("recorded", recorded), ("shipped", self.store())] {
            XCTAssertNil(HotkeyManager.combination(store: store, prefix: "hotkey", fallback: fallback, isLive: false),
                         "\(what): a switched-off module still held its combination")
            XCTAssertNotNil(HotkeyManager.combination(store: store, prefix: "hotkey", fallback: fallback, isLive: true),
                            "\(what): the same store held nothing while the module was on, so the test above proves nothing")
        }
    }

    /// **Every screenshot shortcut, the panel's included, goes through the same
    /// four answers.** `ScreenshotsDescriptor.hotkeys` maps every case and the host's loop registers
    /// what it declares, so a case added to the enum is registered; this asks the manager what each holds: nothing
    /// while the module is off, its shipped combination when nothing was
    /// recorded (⇧⌘8 for the panel), nothing when the person cleared it, and
    /// what they recorded otherwise.
    func testEveryScreenshotShortcutIncludingThePanelHoldsWhatItShouldInEveryState() throws {
        XCTAssertTrue(ScreenshotsHotkey.allCases.contains(.panel), "the panel has no shortcut of its own")
        let prefix = "module.screenshots."
        for hotkey in ScreenshotsHotkey.allCases {
            let shipped = hotkey.fallback
            let backing = { (values: [String: Any]) -> NamespacedStore in
                let backing = InMemoryKeyValueStore()
                for (key, value) in values { backing.set(value, forKey: prefix + key) }
                return NamespacedStore(namespace: "screenshots", backing: backing)
            }
            let fresh = backing([:])
            let live = HotkeyManager.combination(store: fresh, prefix: hotkey.storePrefix, fallback: shipped, isLive: true)
            XCTAssertEqual(live?.code, UInt32(shipped.keyCode), "\(hotkey): absent is not the shipped key")
            XCTAssertEqual(live?.label, shipped.label, "\(hotkey)")
            XCTAssertNil(HotkeyManager.combination(store: fresh, prefix: hotkey.storePrefix, fallback: shipped, isLive: false),
                         "\(hotkey): a switched-off module held its shipped combination")
            let cleared = backing(["\(hotkey.storePrefix)KeyCode": -1, "\(hotkey.storePrefix)Modifiers": 0])
            XCTAssertNil(HotkeyManager.combination(store: cleared, prefix: hotkey.storePrefix, fallback: shipped, isLive: true),
                         "\(hotkey): a cleared shortcut came back as the default")
            let recorded = backing(["\(hotkey.storePrefix)KeyCode": 23, "\(hotkey.storePrefix)Modifiers": cmdKey | shiftKey])
            XCTAssertEqual(HotkeyManager.combination(store: recorded, prefix: hotkey.storePrefix, fallback: shipped, isLive: true)?.code, 23,
                           "\(hotkey): a recorded combination was not the one held")
            XCTAssertNil(HotkeyManager.combination(store: recorded, prefix: hotkey.storePrefix, fallback: shipped, isLive: false),
                         "\(hotkey): a switched-off module held what was recorded")
        }
        XCTAssertEqual(ScreenshotsHotkey.panel.fallback.label, "⇧⌘8")
    }

    /// The other half: the manager must actually ask. A pure function that nobody
    /// asks is a check that cannot fail, so the host's registration is read for
    /// the question — and the manager for the reloads that follow a switch.
    /// Every combination is registered in one place, the loop over the registry
    /// in `ModuleHost`, which hands each one `isLive:` reading the host's `live`.
    func testEveryDeclaredHotkeyAsksWhetherItsModuleIsRunning() throws {
        let call = "HotkeyManager.shared.register("
        let delegate = try RepoSource.text(of: "Sources/HelmApp/AppDelegate.swift")
        XCTAssertFalse(delegate.contains(call),
                       "AppDelegate.swift registers a combination itself: registration belongs to the one loop in ModuleHost.registerHotkeys(), which every module's declared hotkeys go through and which asks isLive: of each")

        let host = try RepoSource.text(of: "Sources/HelmApp/ModuleHost.swift")
        let registrations = host.components(separatedBy: call).count - 1
        XCTAssertEqual(registrations, 1,
                       "ModuleHost.swift must hold exactly one \(call) (found \(registrations)); if the call was renamed, look for the single registration loop in registerHotkeys()")
        if let at = host.range(of: call) {
            let before = String(host[..<at.lowerBound].suffix(600))
            let after = String(host[at.upperBound...].prefix(900))
            XCTAssertTrue(before.range(of: #"for\s+[^\n]+\s+in\s+ModuleRegistry\.all"#, options: .regularExpression) != nil,
                          "the registration is not inside a `for … in ModuleRegistry.all` loop: a module added to the registry would hold no key; if the loop was renamed, look for the iteration over ModuleRegistry.all above the register call")
            XCTAssertTrue(after.range(of: #"isLive:[^\n]*live\["#, options: .regularExpression) != nil,
                          "the registration's arguments carry no `isLive:` reading `live[`: the manager is not asked whether the module is running; if renamed, look for isLive: closure reading the host's live[id]")
        }

        let manager = try RepoSource.text(of: "Sources/HelmApp/HotkeyManager.swift")
        for name in [".helmModuleEnabled", ".helmModuleDisabled"] {
            XCTAssertTrue(manager.contains(name),
                          "the manager does not re-register when a module is switched (\(name))")
        }
        XCTAssertTrue(manager.contains("binding.isLive()"), "reload() never asks isLive")
    }
}
