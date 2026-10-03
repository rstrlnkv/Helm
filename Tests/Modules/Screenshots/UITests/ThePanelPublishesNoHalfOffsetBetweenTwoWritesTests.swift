import Combine
import Foundation
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The panel's offset is two keys, and the model never publishes the one without the other.** Every write announces
/// itself, and a model that reloaded on each announcement would hold, between the two writes of one move, an `x` from the
/// new place and a `y` from the old (or, for «Put the Panel Back», a zero `x` over the old `y`): a place that never was.
/// The check listens to everything the model publishes while it writes, and to what the store announced meanwhile, so a
/// run with no announcement cannot pass for a model that kept quiet.
@MainActor
final class ThePanelPublishesNoHalfOffsetBetweenTwoWritesTests: XCTestCase {
    private var listeners: [AnyCancellable] = []
    override func tearDown() { listeners = []; super.tearDown() }

    private func standing(at offset: PanelOffset) -> (CapturePanelModel, NamespacedStore) {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        offset.write(to: store)
        return (CapturePanelModel(store: store), store)
    }

    /// Every offset the model publishes from now, and how many times the store announced a change meanwhile.
    private func listen(_ model: CapturePanelModel) -> (published: () -> [PanelOffset], announced: () -> Int) {
        var seen: [PanelOffset] = []
        var announcements = 0
        listeners.append(model.$settings.dropFirst().sink { seen.append($0.panelOffset) })
        listeners.append(NotificationCenter.default.publisher(for: .helmStoreChanged).sink { _ in announcements += 1 })
        return ({ seen }, { announcements })
    }

    func testAMoveWrittenOnCloseIsNeverPublishedHalfWay() {
        let before = PanelOffset(dx: 30, dy: 40), after = PanelOffset(dx: 100, dy: 200)
        let (model, store) = standing(at: before)
        XCTAssertEqual(model.settings.panelOffset, before)
        let heard = listen(model)
        model.remember(place: after)
        XCTAssertGreaterThanOrEqual(heard.announced(), 2, "the two writes were not announced: the check watched nothing")
        XCTAssertEqual(PanelOffset.read(store), after)
        XCTAssertEqual(model.settings.panelOffset, after, "the model did not read the move once the last key was written")
        for offset in heard.published() {
            XCTAssertTrue(offset == before || offset == after, "the model published \(offset), a place that was never stored")
        }
    }

    func testPuttingThePanelBackIsNeverPublishedHalfWay() {
        let before = PanelOffset(dx: 30, dy: 40)
        let (model, store) = standing(at: before)
        let heard = listen(model)
        model.putBack()
        XCTAssertGreaterThanOrEqual(heard.announced(), 2)
        XCTAssertEqual(PanelOffset.read(store), .zero)
        XCTAssertEqual(model.settings.panelOffset, .zero)
        for offset in heard.published() {
            XCTAssertTrue(offset == before || offset == .zero, "the model published \(offset) while the move was being forgotten")
        }
    }

    /// The flag clears however the group ends: a write after the group is heard again.
    func testAWriteAfterTheGroupIsHeardAgain() {
        let (model, store) = standing(at: PanelOffset(dx: 30, dy: 40))
        model.putBack()
        store.set(Double(7), for: ScreenshotsSettings.Key.panelOffsetX)
        store.set(Double(9), for: ScreenshotsSettings.Key.panelOffsetY)
        XCTAssertEqual(model.settings.panelOffset, PanelOffset(dx: 7, dy: 9), "the model stayed deaf after a group of writes")
    }
}
