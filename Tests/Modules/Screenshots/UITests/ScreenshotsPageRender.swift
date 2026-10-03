import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// The settings page, mounted, in a named language and appearance, over a
/// transport that says what macOS says and nothing more.
@MainActor
enum ScreenshotsPageRender {

    /// The Keyboard boxes as macOS would answer with nothing ever touched.
    static let untouched = ScreenshotsState(folder: "/Users/someone/Desktop", folderRefused: nil,
                                            boxes: SystemShortcuts.boxes(from: .absent))

    static func mount(language: AppLanguage, appearance: NSAppearance.Name,
                      screenRecording: PermissionState = .granted,
                      state: ScreenshotsState = untouched,
                      values: [String: Any] = [:],
                      tab: ScreenshotsSettingsPage.Tab = .capturing,
                      width: CGFloat = 744) -> MountedRender {
        AppLanguage.override = language
        let transport = LocalTransport()
        transport.emit(ScreenshotsEvent.screenshotsState, encoding: state)
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.screenshots.\(key)") }
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        let vm = ModuleViewModel(transport: transport)
        let mount = MountedRender(
            ScreenshotsSettingsPage(vm: vm, store: store, tab: tab)
                .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted,
                                                      screenRecording: screenRecording)),
            width: width, height: 900, appearance: appearance)
        // The event crosses a task before the page hears it.
        mount.settle(40)
        return mount
    }

    /// What the page asks for, top to bottom, which is all a height can say.
    static func height(of mount: MountedRender) -> CGFloat { mount.host.fittingSize.height }
}
