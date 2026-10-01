import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The Apps tab's sort at the inputs its first tests did not feed in.**
///
/// `TheAppsAreSortedAndDatedTests` proves the order on the view model and the
/// declaration of the menu. This file takes the order to the places a person
/// meets it: ticks made under one order and a review built under another (the
/// path that deletes), a search over a sorted list, the menu on the review and
/// on the failure report, a read the engine cut short, the row itself before
/// anything is measured and in every language, and the page's own
/// `.animation(value: tab)` and `.animation(value: apps.count)` under a re-sort
/// and a tab switch — timestamped frames, one per run-loop turn.
///
/// `HELM_FRAMES_DIR` names a folder for the PNGs.
@MainActor
final class TheSortedListUnderOddInputsTests: XCTestCase {

    // Alpha is the smallest and the most recently opened, Gamma the largest and
    // opened longest ago, Delta never recorded — so every order is a different
    // sequence and no assertion passes by the name order being the answer.
    private static let alpha = InstalledApp(name: "Alpha", bundleID: "com.x.alpha",
                                            path: "/Applications/Alpha.app", sizeBytes: 10_000)
    private static let beta = InstalledApp(name: "Beta", bundleID: "com.x.beta",
                                           path: "/Applications/Beta.app", sizeBytes: 500_000_000)
    private static let gamma = InstalledApp(name: "Gamma", bundleID: "com.x.gamma",
                                            path: "/Applications/Gamma.app", sizeBytes: 9_000_000_000)
    private static let delta = InstalledApp(name: "Delta", bundleID: "com.x.delta",
                                            path: "/Applications/Delta.app", sizeBytes: 70_000_000)
    private static let apps = [alpha, beta, gamma, delta]

    private static var opened: [String: Date] {
        [alpha.path: Date(timeIntervalSinceNow: -3_600),
         beta.path: Date(timeIntervalSinceNow: -86_400 * 30),
         gamma.path: Date(timeIntervalSinceNow: -86_400 * 400)]
    }

    private static func scans(_ list: [InstalledApp]) -> [String: ScanResult] {
        Dictionary(uniqueKeysWithValues: list.map {
            ($0.bundleID, ScanResult(bundleID: $0.bundleID, appPath: $0.path, appSizeBytes: $0.sizeBytes,
                                     leftovers: [], runningNow: false))
        })
    }

    private func wire(_ list: [InstalledApp] = TheSortedListUnderOddInputsTests.apps) -> UninstallerWire {
        let wire = UninstallerWire(apps: list, scans: Self.scans(list),
                                   removal: UninstallResult(trashed: [], freedBytes: 0))
        wire.setOpened(Self.opened)
        return wire
    }

    private var mounts: [MountedRender] = []
    private var previousLanguage: AppLanguage?
    override func setUp() { super.setUp(); previousLanguage = AppLanguage.override }
    override func tearDown() {
        mounts.forEach { $0.drop() }
        mounts = []
        AppLanguage.override = previousLanguage
        super.tearDown()
    }

    // MARK: - The path that deletes

    /// Ticks made under the size order, the list re-sorted twice, and the review
    /// built: it holds exactly the ticked apps, the scans asked for exactly them,
    /// and the batch sent to the Trash names exactly their bundles. The ticked
    /// pair is not the first two in the name order (the list `apps` holds) nor in
    /// the order the review is built under, so a selection that followed a
    /// position rather than an identity picks different apps.
    func testReSortingKeepsTheTicksAndTheReviewAndTheBatchAreExactlyTheTicked() async throws {
        let wire = wire()
        let uvm = UninstallerViewModel(vm: ModuleViewModel(transport: wire))
        await uvm.setSortOrder(.size)
        await uvm.loadAppsIfNeeded()
        XCTAssertEqual(uvm.sortedApps.map(\.name), ["Gamma", "Beta", "Delta", "Alpha"],
                       "precondition: the size order is not the name order")
        // The two the person sees at the top.
        for app in uvm.sortedApps.prefix(2) { uvm.toggleChecked(app.bundleID) }
        let ticked: Set<String> = [Self.gamma.bundleID, Self.beta.bundleID]
        XCTAssertEqual(uvm.checked, ticked)

        for order in [AppSortOrder.dateLastOpened, .name, .size, .name] {
            await uvm.setSortOrder(order)
            XCTAssertEqual(uvm.checked, ticked, "the ticks moved when the list was sorted by \(order)")
        }
        XCTAssertEqual(uvm.sortedApps.prefix(2).map(\.bundleID), [Self.alpha.bundleID, Self.beta.bundleID],
                       "precondition: under the name order the top two are not the ticked two")

        await uvm.prepareReview()
        XCTAssertEqual(uvm.step, .review, "the review never opened")
        XCTAssertEqual(Set(uvm.groups.map(\.app.bundleID)), ticked)
        XCTAssertEqual(uvm.groups.count, 2)
        let scanned = try wire.payloads(of: .scan).map {
            try JSONDecoder().decode(UninstallScanRequest.self, from: $0).bundleID
        }
        XCTAssertEqual(Set(scanned), ticked, "the scans asked about other apps than the ticked")

        await uvm.removeSelection()
        let batch = try JSONDecoder().decode(TrashBatchRequest.self,
                                             from: try XCTUnwrap(wire.payload(of: .trashPaths),
                                                                 "the removal was never sent"))
        XCTAssertEqual(Set(batch.paths), [Self.gamma.path, Self.beta.path])
    }

