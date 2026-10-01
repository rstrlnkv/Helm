import Carbon.HIToolbox
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **A registered combination that does nothing is a key taken from every other
/// program for no reason.** The host registers the screenshot shortcuts at
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

    /// The other half: the manager must actually ask. A pure function that nobody
    /// asks is a check that cannot fail, so the host's registration is read for
    /// the question — and the manager for the reloads that follow a switch.
    func testTheHostAsksWhetherTheModuleIsRunning() throws {
        let host = try RepoSource.text(of: "Sources/HelmApp/AppDelegate.swift")
        let loop = try XCTUnwrap(host.range(of: "for hotkey in ScreenshotsHotkey.allCases"))
        let body = String(host[loop.lowerBound...].prefix(900))
        XCTAssertTrue(body.contains("isLive:") && body.contains("liveModule(screenshotsID)"),
                      "the screenshot shortcuts are registered without asking whether the module is live")
        XCTAssertTrue(body.contains("fallback: hotkey.fallback"), "the shortcuts ship with no default")

        let manager = try RepoSource.text(of: "Sources/HelmApp/HotkeyManager.swift")
        for name in [".helmModuleEnabled", ".helmModuleDisabled"] {
            XCTAssertTrue(manager.contains(name),
                          "the manager does not re-register when a module is switched (\(name))")
        }
        XCTAssertTrue(manager.contains("binding.isLive()"), "reload() never asks isLive")
    }
}
