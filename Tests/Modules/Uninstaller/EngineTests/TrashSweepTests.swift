import XCTest
import HelmRuntime
@testable import Module_Uninstaller_Engine

/// The sweep that turns "an app is in the Trash" into "here is what it left".
///
/// One engine call rather than several: the host reaches it only through the
/// module's model (`UninstallerViewModel`), since `HelmApp` depends on no module's engine target (`Package.swift`, target `HelmApp`). The host triggers and draws; everything judged happens here.
final class TrashSweepTests: XCTestCase {

    /// A lister that reports what is installed and what is in the Trash
    /// independently, which is the only combination that matters: an app can be in
    /// both at once, and that is the case where offering would be wrong.
    private struct Lister: AppLister {
        var installed: [InstalledApp] = []
        /// Optional, the way the port is: `nil` is a Trash this process was not
        /// allowed to read, which is a different fact from an empty one and has its
        /// own tests in `TheOfferSwitchSaysWhatItIsDoingTests`. A non-optional here
        /// would satisfy nothing and hand every test in this file the protocol's
        /// default of `[]` — with no error anywhere.
        var trashed: [TrashedApp]? = []
        func installedApps() -> [InstalledApp] { installed }
        func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
        func installedBundleIDs() -> Set<String> { Set(installed.map(\.bundleID)) }
        func isKnownToSystem(bundleID: String) -> Bool { false }
        func trashedApps() -> [TrashedApp]? { trashed }
    }

    /// Reports every candidate path as present and non-empty, so the leftover scan
    /// finds something for any bundle id. What the scan itself decides is
    /// `LeftoverMatcher`'s business and has its own tests; this file is about which
    /// apps reach it.
    private struct Everything: FileSystemPort {
        func exists(_ url: URL) -> Bool { true }
        func size(_ url: URL) -> Int { 4096 }
        func glob(_ pattern: URL) -> [URL] { [] }
        func children(of url: URL) -> [URL] { [] }
    }

    private let home = URL(fileURLWithPath: "/Users/ann")

    /// `watching: true` unless a test says otherwise, because the offer is off
    /// until somebody turns it on and every test below is about what happens once
    /// they have. The one that checks the switch itself passes `false`.
    private func engine(_ lister: Lister,
                        store: NamespacedStore? = nil,
                        watching: Bool = true) -> UninstallerEngine {
        let store = store ?? NamespacedStore(namespace: "uninstaller",
                                             backing: InMemoryKeyValueStore())
        store.set(watching, for: "watchTrash")
        return UninstallerEngine(home: home, apps: lister, fs: Everything(),
                                 trash: NoTrash(), running: NoRunning(),
                                 store: store)
    }

    private func trashed(_ id: String, _ name: String) -> TrashedApp {
        TrashedApp(bundleID: id, name: name, path: "/Users/ann/.Trash/\(name).app")
    }

    private func installed(_ id: String, at path: String) -> InstalledApp {
        InstalledApp(name: "Whatever", bundleID: id, path: path, sizeBytes: 0)
    }

    // MARK: - What is offered

    func testAnAppInTheTrashWithLeftoversIsOffered() async {
        let uninstaller = engine(Lister(trashed: [trashed("com.example.gone", "Gone")]))

        let groups = await uninstaller.trashedAppLeftovers()

        XCTAssertEqual(groups.map(\.bundleID), ["com.example.gone"])
        XCTAssertEqual(groups.first?.name, "Gone")
        XCTAssertEqual(groups.first?.appPath, "/Users/ann/.Trash/Gone.app")
        XCTAssertFalse(groups.first?.leftovers.isEmpty ?? true)
    }

    /// The order the Trash listed is the order the window draws its groups in, so
    /// the sweep must not sort.
    func testTheOrderFoundIsKept() async {
        let uninstaller = engine(Lister(trashed: [trashed("com.c", "C"), trashed("com.a", "A"),
                                        trashed("com.b", "B")]))

        let groups = await uninstaller.trashedAppLeftovers()

        XCTAssertEqual(groups.map(\.bundleID), ["com.c", "com.a", "com.b"])
    }