    /// The same path in the order it really happens, under every order: the
    /// list is drawn from names, the dates land, the person ticks the second and
    /// the fourth row they see, presses Review while the sizes are still being
    /// measured, and the sizes land in the middle of the review's scans — so
    /// under Size the rows change places between the ticks and the review. The
    /// review, the scans and the batch name exactly the ticked apps, each once.
    func testUnderEveryOrderWithTheSizesArrivingTheBatchIsExactlyTheTicked() async throws {
        let listed = Self.apps.map {
            InstalledApp(name: $0.name, bundleID: $0.bundleID, path: $0.path, sizeBytes: 0)
        }
        let sizes = Dictionary(uniqueKeysWithValues: Self.apps.map { ($0.path, $0.sizeBytes) })
        for order in AppSortOrder.allCases {
            let inner = wire(listed)
            let wire = ArrivingWire(inner, sizes: sizes)
            let uvm = UninstallerViewModel(vm: ModuleViewModel(transport: wire))
            await uvm.setSortOrder(order)
            let load = Task { await uvm.loadAppsIfNeeded() }
            await until("\(order): the list and the dates are in") {
                uvm.apps.count == Self.apps.count && uvm.lastOpened != nil
            }
            XCTAssertTrue(uvm.measuredSizes.isEmpty, "\(order): precondition — the sizes are still being measured")
            let shown = uvm.sortedApps
            let picked = [shown[1], shown[3]]
            for app in picked { uvm.toggleChecked(app.bundleID) }
            let ticked = Set(picked.map(\.bundleID))
            XCTAssertNotEqual(Set(uvm.apps.prefix(2).map(\.bundleID)), ticked,
                              "\(order): precondition — the ticked are not the first two by name")

            wire.holdScans()
            let review = Task { await uvm.prepareReview() }
            await until("\(order): the review asked for both scans") { wire.scansAsked == 2 }
            wire.land()
            await load.value
            XCTAssertEqual(uvm.measuredSizes.count, Self.apps.count, "\(order): precondition — the sizes landed mid-review")
            if order == .size {
                XCTAssertNotEqual(uvm.sortedApps.map(\.bundleID), shown.map(\.bundleID),
                                  "precondition: under Size the rows changed places between the ticks and the review")
            }
            XCTAssertEqual(uvm.checked, ticked, "\(order): the ticks moved when the sizes landed")
            wire.releaseScans()
            await review.value

            XCTAssertEqual(uvm.step, .review, "\(order): the review never opened")
            XCTAssertEqual(uvm.groups.map(\.app.bundleID).sorted(), ticked.sorted(),
                           "\(order): the review lists other apps than the ticked")
            let scanned = try inner.payloads(of: .scan).map {
                try JSONDecoder().decode(UninstallScanRequest.self, from: $0).bundleID
            }
            XCTAssertEqual(scanned.sorted(), ticked.sorted(), "\(order): the scans asked about other apps than the ticked")

            await uvm.removeSelection()
            let batch = try JSONDecoder().decode(TrashBatchRequest.self,
                                                 from: try XCTUnwrap(inner.payload(of: .trashPaths),
                                                                     "\(order): the removal was never sent"))
            XCTAssertEqual(batch.paths.sorted(), picked.map(\.path).sorted(),
                           "\(order): the batch sent to the Trash is not the ticked apps")
        }
    }

    /// A wait on the clock, bounded — the thing waited for happens on another
    /// task, and a yield buys a turn rather than time.
    private func until(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                       _ condition: () -> Bool) async {
        let limit = Date().addingTimeInterval(5)
        while !condition(), Date() < limit { await HelmTestSupport.grace(0.01) }
        XCTAssertTrue(condition(), "never reached: \(what)", file: file, line: line)
    }

