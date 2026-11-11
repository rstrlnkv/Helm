import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **A module owns its model: the host builds it through the module, hands the page, the scan and the
/// teardown that same object, and stops it before the engine goes.**
///
/// Driven on the shared host (the way `AStandInEngineCannotBeSwitchedOffTests` does) with a local
/// descriptor that has its own model type, `makeModule`, `stop` and its own scan. It is not
/// reached by a cast anywhere in this file; a cast needed to make it live is the defect.
///
/// Every reference the fakes keep to a model is weak, so "the model goes with its module" is read
/// off the object, not off the fakes' own bookkeeping.
@MainActor
final class AModuleOwnsItsModelTests: XCTestCase {

    private static let convertedID = "test-owns-model-converted"
    private static let standInID = "test-owns-model-stand-in"
    private static let allIDs = [convertedID, standInID]

    nonisolated static let report = ScanReport(bytes: 4242, count: 2,
                                           items: [ScanItem(path: "/x/a", bytes: 4000),
                                                   ScanItem(path: "/x/b", bytes: 242)])

    /// What the fakes did, in order.
    private final class Journal {
        var calls: [String] = []
    }

    private final class FakeEngine: ModuleEngine {
        let journal: Journal
        let standsIn: Bool
        init(journal: Journal, standsIn: Bool = false) {
            self.journal = journal
            self.standsIn = standsIn
        }
        func activate() {}
        func willDisable() { journal.calls.append("willDisable") }
        func deactivate() { journal.calls.append("deactivate") }
    }

    /// The module's own model type.
    private final class OwnModel {}

    private class Base {
        static let category: ModuleCategory = .utilities
        static let tint = ModuleTint(ordinary: ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)),
                                     increasedContrast: ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)))
        static let glyph = ShellGlyph.settings
        let journal = Journal()
    }

    private final class Converted: Base, ModuleDescriptor {
        static let id = ModuleID(AModuleOwnsItsModelTests.convertedID)
        static let metadata = ModuleMetadata(id: id, name: "Converted", summary: "",
                                             sfSymbol: "gear", permissions: [])
        let standsIn: Bool
        init(standsIn: Bool = false) { self.standsIn = standsIn }

        private(set) weak var built: OwnModel?
        private(set) weak var pageModel: OwnModel?
        private(set) weak var stopped: OwnModel?
        private(set) weak var scanned: OwnModel?
        private(set) var makeModuleCalls = 0
        private(set) var builtEngine: FakeEngine?

        func makeModule(store: NamespacedStore) -> ModuleParts<OwnModel> {
            makeModuleCalls += 1
            let model = OwnModel()
            built = model
            let engine = FakeEngine(journal: journal, standsIn: standsIn)
            builtEngine = engine
            return ModuleParts(engine: engine, model: model)
        }
        func menuBar(_ model: OwnModel) -> MenuBarContribution? { nil }
        func settingsPage(_ model: OwnModel) -> AnyView {
            pageModel = model
            return AnyView(EmptyView())
        }
        func stop(_ model: OwnModel) {
            journal.calls.append("stop")
            stopped = model
        }
        func backgroundScan(_ parts: ModuleParts<OwnModel>) async -> ScanReport? {
            scanned = parts.model
            return AModuleOwnsItsModelTests.report
        }
    }

    /// The host's store is `UserDefaults.standard`: the keys written are taken back out.
    override func tearDown() {
        ModuleHost.shared.shutdown()
        for id in Self.allIDs {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        super.tearDown()
    }

    private func enabledKey(_ id: String) -> Any? {
        UserDefaults.standard.object(forKey: "module.\(id).enabled")
    }

    func testTheHostHoldsWhatTheModuleBuilt() throws {
        let converted = Converted()
        let host = ModuleHost.shared

        host.setEnabled(converted, true)

        let c = try XCTUnwrap(host.liveModule(Self.convertedID), "the module never came up")
        XCTAssertEqual(converted.makeModuleCalls, 1, "the host built the module's model other than once, through makeModule")
        let builtModel = try XCTUnwrap(converted.built, "makeModule was never the way the model was built")
        XCTAssertTrue(c.model === builtModel, "the host holds a model of its own, not the one the module built")
        _ = c.page()
        XCTAssertTrue(converted.pageModel === builtModel, "the page was handed another object than the one the module built")
        XCTAssertTrue(c.engine === converted.builtEngine, "the host holds an engine other than the one makeModule built")
        XCTAssertEqual(converted.journal.calls, [], "building must not have stopped or torn anything down")
    }

    func testThePersonsSwitchStopsTheModelBeforeTheEngineOnce() throws {
        let d = Converted()
        let host = ModuleHost.shared
        host.setEnabled(d, true)
        let model = try XCTUnwrap(d.built)
        XCTAssertNotNil(host.liveModule(Self.convertedID))

        host.setEnabled(d, false)
        host.setEnabled(d, false)

        XCTAssertEqual(d.journal.calls, ["willDisable", "stop", "deactivate"],
                       "the model must be stopped after the question and before the engine goes, each once")
        XCTAssertTrue(d.stopped === model, "stop got something other than the model the module built")
        XCTAssertNil(host.liveModule(Self.convertedID))
    }

    func testQuittingStopsTheModelBeforeTheEngineToo() throws {
        let d = Converted()
        let host = ModuleHost.shared
        host.setEnabled(d, true)
        let model = try XCTUnwrap(d.built)

        host.shutdown()
        host.shutdown()

        XCTAssertEqual(d.journal.calls, ["stop", "deactivate"],
                       "quitting asks no question, stops the model, then deactivates, each once")
        XCTAssertTrue(d.stopped === model)
        XCTAssertEqual(enabledKey(Self.convertedID) as? Bool, true, "quitting is not the person's off")
    }

    func testAStandInIsNeitherStoppedNorDeactivated() {
        let d = Converted(standsIn: true)
        let host = ModuleHost.shared
        host.setEnabled(d, true)
        XCTAssertNotNil(host.liveModule(Self.convertedID), "the stand-in never went live; nothing below proves anything")

        host.setEnabled(d, false)

        XCTAssertEqual(d.journal.calls, [], "a refused switch still stopped or tore down the stand-in")
        XCTAssertNotNil(host.liveModule(Self.convertedID))
        XCTAssertTrue(host.anyStandsIn)
        XCTAssertEqual(enabledKey(Self.convertedID) as? Bool, true, "the refused switch wrote \"off\"")
    }

    func testTheModelGoesWithItsModule() throws {
        let d = Converted()
        let host = ModuleHost.shared
        host.setEnabled(d, true)
        _ = try XCTUnwrap(host.liveModule(Self.convertedID)).page()
        XCTAssertNotNil(d.built, "the module's model never existed; nothing below proves anything")

        host.setEnabled(d, false)

        XCTAssertNil(d.built, "the model outlived its module: something still holds it after the switch")
    }

    func testTheScanIsAskedOfTheModule() async throws {
        let converted = Converted()
        let host = ModuleHost.shared
        host.setEnabled(converted, true)
        let c = try XCTUnwrap(host.liveModule(Self.convertedID))

        let fromConverted = await c.backgroundScan()
        XCTAssertEqual(fromConverted, Self.report, "the converted module's own scan was not what answered")
        let builtModel = try XCTUnwrap(converted.built)
        XCTAssertTrue(converted.scanned === builtModel, "the module's scan was not given its own model")
    }
}