    // MARK: - The refusal that matters most

    /// Two copies of one app share a bundle id. Dragging one to the Trash leaves the
    /// other installed and its support files in use — offering to delete them then
    /// is not cleaning up after an uninstall, it is breaking an app the person still
    /// runs.
    func testAnAppStillInstalledElsewhereIsNotOffered() async {
        let uninstaller = engine(Lister(installed: [installed("com.example.two", at: "/Applications/Two.app")],
                              trashed: [trashed("com.example.two", "Two")]))

        let groups = await uninstaller.trashedAppLeftovers()

        XCTAssertTrue(groups.isEmpty,
                      "offered to delete the support files of an installed app: "
                      + "\(groups.flatMap { $0.leftovers.map(\.path) })")
    }

    /// The control for the test above: the same bundle id, nothing installed, and it
    /// *is* offered — so the refusal is the installed copy and not the fixture.
    func testTheSameAppWithNothingInstalledIsOffered() async {
        let uninstaller = engine(Lister(trashed: [trashed("com.example.two", "Two")]))
        let groups = await uninstaller.trashedAppLeftovers()
        XCTAssertEqual(groups.count, 1)
    }

    /// An app that left nothing behind is not worth a window. Reported as empty
    /// rather than as a group with no rows, which the host would have to special-case.
    func testAnAppWithNoLeftoversIsNotAGroup() async {
        struct Nothing: FileSystemPort {
            func exists(_ url: URL) -> Bool { false }
            func size(_ url: URL) -> Int { 0 }
            func glob(_ pattern: URL) -> [URL] { [] }
            func children(of url: URL) -> [URL] { [] }
        }
        let uninstaller = UninstallerEngine(home: home,
                                  apps: Lister(trashed: [trashed("com.example.clean", "Clean")]),
                                  fs: Nothing(), trash: NoTrash(), running: NoRunning())

        let groups = await uninstaller.trashedAppLeftovers()
        XCTAssertTrue(groups.isEmpty)
    }

    func testAnEmptyTrashOffersNothing() async {
        let groups = await engine(Lister()).trashedAppLeftovers()
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - No, remembered

    func testADismissedAppIsNotOfferedAgain() async {
        let lister = Lister(trashed: [trashed("com.a", "A"), trashed("com.b", "B")])
        let uninstaller = engine(lister)
        let both = await uninstaller.trashedAppLeftovers()
        XCTAssertEqual(both.count, 2, "precondition")

        uninstaller.dismissTrashedApp(bundleID: "com.a")

        let rest = await uninstaller.trashedAppLeftovers()
        XCTAssertEqual(rest.map(\.bundleID), ["com.b"])
    }

    /// The record is in the store the host hands the module, so it outlives the
    /// process — which is the whole point of remembering a no.
    func testTheNoSurvivesANewEngineOverTheSameStore() async {
        let backing = InMemoryKeyValueStore()
        let store = { NamespacedStore(namespace: "uninstaller", backing: backing) }
        let lister = Lister(trashed: [trashed("com.a", "A")])

        engine(lister, store: store()).dismissTrashedApp(bundleID: "com.a")

        let after = await engine(lister, store: store()).trashedAppLeftovers()
        XCTAssertTrue(after.isEmpty,
                      "the window will reappear for an app already declined")
    }

    /// A record in the current format is a plain `[String]` under the
    /// `trashOfferDismissed` key: it must still silence the offer, and the prune must keep it a
    /// `[String]` while the app is still in the Trash.
    func testARecordInTheCurrentFormatStillSilencesTheOffer() async {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "uninstaller", backing: backing)
        store.set(["com.acme.tool"], for: "trashOfferDismissed")
        let lister = Lister(trashed: [trashed("com.acme.tool", "Tool")])

        let offered = await engine(lister, store: store).trashedAppLeftovers()

        XCTAssertTrue(offered.isEmpty, "an app already declined, in the current format, was offered again")
        XCTAssertEqual(store.stringArray("trashOfferDismissed"), ["com.acme.tool"],
                       "the pruned record no longer reads as the [String] it was")
    }