    /// The menu on the steps where the order of the choice does not move: the
    /// review, and the failure report after a partly refused removal. Enabled
    /// on the pick step first, or «disabled» is about a menu that never was.
    func testTheMenuIsDimOnTheReviewAndOnTheFailureReport() async throws {
        let wire = wire()
        let failure = TrashFailureInfo(path: Self.gamma.path, reason: .noPermission, message: "denied")
        wire.setRemoval(UninstallResult(trashed: [], freedBytes: 0, failures: [failure]))
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        let channel = HelmWindowToolbarChannel()
        let mount = MountedRender(page(vm), width: 800, height: 600, appearance: .aqua, channel: channel)
        mounts.append(mount)
        mount.settle(30)

        func sort() throws -> HelmToolbarAction {
            let content = try XCTUnwrap(channel.content(for: UninstallerDescriptor.id.rawValue))
            return try XCTUnwrap(content.actions.first { $0.id == "sort" })
        }
        XCTAssertTrue(try sort().isEnabled, "the menu is dim on the pick step")

        uvm.toggleChecked(Self.gamma.bundleID)
        await uvm.prepareReview()
        mount.settle(20)
        XCTAssertEqual(uvm.step, .review)
        XCTAssertFalse(try sort().isEnabled, "the menu reorders nothing on the review and was offered there")

        await uvm.removeSelection()
        mount.settle(20)
        XCTAssertFalse(uvm.failures.isEmpty, "precondition: the failure report is up")
        XCTAssertEqual(uvm.step, .pick)
        XCTAssertFalse(try sort().isEnabled, "the menu was offered over the failure report")

        uvm.dismissFailures()
        mount.settle(20)
        XCTAssertTrue(try sort().isEnabled, "the menu did not come back after the report was dismissed")
    }

    // MARK: - A read cut short

    /// The engine ran out of its ceiling or its deadline before Beta and Delta:
    /// it never asked Spotlight about them, and the row draws them blank — not
    /// «no record». The order has to keep that distinction too: the head of the
    /// date order is the claim «least evidence this app is used», which Helm
    /// cannot make about an app it never asked about.
    func testAnAppTheReadNeverReachedDoesNotLeadTheDateOrder() async {
        let wire = wire()
        wire.setOpened([Self.alpha.path: Date(timeIntervalSinceNow: -60)],
                       unread: [Self.beta.path, Self.delta.path])
        let uvm = UninstallerViewModel(vm: ModuleViewModel(transport: wire))
        await uvm.setSortOrder(.dateLastOpened)
        await uvm.loadAppsIfNeeded()
        XCTAssertEqual(uvm.lastOpenedUnread, [Self.beta.path, Self.delta.path], "precondition: the read was cut short")
        XCTAssertEqual(uvm.effectiveSortOrder, .dateLastOpened)
        let order = uvm.sortedApps.map(\.name)
        // Gamma has no record (asked, nothing) and belongs at the head.
        XCTAssertEqual(order.first, "Gamma",
                       "the date order is led by \(order.first ?? "nothing") — an app Spotlight was never asked about; order \(order)")
    }

    // MARK: - A reading older than the choice

    /// The page's `.task` asks the engine for the remembered order; the person
    /// picks Size before that answer lands; the answer — read before the
    /// choice — then lands. The engine holds Size (it was told); the screen
    /// must not go back to the order read before the press.
    func testAnOrderReadBeforeAChoiceDoesNotUndoTheChoice() async {
        let inner = wire()
        inner.setOrder(.name)
        let gated = HeldOrderWire(RememberingWire(inner))
        let uvm = UninstallerViewModel(vm: ModuleViewModel(transport: gated))
        let refresh = Task { await uvm.refreshSortOrder() }
        await waitUntil("the order was asked for") { gated.asked }
        await uvm.setSortOrder(.size)
        let stored = await inner.storedOrder
        XCTAssertEqual(stored, .size, "precondition: the engine was told Size")
        gated.release()
        await refresh.value
        XCTAssertEqual(uvm.sortOrder, .size,
                       "the screen went back to \(uvm.sortOrder), read before the press, while the engine holds Size")
    }

    // MARK: - The review before the sizes land

