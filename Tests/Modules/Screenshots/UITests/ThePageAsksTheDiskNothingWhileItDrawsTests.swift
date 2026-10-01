import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Drawing the settings page asks the disk nothing about a protected folder.**
/// `isWritableFile` on Documents or the Desktop is what can raise the system's
/// prompt, and a view body runs on every render: a page that probed from its
/// body would ask on every render, and on merely being opened. The selected
/// target is judged from a task, once; a target that is not selected is never
/// judged at all.
@MainActor
final class ThePageAsksTheDiskNothingWhileItDrawsTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private final class Probes { var paths: [String] = [] }

    private func page(target: SaveTarget, _ probes: Probes) -> MountedRender {
        AppLanguage.override = .en
        let backing = InMemoryKeyValueStore()
        backing.set(target.rawValue, forKey: "module.screenshots.\(ScreenshotsSettings.Key.saveTarget)")
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        let transport = LocalTransport()
        transport.emit(ScreenshotsEvent.screenshotsState, encoding: ScreenshotsPageRender.untouched)
        return MountedRender(
            ScreenshotsSettingsPage(vm: ModuleViewModel(transport: transport), store: store,
                                    writable: { probes.paths.append($0); return true })
                .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted,
                                                      screenRecording: .granted)),
            width: 744, height: 900, appearance: .aqua)
    }

    private var documents: String { ScreenshotsLocations.system.documents.path }

    func testTheSelectedFolderIsJudgedOnceFromTheTaskAndNoRenderRepeatsIt() {
        let probes = Probes()
        let mount = page(target: .documents, probes)
        mount.settle(40)
        XCTAssertEqual(probes.paths, [documents], "the control: the selected target is judged, once")
        NotificationCenter.default.post(name: .helmHotkeyChanged, object: nil)
        mount.settle(40)
        XCTAssertEqual(probes.paths, [documents], "a re-render asked the disk again")
    }

    func testADocumentsThatIsNotSelectedIsNeverAsked() {
        let probes = Probes()
        let mount = page(target: .desktop, probes)
        mount.settle(40)
        XCTAssertEqual(probes.paths, [ScreenshotsLocations.system.desktop.path], "the control: the Desktop is judged")
        XCTAssertFalse(probes.paths.contains(documents), "Documents was probed though it is not the target")
        let macOS = Probes()
        page(target: .macOS, macOS).settle(40)
        XCTAssertEqual(macOS.paths, [], "macOS's own folder is the engine's to judge, not the page's")
    }
}
