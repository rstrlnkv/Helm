import Foundation
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Choosing Desktop, Documents, Clipboard or macOS in the bar stores that target.** Only «Other…» asks for a folder.
@MainActor
final class TheBarStoresTheTargetItIsGivenTests: XCTestCase {
    func testChoosingATargetInTheBarStoresIt() {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let model = CapturePanelModel(store: store)
        for target in [SaveTarget.desktop, .documents, .clipboard, .macOS] {
            model.choose(target)
            XCTAssertEqual(ScreenshotsSettings.read(store).saveTarget, target)
            XCTAssertEqual(model.settings.saveTarget, target)
        }
    }
}

/// **«Other…» writes its folder and its target together, from the bar and from the settings page.**
@MainActor
final class TheOtherFolderIsWrittenWithItsTargetTests: XCTestCase {
    private func newStore() -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
    }

    func testTheBarWritesAChosenFolderAndTheTarget() {
        let store = newStore()
        CapturePanelModel(store: store).choose(.other, ask: { .chosen("/tmp/shots") })
        let settings = ScreenshotsSettings.read(store)
        XCTAssertEqual(settings.saveTarget, .other)
        XCTAssertEqual(settings.otherFolder, "/tmp/shots")
    }

    func testTheBarWritesNothingForACancelledOrRefusedFolder() {
        for answer in [ScreenshotsSettingsPage.FolderChoice.cancelled, .refused] {
            let store = newStore()
            CapturePanelModel(store: store).choose(.other, ask: { answer })
            XCTAssertNotEqual(ScreenshotsSettings.read(store).saveTarget, .other)
        }
    }

    func testThePageWritesAChosenFolderAndTheTarget() {
        let store = newStore()
        _ = ScreenshotsSettingsPage.storeTarget(.other, in: store, ask: { .chosen("/tmp/shots") })
        let settings = ScreenshotsSettings.read(store)
        XCTAssertEqual(settings.saveTarget, .other)
        XCTAssertEqual(settings.otherFolder, "/tmp/shots")
    }

    func testThePageWritesNothingForACancelledOrRefusedFolder() {
        for answer in [ScreenshotsSettingsPage.FolderChoice.cancelled, .refused] {
            let store = newStore()
            _ = ScreenshotsSettingsPage.storeTarget(.other, in: store, ask: { answer })
            XCTAssertNotEqual(ScreenshotsSettings.read(store).saveTarget, .other)
        }
    }

    func testThePageStoresAPlainTargetWithoutAsking() {
        let store = newStore()
        _ = ScreenshotsSettingsPage.storeTarget(.documents, in: store, ask: { XCTFail("asked"); return .cancelled })
        XCTAssertEqual(ScreenshotsSettings.read(store).saveTarget, .documents)
    }
}