    /// A person ticks an app and presses Review before its size has been
    /// measured (4–9 s on a real Mac). The review drew the app's size from the
    /// snapshot taken at the press, and that snapshot carries the list's zero:
    /// «0 bytes» on the heading and on the app's own row, «To the Trash — —» at
    /// the bottom, and nothing later replaced it. Nothing is drawn where a size
    /// was never measured — and when the size lands, it is drawn in each of
    /// those places, which is also what proves each band can see a figure.
    ///
    /// The bands step round the sticky heading's lower edge (about 24–30 pt): it
    /// is a hairline across the whole width, trailing columns included, and a
    /// band over it reads ink with no figure anywhere near it.
    func testTheReviewDoesNotDrawAZeroForAnAppNobodyMeasured() async throws {
        let heading = 3...22, row = 32...74
        for appearance in RenderedInk.bothAppearances {
            AppLanguage.override = .en
            // The list arrives the way `WorkspaceAppLister` sends it: names, and
            // `sizeBytes` zero until measured.
            let listed = InstalledApp(name: Self.gamma.name, bundleID: Self.gamma.bundleID,
                                      path: Self.gamma.path, sizeBytes: 0)
            let wire = SizesLandLater(wire([listed]), sizes: [Self.gamma.path: Self.gamma.sizeBytes])
            let vm = ModuleViewModel(transport: wire)
            let uvm = UninstallerViewModel.shared(vm: vm)
            await uvm.loadAppsIfNeeded()
            XCTAssertTrue(uvm.measuredSizes.isEmpty, "precondition: nothing was measured")
            uvm.toggleChecked(Self.gamma.bundleID)
            await uvm.prepareReview()
            XCTAssertEqual(uvm.step, .review, "the review never opened")
            let mount = MountedRender(page(vm), width: 800, height: 600, appearance: appearance)
            mounts.append(mount)
            mount.settle(40)
            write(mount, "review-unmeasured-\(RenderedInk.label(of: appearance))")
            let name = appearance.rawValue
            let left = try XCTUnwrap(RenderedInk.read(mount.host, points: row, columns: 0...300))
            XCTAssertGreaterThan(left, 0, "\(name): the review drew nothing at all")
            for (band, what) in [(heading, "the heading"), (row, "the app's own row")] {
                let right = try XCTUnwrap(RenderedInk.read(mount.host, points: band, columns: trailing(mount)))
                XCTAssertEqual(right, 0,
                               "\(name): \(what) drew \(right) ink where the size goes, for an app nobody measured")
            }
            // The total beside the button. Light only: the bottom bar's material
            // does not composite in an offscreen render and reads as a white
            // strip in the dark one.
            let footer = 560...594, total = 480...665
            if appearance == .aqua {
                let beside = try XCTUnwrap(RenderedInk.read(mount.host, points: footer, columns: total))
                XCTAssertEqual(beside, 0, "\(name): the bottom line drew \(beside) ink — a total nobody measured")
            }

            // The size lands while the review is up.
            wire.land()
            await uvm.reloadApps()
            XCTAssertEqual(uvm.measuredSizes[Self.gamma.path], Self.gamma.sizeBytes, "precondition: the size landed")
            XCTAssertEqual(uvm.step, .review, "precondition: the review is still up")
            mount.settle(40)
            write(mount, "review-measured-\(RenderedInk.label(of: appearance))")
            for (band, what) in [(heading, "the heading"), (row, "the app's own row")] {
                let right = try XCTUnwrap(RenderedInk.read(mount.host, points: band, columns: trailing(mount)))
                XCTAssertGreaterThan(right, 0, "\(name): \(what) drew no size after it landed")
            }
            if appearance == .aqua {
                let beside = try XCTUnwrap(RenderedInk.read(mount.host, points: footer, columns: total))
                XCTAssertGreaterThan(beside, 0, "\(name): the bottom line drew no total after the size landed")
            }
        }
    }

    // MARK: - Search over a sorted list

    /// The search narrows the sorted list and does not put it back in name
    /// order: «l» matches Alpha and Delta; under Size Delta (70 MB) is above
    /// Alpha (10 KB), under Name it is below. Read from the drawing — the first
    /// row of the searched page is the same pixels as the only row of a page
    /// listing Delta, and not those of a page listing Alpha.
    func testASearchNarrowsTheSortedListWithoutReorderingIt() async throws {
        func mountSorted(_ list: [InstalledApp], search: String?) async throws -> (MountedRender, NSTableView) {
            let wire = wire(list)
            wire.setOrder(.size)
            let vm = ModuleViewModel(transport: wire)
            let uvm = UninstallerViewModel.shared(vm: vm)
            await uvm.setSortOrder(.size)
            await uvm.loadAppsIfNeeded()
            let channel = HelmWindowToolbarChannel()
            let mount = MountedRender(page(vm), width: 800, height: 600, appearance: .aqua, channel: channel)
            mounts.append(mount)
            mount.settle(30)
            if let search {
                let content = try XCTUnwrap(channel.content(for: UninstallerDescriptor.id.rawValue))
                try XCTUnwrap(content.search).text.wrappedValue = search
                mount.settle(30)
            }
            let table = try XCTUnwrap(mount.host.everyView(ofType: NSTableView.self).first, "no list drawn")
            return (mount, table)
        }
        AppLanguage.override = .en
        let (narrowed, narrowedTable) = try await mountSorted(Self.apps, search: "l")
        XCTAssertEqual(narrowedTable.numberOfRows, 2, "«l» should leave Alpha and Delta")
        let (delta, _) = try await mountSorted([Self.delta], search: nil)
        let (alpha, _) = try await mountSorted([Self.alpha], search: nil)
        let row = try XCTUnwrap(band(of: 0, in: narrowedTable, host: narrowed.host))
        let first = try XCTUnwrap(narrowed.pixels(row))
        let d = try XCTUnwrap(delta.pixels(row))
        let a = try XCTUnwrap(alpha.pixels(row))
        XCTAssertNotEqual(d, a, "precondition: Delta's row and Alpha's row draw differently")
        XCTAssertEqual(first, d, "the searched list's first row is not Delta — the search reordered the sorted list")
    }