    /// A store that holds the sweep between its read of the dismissed set and its
    /// write, so a cancel can arrive in the gap: the lost update is then certain
    /// rather than a matter of timing.
    private final class HoldingStore: KeyValueStore, @unchecked Sendable {
        let inner = InMemoryKeyValueStore()
        let firstRead = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var reads = 0
        func object(forKey k: String) -> Any? {
            let value = inner.object(forKey: k)
            guard k.hasSuffix("trashOfferDismissed") else { return value }
            let first = lock.withLock { reads += 1; return reads == 1 }
            if first {
                firstRead.signal()
                Thread.sleep(forTimeInterval: 0.3)
            }
            return value
        }
        func set(_ v: Any?, forKey k: String) { inner.set(v, forKey: k) }
    }

    /// The sweep's prune and a cancel each read the dismissed set, change it and
    /// write it back; run together, one wrote over the other's change.
    func testACancelDuringTheSweepIsNotLostToItsPrune() {
        let backing = HoldingStore()
        let store = NamespacedStore(namespace: "uninstaller", backing: backing)
        // "com.gone" left the Trash, so the prune drops it; "com.kept" stays.
        store.set(["com.gone", "com.kept"], for: "trashOfferDismissed")
        let uninstaller = engine(Lister(trashed: [trashed("com.kept", "Kept")]), store: store)

        let swept = expectation(description: "the sweep finished")
        Task {
            _ = await uninstaller.trashedAppLeftovers()
            swept.fulfill()
        }
        XCTAssertEqual(backing.firstRead.wait(timeout: .now() + 5), .success,
                       "the sweep never read the dismissed set under its key")
        uninstaller.dismissTrashedApp(bundleID: "com.new")
        wait(for: [swept], timeout: 10)

        XCTAssertEqual(Set(store.stringArray("trashOfferDismissed")), ["com.kept", "com.new"],
                       "the prune wrote over a cancel made while it ran")
    }

    /// And it stops meaning anything once the app leaves the Trash: restored or
    /// finally deleted, a later removal is a question nobody has answered.
    func testTheNoIsForgottenWhenTheAppLeavesTheTrash() async {
        let backing = InMemoryKeyValueStore()
        let store = { NamespacedStore(namespace: "uninstaller", backing: backing) }
        let one = trashed("com.a", "A")

        let first = engine(Lister(trashed: [one]), store: store())
        first.dismissTrashedApp(bundleID: "com.a")
        let afterNo = await first.trashedAppLeftovers()
        XCTAssertTrue(afterNo.isEmpty, "precondition: declined")

        // The person put it back, and the sweep sees an empty Trash.
        _ = await engine(Lister(trashed: []), store: store()).trashedAppLeftovers()

        // Dragged there a second time.
        let again = await engine(Lister(trashed: [one]), store: store()).trashedAppLeftovers()
        XCTAssertEqual(again.count, 1,
                       "a second removal of the same app was never asked about")
    }

    // MARK: - The switch

    /// Off is the default, and off means the engine has nothing to say — not that
    /// the host is expected to keep quiet about an answer it was given. A window
    /// that opens unasked has to be something somebody asked for, and the module
    /// is where that is decided, the same way it decides everything else here.
    func testNothingIsOfferedWhileTheOfferIsOff() async {
        let lister = Lister(trashed: [trashed("com.a", "A")])
        let groups = await engine(lister, watching: false).trashedAppLeftovers()
        XCTAssertTrue(groups.isEmpty, "the offer answered while it was switched off")
    }

    /// And the same Trash, with the switch on, is an offer — so the test above is
    /// about the switch and not about a Trash that had nothing in it.
    func testTheSameTrashIsOfferedWhenItIsOn() async {
        let lister = Lister(trashed: [trashed("com.a", "A")])
        let groups = await engine(lister, watching: true).trashedAppLeftovers()
        XCTAssertEqual(groups.count, 1)
    }
}
