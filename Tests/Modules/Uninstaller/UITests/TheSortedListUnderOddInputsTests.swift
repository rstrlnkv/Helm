import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The Apps tab's sort at the inputs its first tests did not feed in.**
///
/// This file takes the order to the path that deletes: ticks made under one order
/// and a review built under another, with the sizes landing in the middle of it.
/// The review, the scans it asks for and the batch sent to the Trash must name
/// exactly the ticked apps.
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

    private func work(_ list: [InstalledApp] = TheSortedListUnderOddInputsTests.apps,
                      sizes: [String: Int]? = nil) -> AnsweringWork {
        let work = AnsweringWork(apps: list, scans: Self.scans(list),
                                 removal: UninstallResult(trashed: [], freedBytes: 0), sizes: sizes)
        work.setOpened(Self.opened)
        return work
    }

    // MARK: - The path that deletes

    /// Ticks made under the size order, the list re-sorted twice, and the review
    /// built: it holds exactly the ticked apps, the scans asked for exactly them,
    /// and the batch sent to the Trash names exactly their bundles. The ticked
    /// pair is not the first two in the name order (the list `apps` holds) nor in
    /// the order the review is built under, so a selection that followed a
    /// position rather than an identity picks different apps.
    func testReSortingKeepsTheTicksAndTheReviewAndTheBatchAreExactlyTheTicked() async throws {
        let work = work()
        let uvm = modelOver(work)
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
        XCTAssertEqual(Set(work.scanned), ticked, "the scans asked about other apps than the ticked")

        await uvm.removeSelection()
        let batch = try XCTUnwrap(work.batches.last, "the removal was never sent")
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
            let work = work(listed, sizes: sizes)
            work.holdSizes()
            let uvm = modelOver(work)
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

            work.holdScans()
            let review = Task { await uvm.prepareReview() }
            await until("\(order): the review asked for both scans") { work.scansAsked == 2 }
            work.land()
            await load.value
            XCTAssertEqual(uvm.measuredSizes.count, Self.apps.count, "\(order): precondition — the sizes landed mid-review")
            if order == .size {
                XCTAssertNotEqual(uvm.sortedApps.map(\.bundleID), shown.map(\.bundleID),
                                  "precondition: under Size the rows changed places between the ticks and the review")
            }
            XCTAssertEqual(uvm.checked, ticked, "\(order): the ticks moved when the sizes landed")
            work.releaseScans()
            await review.value

            XCTAssertEqual(uvm.step, .review, "\(order): the review never opened")
            XCTAssertEqual(uvm.groups.map(\.app.bundleID).sorted(), ticked.sorted(),
                           "\(order): the review lists other apps than the ticked")
            XCTAssertEqual(work.scanned.sorted(), ticked.sorted(), "\(order): the scans asked about other apps than the ticked")

            await uvm.removeSelection()
            let batch = try XCTUnwrap(work.batches.last, "\(order): the removal was never sent")
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
}