    // MARK: - The row

    /// Nothing measured and the date never reached: the right-hand column of the
    /// row is empty — no «0 bytes», no «no record». Then the sizes and dates
    /// land and the same column draws, which is the control that the column is
    /// the one being read.
    func testNothingIsDrawnWhereTheSizeGoesUntilItIsMeasured() async throws {
        for appearance in RenderedInk.bothAppearances {
            let wire = wire([Self.gamma])
            wire.answers(.nothing, to: .appSizes)
            wire.setOpened([:], unread: [Self.gamma.path])
            AppLanguage.override = .en
            let vm = ModuleViewModel(transport: wire)
            let uvm = UninstallerViewModel.shared(vm: vm)
            await uvm.loadAppsIfNeeded()
            let mount = MountedRender(page(vm), width: 800, height: 600, appearance: appearance)
            mounts.append(mount)
            mount.settle(30)
            XCTAssertTrue(uvm.measuredSizes.isEmpty, "precondition: nothing was measured")
            let table = try XCTUnwrap(mount.host.everyView(ofType: NSTableView.self).first)
            let row = try XCTUnwrap(band(of: 0, in: table, host: mount.host))
            let right = trailing(mount)
            let blank = try XCTUnwrap(RenderedInk.read(mount.host, points: row, columns: right))
            let name = try XCTUnwrap(RenderedInk.read(mount.host, points: row, columns: 0...300))
            write(mount, "row-unmeasured-\(RenderedInk.label(of: appearance))")
            XCTAssertGreaterThan(name, 0, "\(appearance.rawValue): the row drew nothing at all")
            XCTAssertEqual(blank, 0, "\(appearance.rawValue): the size column drew \(blank) ink before anything was measured")

            wire.answers(.reply, to: .appSizes)
            wire.setOpened([Self.gamma.path: Date(timeIntervalSinceNow: -86_400 * 3)])
            await uvm.reloadApps()
            mount.settle(30)
            let filled = try XCTUnwrap(RenderedInk.read(mount.host, points: row, columns: right))
            write(mount, "row-measured-\(RenderedInk.label(of: appearance))")
            XCTAssertGreaterThan(filled, 0, "\(appearance.rawValue): the size column draws nothing even measured — the reading above proves nothing")
        }
    }

    /// «Opened …» on the row in every language and both appearances, and it is
    /// not the «no record» line: the same row with no record draws different
    /// pixels in the same place. PNGs per language in `HELM_FRAMES_DIR`.
    func testTheOpenedLineIsDrawnInEveryLanguage() async throws {
        for language in AppLanguage.allCases {
            for appearance in RenderedInk.bothAppearances {
                let dated = try await rowRender(language, appearance,
                                                opened: [Self.gamma.path: Date(timeIntervalSinceNow: -86_400 * 40)])
                let unrecorded = try await rowRender(language, appearance, opened: [Self.beta.path: Date()])
                let label = "\(language.rawValue)-\(RenderedInk.label(of: appearance))"
                write(dated.mount, "row-opened-\(label)")
                write(unrecorded.mount, "row-norecord-\(label)")
                let inkDated = try XCTUnwrap(RenderedInk.read(dated.mount.host, points: dated.row, columns: trailing(dated.mount)))
                XCTAssertGreaterThan(inkDated, 0, "\(label): nothing drawn where «Opened …» goes")
                XCTAssertNotEqual(dated.mount.pixels(dated.row), unrecorded.mount.pixels(unrecorded.row),
                                  "\(label): the dated row draws the same as the row with no record")
                AppLanguage.only(language) {
                    let line = UnStr.opened("X")
                    XCTAssertTrue(line.contains("X"), "\(label): the age is not in the line «\(line)»")
                    if language != .en {
                        XCTAssertNotEqual(line, "Opened X", "\(label): «Opened» is not translated")
                    }
                }
            }
        }
    }

    private func rowRender(_ language: AppLanguage, _ appearance: NSAppearance.Name,
                           opened: [String: Date]) async throws -> (mount: MountedRender, row: ClosedRange<Int>) {
        AppLanguage.override = language
        defer { AppLanguage.override = previousLanguage }
        let wire = wire([Self.gamma])
        wire.setOpened(opened)
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        let mount = MountedRender(page(vm), width: 800, height: 600, appearance: appearance)
        mounts.append(mount)
        mount.settle(30)
        let table = try XCTUnwrap(mount.host.everyView(ofType: NSTableView.self).first)
        return (mount, try XCTUnwrap(band(of: 0, in: table, host: mount.host)))
    }

