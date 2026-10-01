import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **A row's right-hand column is two lines from the first frame, so the date
/// does not slide when the sizes arrive.**
///
/// The sizes come 4-9 s after the list. While the size line was absent the date
/// stood alone, centred in the row; when the size appeared above it every date
/// on screen dropped half a line at once. The place stays reserved, empty.
@MainActor
final class TheDateStaysWhereItIsWhenTheSizesLandTests: XCTestCase {

    private let app = InstalledApp(name: "Gamma", bundleID: "com.x.gamma",
                                   path: "/Applications/Gamma.app", sizeBytes: 9_000_000_000)
    private var mounts: [MountedRender] = []
    private var previous: AppLanguage?
    override func setUp() { super.setUp(); previous = AppLanguage.override }
    override func tearDown() {
        mounts.forEach { $0.drop() }
        mounts = []
        AppLanguage.override = previous
        super.tearDown()
    }

    /// (`read` takes rows lower..<upper, so one point-row is `y...(y + 1)`.)
    /// The lowest point-row with ink in the trailing column of row 0: the date
    /// is the lower of the column's lines, so this is where the date sits.
    private func dateBottom(_ mount: MountedRender) throws -> (bottom: Int, top: Int) {
        let table = try XCTUnwrap(mount.host.everyView(ofType: NSTableView.self).first)
        let r = table.convert(table.rect(ofRow: 0), to: mount.host)
        let top = mount.host.isFlipped ? r.minY : mount.host.bounds.height - r.maxY
        let lo = Int(top.rounded(.up)) + 1, hi = Int((top + r.height).rounded(.down)) - 1
        let w = Int(mount.host.bounds.width)
        var inked: [Int] = []
        for y in lo...hi {
            let ink = try XCTUnwrap(RenderedInk.read(mount.host, points: y...(y + 1), columns: (w - 170)...(w - 8)))
            if ink > 0 { inked.append(y) }
        }
        return (try XCTUnwrap(inked.max(), "the right-hand column drew nothing in the row"),
                try XCTUnwrap(inked.min()))
    }

    func testTheDateDoesNotMoveWhenTheSizeArrives() async throws {
        for appearance in RenderedInk.bothAppearances {
            AppLanguage.override = .en
            let wire = UninstallerWire(apps: [app])
            wire.setOpened([app.path: Date(timeIntervalSinceNow: -86_400 * 3)])
            wire.answers(.nothing, to: .appSizes)
            let vm = ModuleViewModel(transport: wire)
            let uvm = UninstallerViewModel.shared(vm: vm)
            await uvm.loadAppsIfNeeded()
            XCTAssertTrue(uvm.measuredSizes.isEmpty, "precondition: nothing was measured")
            let mount = MountedRender(UninstallerSettingsPage(vm: vm)
                .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted)),
                                      width: 860, height: 600, appearance: appearance)
            mounts.append(mount)
            mount.settle(30)
            let before = try dateBottom(mount)

            wire.answers(.reply, to: .appSizes)
            await uvm.reloadApps()
            mount.settle(30)
            XCTAssertEqual(uvm.measuredSizes[app.path], app.sizeBytes, "precondition: the size landed")
            let after = try dateBottom(mount)
            XCTAssertLessThan(after.top, before.top,
                              "\(appearance.rawValue): precondition: the size line drew nothing above the date once landed")
            XCTAssertEqual(after.bottom, before.bottom,
                           "\(appearance.rawValue): the date slid from \(before.bottom) to \(after.bottom) pt when the size arrived")
        }
    }

    // MARK: - The line's age is spelled out

    private var sevenMonths: Date { Date(timeIntervalSinceNow: -86_400 * 215) }

    /// The short form of es and fr is one letter for a month and for a year
    /// («7 m», «2 a»), and «m» reads as minutes or metres.
    func testMonthsAndYearsAreSpelledOutInEveryLanguage() {
        let words: [AppLanguage: String] = [.es: "meses", .fr: "mois", .de: "Monaten", .pt: "meses"]
        for (language, word) in words {
            AppLanguage.only(language) {
                let line = HelmDates.age(sevenMonths, style: .full).map(UnStr.opened) ?? ""
                XCTAssertTrue(line.contains(word), "\(language.rawValue): «\(line)» does not spell the month out")
            }
        }
        let source = (try? RepoSource.text(of: "Sources/Modules/Uninstaller/UI/UninstallerSettingsPage.swift")) ?? ""
        XCTAssertTrue(source.contains("HelmDates.age(date, style: .full)"), "the row's age is not the full form")
    }

    /// At the narrowest window the row's right-hand column must not be wider
    /// than the widest line it already carried and the designer saw fit at 860 pt:
    /// «No record of opening» in de (153 pt as measured with the subheadline
    /// face). The widest full age is ru «Открыто 6 месяцев назад» (142 pt).
    func testTheFullAgeIsNoWiderThanTheWidestLineTheColumnAlreadyHeld() {
        let font = NSFont.preferredFont(forTextStyle: .subheadline)
        func width(_ text: String) -> CGFloat { NSAttributedString(string: text, attributes: [.font: font]).size().width }
        let spans: [Double] = [1, 30, 3_600, 172_800, 691_200, 3_456_000, 6_480_000, 17_280_000,
                               34_560_000, 69_120_000, 259_200_000]
        var widestAge: CGFloat = 0, widestHeld: CGFloat = 0
        for language in AppLanguage.allCases {
            AppLanguage.only(language) {
                widestHeld = max(widestHeld, width(UnStr.noRecordOfOpening))
                for span in spans {
                    guard let age = HelmDates.age(Date(timeIntervalSinceNow: -span), style: .full) else { continue }
                    widestAge = max(widestAge, width(UnStr.opened(age)))
                }
            }
        }
        XCTAssertGreaterThan(widestAge, 0, "no age was measured")
        XCTAssertLessThanOrEqual(widestAge, widestHeld,
                                 "a full age is \(widestAge) pt, wider than the \(widestHeld) pt the column held")
    }

    func testTheGermanDateOrderIsFindersOwnWord() {
        AppLanguage.only(.de) {
            XCTAssertTrue(UnStr.sortName(.dateLastOpened).contains("Zuletzt geöffnet"),
                          "Finder's name for this column is «Zuletzt geöffnet»")
        }
    }
}
