import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import ObjectiveC
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The page never opens the folder chooser because the bar's choice of
/// «Other…» arrived through the store.** The page
/// mirrors the bar's writes into its own `target`, and its picker reacts to any
/// change of `target` — so a mirrored «Other…» reaches the same handler a
/// person's pick does. That handler returns early when the store already holds
/// «Other…»; these cases pin that the mirror opens nothing, and that the
/// chooser the page calls is the one counted here. A person picking or
/// pressing on the page cannot be driven headless: its picker and button draw
/// no AppKit control.
///
/// And the mirror is not a loop: the bar's write comes back from the page at
/// most as an equal value, the exchange stops, and the last word is the bar's.
///
/// No panel reaches a screen: `runModal` on the open panel's class answers
/// «cancel» and counts, and activation is a no-op, for the length of each case.
@MainActor
final class TheFolderChooserOpensOnlyWhenAskedTests: XCTestCase {

    nonisolated(unsafe) private static var opened = 0

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// Stands the chooser and activation in for the length of one case.
    private func arm() {
        _ = NSApplication.shared
        Self.opened = 0
        let panelClass: AnyClass = object_getClass(NSOpenPanel())!
        let counted: @convention(block) (AnyObject) -> Int = { _ in
            TheFolderChooserOpensOnlyWhenAskedTests.opened += 1
            return NSApplication.ModalResponse.cancel.rawValue
        }
        let quiet: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
        let undoPanel = Self.replace(#selector(NSSavePanel.runModal), on: panelClass, with: counted)
        let undoActivate = Self.replace(#selector(NSApplication.activate(ignoringOtherApps:)),
                                        on: NSApplication.self, with: quiet)
        addTeardownBlock { undoActivate(); undoPanel() }
    }

    /// Swaps one method's implementation on one class, and hands back the swap
    /// that puts the original back.
    nonisolated private static func replace(_ selector: Selector, on cls: AnyClass, with block: Any) -> @Sendable () -> Void {
        let method = class_getInstanceMethod(cls, selector)!
        nonisolated(unsafe) let types = method_getTypeEncoding(method)
        nonisolated(unsafe) let original = class_getMethodImplementation(cls, selector)!
        class_replaceMethod(cls, selector, imp_implementationWithBlock(block), types)
        return { class_replaceMethod(cls, selector, original, types) }
    }

    /// Every write that reaches the backing, in order, by short key.
    private final class Spy: KeyValueStore {
        let inner = InMemoryKeyValueStore()
        var writes: [(key: String, value: Any?)] = []
        func object(forKey key: String) -> Any? { inner.object(forKey: key) }
        func set(_ value: Any?, forKey key: String) {
            writes.append((String(key.split(separator: ".").last ?? ""), value))
            inner.set(value, forKey: key)
        }
        func count(_ key: String) -> Int { writes.filter { $0.key == key }.count }
    }

    /// The folders the page judged, in order — the page's own reading of which
    /// target and folder it now holds, since its pickers draw no AppKit control
    /// a test can read.
    private final class Judged { var paths: [String] = [] }

    private func mount(_ store: NamespacedStore, _ judged: Judged = Judged()) -> MountedRender {
        AppLanguage.override = .en
        let transport = LocalTransport()
        transport.emit(ScreenshotsEvent.screenshotsState, encoding: ScreenshotsPageRender.untouched)
        let mount = MountedRender(
            ScreenshotsSettingsPage(vm: ModuleViewModel(transport: transport), store: store,
                                    writable: { judged.paths.append($0); return true })
                .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted,
                                                      screenRecording: .granted)),
            width: 744, height: 900, appearance: .aqua)
        mount.settle(40)
        return mount
    }

    private func store(_ spy: Spy, target: SaveTarget, folder: String? = nil) -> NamespacedStore {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: spy)
        spy.inner.set(target.rawValue, forKey: "module.screenshots.\(ScreenshotsSettings.Key.saveTarget)")
        if let folder { spy.inner.set(folder, forKey: "module.screenshots.\(ScreenshotsSettings.Key.otherFolder)") }
        return store
    }

    /// The control: the stand-in sees the chooser the page and the bar both
    /// call, so a zero below is a chooser that did not open and not one that
    /// opened somewhere this count cannot see.
    func testTheStandInSeesTheChooser() {
        arm()
        guard case .cancelled = ScreenshotsSettingsPage.askForFolder() else {
            return XCTFail("the stand-in did not answer «cancel»")
        }
        XCTAssertEqual(Self.opened, 1, "the page's chooser opened past the stand-in")
    }

    /// The case: the bar chose «Other…» and a folder — written in the order its
    /// own `choose(.other)` writes them — while the page was up on the Desktop.
    /// The page follows (it judges the new folder) and asks the person nothing.
    func testAnOtherTheBarChoseOpensNothingOnThePage() {
        arm()
        // A folder that exists, or the judgement falls back to the Desktop.
        let folder = scratchDirectory("screenshots-chooser").path
        let spy = Spy()
        let judged = Judged()
        let store = store(spy, target: .desktop)
        let page = mount(store, judged)
        XCTAssertEqual(judged.paths, [ScreenshotsLocations.system.desktop.path], "the control: the page holds the Desktop")
        store.set(folder, for: ScreenshotsSettings.Key.otherFolder)
        store.set(SaveTarget.other.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        page.settle(40)
        let leaf = (folder as NSString).lastPathComponent
        XCTAssertEqual(judged.paths.last.map { ($0 as NSString).lastPathComponent }, leaf,
                       "the page did not follow the bar to «Other…» and its folder: \(judged.paths)")
        XCTAssertEqual(Self.opened, 0, "the bar's «Other…» opened the folder chooser on the settings page")
        let settings = ScreenshotsSettings.read(store)
        XCTAssertEqual(settings.saveTarget, .other)
        XCTAssertEqual(settings.otherFolder, folder)
    }

    /// The mirror is not a loop: each bar write comes back from the page at
    /// most once, equal, the exchange stops, and a burst ends on the bar's
    /// last word rather than on a value the page caught on the way.
    func testTheBarAndThePageDoNotWriteEachOtherForEver() {
        arm()
        let spy = Spy()
        let judged = Judged()
        let store = store(spy, target: .desktop)
        let page = mount(store, judged)
        let bar = CapturePanelModel(store: store)

        bar.setCursor(true)
        page.settle(40)
        let afterOne = spy.count(ScreenshotsSettings.Key.showCursor)
        XCTAssertGreaterThanOrEqual(afterOne, 1, "the bar's write never reached the backing, so nothing below is read")
        XCTAssertLessThanOrEqual(afterOne, 2, "one bar write came back more than once: \(spy.writes.map(\.key))")
        XCTAssertTrue(spy.writes.filter { $0.key == ScreenshotsSettings.Key.showCursor }
                        .allSatisfy { ($0.value as? Bool) == true },
                      "the page wrote back a value the bar had not written")
        page.settle(40)
        XCTAssertEqual(spy.count(ScreenshotsSettings.Key.showCursor), afterOne, "the exchange is still going")

        // The subject: the page does follow, so a quiet backing below is a
        // mirror that settled and not a mirror that never ran.
        store.set(SaveTarget.documents.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        page.settle(40)
        XCTAssertEqual(judged.paths.last, ScreenshotsLocations.system.documents.path,
                       "the page did not follow the store at all, so the quiet below proves nothing")

        // A burst inside one turn: the page's handlers run after all of it.
        bar.setCursor(false); bar.setCursor(true); bar.setCursor(false)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        store.set(SaveTarget.clipboard.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        page.settle(40)
        let settled = spy.writes.count
        page.settle(40)
        XCTAssertEqual(spy.writes.count, settled, "the exchange did not stop: \(spy.writes.suffix(8).map(\.key))")
        XCTAssertFalse(ScreenshotsSettings.read(store).showCursor, "the burst ended on a value the page wrote back late")
        XCTAssertEqual(ScreenshotsSettings.read(store).saveTarget, .clipboard,
                       "the target burst ended on a value the page wrote back late")
        XCTAssertEqual(Self.opened, 0)
    }
}