    // MARK: - Does a re-sort or a tab switch morph the page

    private struct Frame { let at: TimeInterval; let pixels: Data }

    private func photograph(_ mount: MountedRender, turns: Int = 45, since start: Date) throws -> [Frame] {
        var out: [Frame] = []
        for _ in 0..<turns {
            mount.host.layoutSubtreeIfNeeded()
            let pixels = try XCTUnwrap(mount.pixels(), "the mount drew nothing")
            out.append(Frame(at: Date().timeIntervalSince(start), pixels: pixels))
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.016))
        }
        return out
    }

    /// A cut is a drawing that goes from `before` to the settled one with nothing
    /// in between. Every frame that is neither is a frame of motion, with one
    /// exception: the very first turn, where the striped list has its rows but
    /// has not yet painted the stripes of its empty area (seen with every page
    /// curve removed, `no-tab-count-curves/tab-*-apps-000`). One turn of grace
    /// and not two: the page's curve is 0.22 s and a SwiftUI rebuild can hold a
    /// run-loop turn for ~0.3 s, so the camera may get exactly one frame inside
    /// the curve, and it is the second one — which a grace of two lets through.
    private func judge(_ shots: [Frame], before: Data, _ label: String,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let settled = try XCTUnwrap(shots.last)
        XCTAssertNotEqual(before, settled.pixels,
                          "\(label): the drawing did not change, so this case proves nothing", file: file, line: line)
        let between = shots.enumerated().dropFirst().filter { $0.element.pixels != settled.pixels && $0.element.pixels != before }
        XCTAssertEqual(between.count, 0,
                       "\(label): \(between.count) frames were neither the drawing before nor the settled one — frames \(between.map { "#\($0.offset) at \(Int($0.element.at * 1000)) ms" })",
                       file: file, line: line)
    }

    private func mountForFrames(_ appearance: NSAppearance.Name, wire: any EngineTransport)
        async throws -> (MountedRender, UninstallerViewModel, HelmWindowToolbarChannel) {
        AppLanguage.override = .en
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        let channel = HelmWindowToolbarChannel()
        let mount = MountedRender(page(vm), width: 800, height: 600, appearance: appearance, channel: channel)
        mounts.append(mount)
        mount.settle(40)
        // The page's own `.task` reads the order back; let that land before a
        // case changes it, or the case races the page (see
        // `testAnOrderReadBeforeAChoiceDoesNotUndoTheChoice`).
        await HelmTestSupport.grace(0.3)
        mount.settle(10)
        return (mount, uvm, channel)
    }

    /// Name to Size to Date and back to Name: four rows change places, and the
    /// page cuts to the new order.
    func testAReSortCutsToTheNewOrder() async throws {
        for appearance in RenderedInk.bothAppearances {
            let probe = wire()
            let (mount, uvm, _) = try await mountForFrames(appearance, wire: RememberingWire(probe))
            for order in [AppSortOrder.size, .dateLastOpened, .name] {
                let before = try XCTUnwrap(mount.pixels())
                let start = Date()
                await uvm.setSortOrder(order)
                XCTAssertEqual(uvm.effectiveSortOrder, order, "precondition: the model is not in the order asked for")
                let shots = try photograph(mount, since: start)
                writeFrames(shots, mount, "resort-\(RenderedInk.label(of: appearance))-\(order.rawValue)")
                try judge(shots, before: before, "\(appearance.rawValue), re-sort to \(order)")
            }
        }
    }

    /// Apps to Leftovers and back: the tab switch, under the page-wide
    /// `.animation(value: tab)`.
    func testATabSwitchCutsBetweenTheTabs() async throws {
        for appearance in RenderedInk.bothAppearances {
            let (mount, _, channel) = try await mountForFrames(appearance, wire: wire())
            for tab in ["orphans", "apps"] {
                let before = try XCTUnwrap(mount.pixels())
                let start = Date()
                let content = try XCTUnwrap(channel.content(for: UninstallerDescriptor.id.rawValue))
                try XCTUnwrap(content.selectedTab).wrappedValue = tab
                let shots = try photograph(mount, since: start)
                writeFrames(shots, mount, "tab-\(RenderedInk.label(of: appearance))-\(tab)")
                try judge(shots, before: before, "\(appearance.rawValue), tab to \(tab)")
            }
        }
    }

    /// Under the size order, the sizes arrive on a list that was drawn without
    /// them: one re-sort, and the count does not change, so the count curve
    /// should not be carrying it.
    func testSizesLandingUnderTheSizeOrderReSortOnceWithoutMotion() async throws {
        for appearance in RenderedInk.bothAppearances {
            let wire = wire()
            wire.answers(.nothing, to: .appSizes)
            wire.setOrder(.size)
            let (mount, uvm, _) = try await mountForFrames(appearance, wire: wire)
            await uvm.setSortOrder(.size)
            mount.settle(20)
            XCTAssertEqual(uvm.sortedApps.map(\.name), ["Alpha", "Beta", "Delta", "Gamma"],
                           "precondition: with nothing measured the size order stands in name order")
            wire.answers(.reply, to: .appSizes)
            let before = try XCTUnwrap(mount.pixels())
            let start = Date()
            await uvm.reloadApps()
            XCTAssertEqual(uvm.sortedApps.map(\.name), ["Gamma", "Beta", "Delta", "Alpha"])
            let shots = try photograph(mount, since: start)
            writeFrames(shots, mount, "sizes-land-\(RenderedInk.label(of: appearance))")
            try judge(shots, before: before, "\(appearance.rawValue), sizes land under Size")
        }
    }

    /// A refresh that finds one more app, under the size order: the count
    /// changes, and the page carries `.animation(value: apps.count)`.
    func testARefreshThatAddsAnAppUnderASortDoesNotMorphThePage() async throws {
        let epsilon = InstalledApp(name: "Epsilon", bundleID: "com.x.epsilon",
                                   path: "/Applications/Epsilon.app", sizeBytes: 3_000_000_000)
        for appearance in RenderedInk.bothAppearances {
            let growing = GrowingWire(first: Self.apps, then: Self.apps + [epsilon], opened: Self.opened)
            let (mount, uvm, _) = try await mountForFrames(appearance, wire: growing.wire)
            await uvm.setSortOrder(.size)
            mount.settle(30)
            growing.grow()
            let before = try XCTUnwrap(mount.pixels())
            let start = Date()
            await uvm.reloadApps()
            XCTAssertEqual(uvm.apps.count, 5, "the refresh did not land")
            let shots = try photograph(mount, since: start)
            writeFrames(shots, mount, "refresh-plus-one-\(RenderedInk.label(of: appearance))")
            try judge(shots, before: before, "\(appearance.rawValue), refresh +1 under Size")
        }
    }

    // MARK: - Helpers

    private func page(_ vm: ModuleViewModel) -> some View {
        UninstallerSettingsPage(vm: vm)
            .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted))
    }

    /// Row `index` of `table` as a band of the host, in points from the top.
    private func band(of index: Int, in table: NSTableView, host: NSView) -> ClosedRange<Int>? {
        guard index < table.numberOfRows else { return nil }
        let r = table.convert(table.rect(ofRow: index), to: host)
        let top = host.isFlipped ? r.minY : host.bounds.height - r.maxY
        let lo = Int(top.rounded(.up)) + 1, hi = Int((top + r.height).rounded(.down)) - 1
        return lo < hi ? lo...hi : nil
    }

    /// The row's right-hand column — the size and the opened line, and nothing
    /// else on the row reaches this far right.
    private func trailing(_ mount: MountedRender) -> ClosedRange<Int> {
        let w = Int(mount.host.bounds.width)
        return (w - 170)...(w - 8)
    }

    private var framesDir: String? { ProcessInfo.processInfo.environment["HELM_FRAMES_DIR"] }

    private func write(_ mount: MountedRender, _ name: String) {
        guard let dir = framesDir, let rep = mount.host.bitmapImageRepForCachingDisplay(in: mount.host.bounds) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        mount.host.cacheDisplay(in: mount.host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func writeFrames(_ frames: [Frame], _ mount: MountedRender, _ named: String) {
        guard let dir = framesDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let width = mount.host.bounds.width, height = mount.host.bounds.height
        for (index, frame) in frames.enumerated() {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2),
                                             pixelsHigh: Int(height * 2), bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
                  let target = rep.bitmapData else { continue }
            _ = frame.pixels.withUnsafeBytes { raw in
                memcpy(target, raw.baseAddress!, min(raw.count, rep.bytesPerRow * rep.pixelsHigh))
            }
            let stamp = String(format: "%03d-%04dms", index, Int(frame.at * 1000))
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/\(named)-\(stamp).png"))
        }
    }
}

