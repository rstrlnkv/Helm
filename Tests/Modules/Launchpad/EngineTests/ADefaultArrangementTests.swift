import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// What a person sees with no arrangement of their own: Apple's apps in Apple's order, a folder of utilities, a page
/// break, then everything else A–Z. Optional by the house table (logic that costs no data); the stored layout
/// that must survive it is `AStoredArrangementIsNeverRearrangedByTheDefaultTests`.
final class ADefaultArrangementTests: XCTestCase {

    static func app(_ id: String, _ path: String? = nil) -> CatalogApp {
        CatalogApp(id: id, name: id, path: path ?? "/Applications/\(id).app")
    }

    private func engine(_ apps: [CatalogApp], dir: String, name: String = "Utilities") -> (LaunchpadEngine, FakeAppCatalog, LayoutStore) {
        let catalog = FakeAppCatalog()
        catalog.reading = CatalogReading(apps: apps, complete: true)
        let store = LayoutStore(directory: scratchDirectory(dir))
        return (LaunchpadEngine(catalog: catalog, launcher: FakeAppLauncher(), store: store, utilitiesFolderName: { name }), catalog, store)
    }

    private func folderApps(_ items: [LaunchpadLayout.Item]) -> [(String, [String])] {
        items.compactMap { if case .folder(let f) = $0 { (f.name, f.apps) } else { nil } }
    }

    func testAppleAppsStandInAppleOrderThenTheFolderThenAPageBreakThenTheRestAToZ() {
        // The catalog is in name order: the Mail before the Safari, Zed before nothing.
        let apps = [Self.app("com.example.alpha"), Self.app("com.apple.mail"), Self.app("com.apple.Safari"),
                    Self.app("com.apple.Terminal", "/System/Applications/Utilities/Terminal.app"),
                    Self.app("com.apple.Automator"), Self.app("com.example.zed")]
        let (engine, _, _) = engine(apps, dir: "default-order", name: "Dienstprogramme")
        let items = engine.read(reason: .refresh).layout.items
        guard case .folder(let folder) = items[2] else { return XCTFail("the folder follows the Apple apps: \(items)") }
        XCTAssertEqual(items[0...1], [.app("com.apple.Safari"), .app("com.apple.mail")][...], "the Dock's order, not the catalog's")
        XCTAssertEqual(folder.name, "Dienstprogramme", "the name that was passed in")
        XCTAssertEqual(folder.apps, ["com.apple.Terminal", "com.apple.Automator"], "catalog order inside")
        XCTAssertEqual(Array(items[3...]), [.pageBreak, .app("com.example.alpha"), .app("com.example.zed")])
    }

    func testAUtilityIsToldByItsIdOrByItsPathAndNothingElseUnderApplicationsIsOne() {
        let apps = [Self.app("com.apple.Automator"),
                    Self.app("com.apple.FutureUtility", "/System/Applications/Utilities/Future.app"),
                    Self.app("com.example.tool", "/Applications/Utilities/Tool.app"),
                    Self.app("com.example.other")]
        let (engine, _, _) = engine(apps, dir: "default-utilities")
        let items = engine.read(reason: .refresh).layout.items
        XCTAssertEqual(folderApps(items).map(\.1), [["com.apple.Automator", "com.apple.FutureUtility"]])
        XCTAssertEqual(Array(items.suffix(3)), [.pageBreak, .app("com.example.tool"), .app("com.example.other")])
    }

    func testAListedAppThatIsNotInstalledIsSkippedAndALoneUtilityIsNotAFolder() {
        let (engine, _, _) = engine([Self.app("com.apple.Terminal"), Self.app("com.apple.Maps"), Self.app("com.example.a")], dir: "default-skips")
        XCTAssertEqual(engine.read(reason: .refresh).layout.items, [.app("com.apple.Maps"), .app("com.apple.Terminal"), .pageBreak, .app("com.example.a")],
                       "the one utility dissolves into its app, where the folder would have stood")
    }

    func testAResetGoesBackToTheDefaultAndKeepsTheHidden() throws {
        let apps = [Self.app("com.apple.mail"), Self.app("com.apple.Safari"), Self.app("com.apple.Terminal"), Self.app("com.apple.Automator"), Self.app("com.example.a")]
        let (engine, _, store) = engine(apps, dir: "default-reset")
        XCTAssertNotNil(engine.hide("com.apple.mail"))
        XCTAssertNotNil(engine.apply(.move("com.example.a", toIndex: 0)))
        let snap = try XCTUnwrap(engine.resetArrangement())
        XCTAssertEqual(snap.layout.hidden, ["com.apple.mail"])
        XCTAssertEqual(snap.layout.items.first, .app("com.apple.Safari"))
        XCTAssertEqual(folderApps(snap.layout.items).map(\.1), [["com.apple.Terminal", "com.apple.Automator"]])
        XCTAssertEqual(snap.layout.items.last, .app("com.example.a"))
        XCTAssertEqual(store.load(), .loaded(snap.layout))
    }

    func testTheFirstEditStartsFromTheDefaultThePersonSaw() throws {
        let apps = [Self.app("com.apple.mail"), Self.app("com.apple.Safari"), Self.app("com.example.a")]
        let (engine, _, _) = engine(apps, dir: "default-first-edit")
        let seen = engine.read(reason: .refresh).layout
        let snap = try XCTUnwrap(engine.hide("com.example.a"))
        XCTAssertEqual(snap.layout.items, [.app("com.apple.Safari"), .app("com.apple.mail")], "what they saw, less the app they hid")
        XCTAssertEqual(seen.items.count, 4)
    }

    func testTwoBuildsOfTheDefaultGiveTheFolderTheSameIdAndSiriAIFollowsSiri() {
        let apps = [Self.app("com.apple.Terminal"), Self.app("com.apple.Automator"), Self.app("com.apple.campo"), Self.app("com.apple.siri.launcher"),
                    Self.app("com.apple.Maps")]
        let first = LaunchpadLayout.defaultArrangement(for: apps, utilitiesFolderName: "U")
        let second = LaunchpadLayout.defaultArrangement(for: apps, utilitiesFolderName: "U")
        XCTAssertEqual(first, second, "an open folder in the window survives a refresh")
        XCTAssertEqual(Array(first.items.prefix(3)), [.app("com.apple.Maps"), .app("com.apple.siri.launcher"), .app("com.apple.campo")])
    }
}
