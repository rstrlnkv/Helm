import XCTest
import HelmRuntime
@testable import HelmApp
@testable import HelmUI

@MainActor
final class PanelLayoutStoreTests: XCTestCase {

    /// In memory, always. Writing a test arrangement into the real domain
    /// rearranges the panel of whoever runs it.
    private func store() -> NamespacedStore {
        NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
    }

    /// **The key is not `panelLayout`.** That one is in
    /// `ObsoleteDefaults.retired` — a grid the app had once and rolled back —
    /// so a layout stored under it would be deleted at the next launch and the
    /// panel would forget its arrangement every morning. Nothing about that
    /// failure looks like a bug while you are looking at it.
    func testTheKeyIsNotOneThatGetsPurgedAtLaunch() {
        let namespaced = "module.app." + PanelLayoutStore.key
        XCTAssertFalse(ObsoleteDefaults.retired.contains(namespaced),
                       "\(namespaced) is purged at every launch")
    }

    /// The control for it: the check is real, and the retired list is not empty
    /// or unreachable.
    func testTheRetiredListIsTheOneThatWouldHaveCaughtIt() {
        XCTAssertTrue(ObsoleteDefaults.retired.contains("module.app.panelLayout"),
                      "the old key is no longer purged, so this guard measures nothing")
    }

    func testAFreshStoreSeedsTodaysPanel() {
        let layout = PanelLayoutStore.read(from: store(), offered: ["vpn", "disk"])
        XCTAssertEqual(layout.allSlots.map(\.widget), ["vpn", "disk"])
        XCTAssertEqual(Set(layout.allSlots.map(\.size)), [.wide])
    }

    func testWhatIsWrittenIsWhatIsRead() {
        let s = store()
        let written = PanelLayout(tabs: [.init(id: "t", widgets: [
            .init(widget: "vpn", size: .compact), .init(widget: "disk", size: .tall),
        ])])
        PanelLayoutStore.write(written, to: s)
        let read = PanelLayoutStore.read(from: s, offered: ["vpn", "disk"])
        XCTAssertEqual(read.allSlots.map(\.size), [.compact, .tall])
    }

    /// A module that arrived with this update joins the panel the first time it
    /// is opened, without anything being rearranged first.
    func testAModuleThatArrivedWithThisBuildJoins() {
        let s = store()
        PanelLayoutStore.write(PanelLayout(tabs: [.init(id: "t", widgets: [
            .init(widget: "vpn", size: .compact),
        ])]), to: s)
        let read = PanelLayoutStore.read(from: s, offered: ["vpn", "homebrew"])
        XCTAssertEqual(read.allSlots.map(\.widget), ["vpn", "homebrew"])
    }

    /// Bytes that are not a layout at all — a half-written save, or a key that
    /// used to mean something else — read as the seed rather than as nothing.
    func testRubbishInTheStoreReadsAsTheSeed() {
        let s = store()
        s.set(Data("not a layout".utf8), for: PanelLayoutStore.key)
        XCTAssertEqual(PanelLayoutStore.read(from: s, offered: ["vpn"]).allSlots.map(\.widget),
                       ["vpn"])
    }

    /// End to end, which is how this was reported: take a widget off, quit,
    /// come back — and it is still off. The store is where the two halves meet,
    /// so it is where the regression is pinned as well as in the model.
    func testAWidgetTakenOffIsStillOffAfterARestart() {
        let s = store()
        let offered = ["vpn", "disk", "keep-awake"]
        let first = PanelLayoutStore.read(from: s, offered: offered)
        PanelLayoutStore.write(first.removing("disk"), to: s)

        // A second launch: same store, same modules, nothing else happened.
        let second = PanelLayoutStore.read(from: s, offered: offered)
        XCTAssertEqual(second.allSlots.map(\.widget), ["vpn", "keep-awake"])
    }
}