/// A wire whose app list grows between two reads — the wire's own list is fixed
/// at construction, so this switches between two of them.
private final class GrowingWire: @unchecked Sendable {
    private let lock = NSLock()
    private let first: UninstallerWire
    private let second: UninstallerWire
    private var grown = false
    init(first: [InstalledApp], then: [InstalledApp], opened: [String: Date]) {
        self.first = UninstallerWire(apps: first)
        self.second = UninstallerWire(apps: then)
        self.first.setOpened(opened)
        self.second.setOpened(opened)
        self.first.setOrder(.size)
        self.second.setOrder(.size)
    }
    func grow() { lock.withLock { grown = true } }
    var wire: Switch { Switch(owner: self) }
    fileprivate var current: UninstallerWire { lock.withLock { grown ? second : first } }

    final class Switch: EngineTransport, @unchecked Sendable {
        let owner: GrowingWire
        init(owner: GrowingWire) { self.owner = owner }
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { try await owner.current.send(command) }
    }
}

/// The engine as it is while a person is working: `appSizes` is still being
/// measured and answers only at `land()`, and each `scan` can be held so the
/// sizes land in the middle of a review. Payloads are recorded by the wire
/// inside.
private final class ArrivingWire: EngineTransport, @unchecked Sendable {
    private let inner: UninstallerWire
    private let sizes: [String: Int]
    private let lock = NSLock()
    private var landed = false
    private var held = false
    private var asked = 0
    init(_ inner: UninstallerWire, sizes: [String: Int]) { self.inner = inner; self.sizes = sizes }
    var events: AsyncStream<EngineEvent> { inner.events }
    func land() { lock.withLock { landed = true } }
    func holdScans() { lock.withLock { held = true } }
    func releaseScans() { lock.withLock { held = false } }
    var scansAsked: Int { lock.withLock { asked } }
    func send(_ command: EngineCommand) async throws -> Data {
        switch command.name {
        case UninstallerCommand.appSizes.rawValue:
            while !lock.withLock({ landed }) { try? await Task.sleep(nanoseconds: 5_000_000) }
            return try JSONEncoder().encode(sizes)
        case UninstallerCommand.scan.rawValue:
            let reply = try await inner.send(command)
            lock.withLock { asked += 1 }
            while lock.withLock({ held }) { try? await Task.sleep(nanoseconds: 5_000_000) }
            return reply
        default:
            return try await inner.send(command)
        }
    }
}

