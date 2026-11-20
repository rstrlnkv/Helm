import Combine
import Foundation
import HelmRuntime
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A window's state over the real engine on a fake catalog and a scratch layout, with the pointer fed by hand and time by the
/// test. Nothing is launched: `onLaunch` records, `onPlace` writes through the engine and records the edit.
@MainActor final class LiftRig {
    let state: LaunchpadScreenState
    let engine: LaunchpadEngine
    let catalog: RigCatalog
    /// The layout's file, for a test that asks whether anything wrote it.
    let layoutFile: URL
    let g: LaunchpadGeometry
    private(set) var placed: [LaunchpadEdit] = []
    private(set) var renamed: [String] = []
    private(set) var launched: [String] = []
    private(set) var closes = 0
    private(set) var changes = 0
    private var bag: [AnyCancellable] = []

    init(_ test: XCTestCase, apps: [String], layout: LaunchpadLayout? = nil, screen: CGSize = CGSize(width: 1280, height: 800)) {
        let store = LayoutStore(directory: test.scratchDirectory("lift"))
        if let layout { XCTAssertTrue(store.save(layout)) }
        layoutFile = store.fileURL
        catalog = RigCatalog(apps)
        engine = LaunchpadEngine(catalog: catalog, launcher: RigLauncher(), store: store)
        g = .make(for: screen, topSafe: 0)
        state = LaunchpadScreenState(geometry: g)
        state.setShown(true)
        state.update(snapshot: engine.read())
        state.buttonDown = { true }
        state.onLaunch = { [unowned self] id, _ in launched.append(id) }
        state.onClose = { [unowned self] in closes += 1 }
        state.onRename = { [unowned self] id, name in
            renamed.append(name)
            if let landed = engine.apply(.rename(id, to: name)) { state.update(snapshot: landed) }
        }
        state.onPlace = { [unowned self] edit in
            placed.append(edit)
            return engine.apply(edit)
        }
    }

    /// The catalog with these apps' categories, read again.
    func categorize(_ categories: [String: String]) {
        catalog.reading = CatalogReading(apps: catalog.reading.apps.map {
            CatalogApp(id: $0.id, name: $0.name, path: $0.path, category: categories[$0.id])
        }, complete: true)
        state.update(snapshot: engine.read())
    }

    /// Counts what the state publishes from here on.
    func countChanges() { bag.append(state.objectWillChange.sink { [unowned self] _ in changes += 1 }) }

    /// The middle of the tile's icon, margin: toward the cell's side. Page 0.
    func core(_ slot: Int) -> CGPoint { g.center(ofSlot: slot) }
    func margin(_ slot: Int) -> CGPoint { let c = g.center(ofSlot: slot); return CGPoint(x: c.x + g.cellWidth * 0.42, y: c.y) }

    func ids(_ page: Int = 0) -> [String] { state.pages[page].map(\.id) }

    /// Press on a tile and go well past the threshold, at `time`.
    func lift(_ slot: Int, at time: TimeInterval = 0) {
        let from = core(slot)
        XCTAssertTrue(state.pointerDown(from, time: time))
        state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: time + 0.01)
    }
}