/// Sizes the engine has not measured yet: `appSizes` answers nothing until
/// `land()`, and then the measurement — which the listing itself never carries.
private final class SizesLandLater: EngineTransport, @unchecked Sendable {
    private let inner: UninstallerWire
    private let sizes: [String: Int]
    private let lock = NSLock()
    private var landed = false
    init(_ inner: UninstallerWire, sizes: [String: Int]) { self.inner = inner; self.sizes = sizes }
    var events: AsyncStream<EngineEvent> { inner.events }
    func land() { lock.withLock { landed = true } }
    func send(_ command: EngineCommand) async throws -> Data {
        guard command.name == UninstallerCommand.appSizes.rawValue else { return try await inner.send(command) }
        return lock.withLock { landed } ? try JSONEncoder().encode(sizes) : Data()
    }
}

/// The engine's half of the order that `UninstallerWire` leaves out: a
/// `setSortOrder` is remembered and the next `sortOrder` answers it, as
/// `UninstallerEngine` does through its store.
private final class RememberingWire: EngineTransport, @unchecked Sendable {
    let inner: UninstallerWire
    private let lock = NSLock()
    private var stored: AppSortOrder?
    init(_ inner: UninstallerWire) { self.inner = inner }
    var events: AsyncStream<EngineEvent> { inner.events }
    func send(_ command: EngineCommand) async throws -> Data {
        if command.name == UninstallerCommand.setSortOrder.rawValue,
           let order = try? JSONDecoder().decode(AppSortOrder.self, from: command.payload) {
            inner.setOrder(order)
            lock.withLock { stored = order }
        }
        return try await inner.send(command)
    }
}

extension UninstallerWire {
    /// What the last `sortOrder` reply would say, read by answering one.
    var storedOrder: AppSortOrder? {
        get async {
            guard let data = try? await send(EngineCommand(name: UninstallerCommand.sortOrder.rawValue, payload: Data()))
            else { return nil }
            return try? JSONDecoder().decode(AppSortOrder.self, from: data)
        }
    }
}

/// Holds the `sortOrder` reply after it has been read — the answer is taken
/// when the request arrives, and delivered only when released.
private final class HeldOrderWire: EngineTransport, @unchecked Sendable {
    private let inner: RememberingWire
    private let lock = NSLock()
    private var released = false
    private var askedFlag = false
    init(_ inner: RememberingWire) { self.inner = inner }
    var events: AsyncStream<EngineEvent> { inner.events }
    var asked: Bool { lock.withLock { askedFlag } }
    func release() { lock.withLock { released = true } }
    func send(_ command: EngineCommand) async throws -> Data {
        let reply = try await inner.send(command)
        guard command.name == UninstallerCommand.sortOrder.rawValue else { return reply }
        lock.withLock { askedFlag = true }
        while !lock.withLock({ released }) { try? await Task.sleep(nanoseconds: 5_000_000) }
        return reply
    }
}
