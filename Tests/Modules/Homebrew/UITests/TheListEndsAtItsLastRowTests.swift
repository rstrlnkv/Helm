import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **A list scrolled to its end stops at its last row.**
///
/// The owner's report: on Установленные, with a hundred-odd packages, the list
/// scrolled well past `zcode` — the last row sat in the middle of the list with
/// about three empty striped rows under it before the list ended above the
/// footer. Nothing is supposed to be under the last row but the table's own
/// bottom padding.
///
/// The page is mounted with enough packages to scroll, scrolled to the
/// furthest offset its clip view allows (`StripedListEnd`), and read there:
/// the distance from the last row's bottom edge to the bottom of what is
/// visible. **The structure, not a figure:** that distance is judged against
/// the table's own row step — anything half a row or more is an empty row a
/// person can scroll into — and the subject is asserted first: the list had
/// the rows, and it could scroll at all.
///
/// With and without the console, Light and Dark.
@MainActor
final class TheListEndsAtItsLastRowTests: XCTestCase {

    private final class Cellar: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        let packages: [BrewPackage]
        let describes: Bool

        init(count: Int, describes: Bool = false) {
            self.describes = describes
            packages = (0..<(count - 1)).map {
                BrewPackage(name: String(format: "pkg-%03d", $0), version: "1.0.\($0)", isCask: false)
            } + [BrewPackage(name: "zcode", version: "9.9", isCask: false)]
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode(packages)
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions:
                guard describes else { return try JSONEncoder().encode([String: String]()) }
                return try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: packages.map {
                    ($0.name, "A fixture description of \($0.name) that runs long enough to wrap in a narrow column")
                }))
            case .doctor: return try JSONEncoder().encode([DoctorIssue]())
            default: return Data()
            }
        }

        func state(_ op: OpState) {
            stream.continuation.yield(EngineEvent(name: HomebrewEvent.opState.rawValue,
                                                  payload: (try? JSONEncoder().encode(op)) ?? Data()))
        }

        func say(_ line: String) {
            stream.continuation.yield(
                EngineEvent(name: HomebrewEvent.opLog.rawValue, payload: Data(line.utf8)))
        }
    }

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    func testTheInstalledListEndsAtItsLastRowInLight() async throws {
        try await read(.aqua, console: false)
    }

    func testTheInstalledListEndsAtItsLastRowInDark() async throws {
        try await read(.darkAqua, console: false)
    }

    func testTheInstalledListEndsAtItsLastRowUnderTheConsoleInLight() async throws {
        try await read(.aqua, console: true)
    }

    func testTheInstalledListEndsAtItsLastRowUnderTheConsoleInDark() async throws {
        try await read(.darkAqua, console: true)
    }

    private func read(_ appearance: NSAppearance.Name, console: Bool,
                      width: CGFloat = 984, height: CGFloat = 700) async throws {
        let count = 107
        let transport = Cellar(count: count)
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(nil)
        hb.segment = .installed
        hb.clearConsole()
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: height, appearance: appearance)
        renders.append(mount)
        mount.settle(40)
        if console {
            transport.say("==> Pouring wget--1.25.0.arm64_tahoe.bottle.tar.gz")
            var yields = 0
            while hb.consoleLines.isEmpty && yields < 50_000 { await Task.yield(); yields += 1 }
            XCTAssertFalse(hb.consoleLines.isEmpty, "precondition: the console line never reached the model")
            mount.settle(60)
        }
        let name = "\(appearance == .aqua ? "Light" : "Dark"), console \(console ? "on" : "off")"
        let table = try XCTUnwrap(StripedListEnd.table(in: mount.host), "\(name): no table on the page")
        XCTAssertEqual(StripedListEnd.contentRows(table), count, """
            \(name): the list holds \(StripedListEnd.contentRows(table)) rows that are not headers for \(count) \
            packages — fewer is a subject that never arrived, more is a row that stands for nothing
            """)
        let reading = try XCTUnwrap(StripedListEnd.read(table, host: mount.host), "\(name): no scroll view")
        print("[list-end] Homebrew installed \(name): \(reading)")
        XCTAssertTrue(reading.scrollable, "\(name): \(count) rows did not scroll — \(reading)")
        XCTAssertLessThan(reading.overscroll, table.rowHeight / 2, """
            \(name): scrolled to its end the list shows \(reading.overscroll) pt of empty rows under \
            the last one (\(reading.overscroll / max(table.rowHeight, 1)) rows at \(table.rowHeight) pt) — \(reading)
            """)
    }

    // MARK: - Changes underneath a list that is already at its end

    /// One step of a scenario and what it did to the list.
    private func note(_ mount: MountedRender, _ name: String, _ step: String,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        let table = try XCTUnwrap(StripedListEnd.table(in: mount.host), "\(name) \(step): no table",
                                  file: file, line: line)
        let rest = try XCTUnwrap(StripedListEnd.resting(table), file: file, line: line)
        print("[list-end] \(name) \(step) AT REST origin=\(rest.origin): \(rest.reading)")
        XCTAssertLessThan(rest.reading.overscroll, table.rowHeight / 2, """
            \(name) \(step): the list rests \(rest.reading.overscroll) pt past its last row \
            (\(rest.reading.overscroll / max(table.rowHeight, 1)) rows at \(table.rowHeight) pt), \
            origin \(rest.origin) where AppKit allows \(rest.reading.maxOffset) — \(rest.reading)
            """, file: file, line: line)
    }

    private func toTheEnd(_ mount: MountedRender, _ name: String, _ step: String,
                          file: StaticString = #filePath, line: UInt = #line) throws {
        let table = try XCTUnwrap(StripedListEnd.table(in: mount.host), file: file, line: line)
        let reading = try XCTUnwrap(StripedListEnd.read(table, host: mount.host), file: file, line: line)
        print("[list-end] \(name) \(step) SCROLLED TO END: \(reading)")
        XCTAssertLessThan(reading.overscroll, table.rowHeight / 2, """
            \(name) \(step): scrolled to its end the list shows \(reading.overscroll) pt under its last row — \(reading)
            """, file: file, line: line)
    }

    private func page(_ appearance: NSAppearance.Name, describes: Bool = true,
                      width: CGFloat = 984) async -> (Cellar, HomebrewViewModel, MountedRender) {
        let transport = Cellar(count: 107, describes: describes)
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        hb.select(nil)
        hb.segment = .installed
        // Mounted before anything is loaded, as the page is on the Mac: the
        // page's own `.task` asks for the list, then the descriptions.
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: appearance)
        renders.append(mount)
        mount.settle(60)
        await hb.loadIfNeeded()
        mount.settle(60)
        return (transport, hb, mount)
    }

    /// At the end of the list with the console up, the operation finishes and
    /// the console is cleared: the list gets the console's height back.
    private func consoleGoesAway(_ appearance: NSAppearance.Name) async throws {
        let (transport, hb, mount) = await page(appearance)
        let name = "Homebrew \(appearance == .aqua ? "Light" : "Dark") console goes"
        transport.say("==> Pouring wget--1.25.0.arm64_tahoe.bottle.tar.gz")
        var yields = 0
        while hb.consoleLines.isEmpty && yields < 50_000 { await Task.yield(); yields += 1 }
        XCTAssertFalse(hb.consoleLines.isEmpty, "precondition: the console never came up")
        mount.settle(60)
        try toTheEnd(mount, name, "console up")
        hb.clearConsole()
        mount.settle(60)
        XCTAssertTrue(hb.consoleLines.isEmpty && !hb.running, "precondition: the console did not go")
        try note(mount, name, "console cleared")
        try toTheEnd(mount, name, "console cleared")
    }

    func testTheConsoleGoingAwayLeavesTheListAtItsEndInLight() async throws { try await consoleGoesAway(.aqua) }
    func testTheConsoleGoingAwayLeavesTheListAtItsEndInDark() async throws { try await consoleGoesAway(.darkAqua) }

    /// At the end of the list, the window is made taller.
    private func windowGrows(_ appearance: NSAppearance.Name) async throws {
        let (_, _, mount) = await page(appearance)
        let name = "Homebrew \(appearance == .aqua ? "Light" : "Dark") window grows"
        try toTheEnd(mount, name, "700 tall")
        let window = try XCTUnwrap(mount.window)
        window.setContentSize(NSSize(width: 984, height: 900))
        mount.host.frame = NSRect(x: 0, y: 0, width: 984, height: 900)
        mount.settle(60)
        try note(mount, name, "900 tall")
    }

    func testAWindowGrownAtTheEndStaysAtTheEndInLight() async throws { try await windowGrows(.aqua) }
    func testAWindowGrownAtTheEndStaysAtTheEndInDark() async throws { try await windowGrows(.darkAqua) }

    /// A list loaded after the page mounted, with descriptions, at the
    /// app's default pane and below the inspector's threshold.
    func testALoadedListEndsAtItsLastRowAtEitherWidth() async throws {
        for width: CGFloat in [984, 520] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let (_, _, mount) = await page(appearance, width: width)
                try toTheEnd(mount, "Homebrew \(appearance == .aqua ? "Light" : "Dark") \(Int(width))", "loaded after mount")
            }
        }
    }

    /// At the end of Установленные, over to Обновления and Состояние and back.
    func testTheListAfterARoundOfTheTabsEndsAtItsLastRow() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let (_, hb, mount) = await page(appearance)
            let name = "Homebrew \(appearance == .aqua ? "Light" : "Dark") tabs"
            try toTheEnd(mount, name, "installed")
            hb.segment = .updates
            mount.settle(60)
            hb.segment = .health
            mount.settle(60)
            hb.segment = .installed
            mount.settle(60)
            try note(mount, name, "back on installed")
            try toTheEnd(mount, name, "back on installed")
        }
    }

    /// At the end at 520 (descriptions on the rows), widened to 984.
    func testAListNarrowedAndWidenedAtItsEndStaysAtItsEnd() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let (_, _, mount) = await page(appearance, width: 520)
            let name = "Homebrew \(appearance == .aqua ? "Light" : "Dark") widened"
            try toTheEnd(mount, name, "520")
            let window = try XCTUnwrap(mount.window)
            window.setContentSize(NSSize(width: 984, height: 700))
            mount.host.frame = NSRect(x: 0, y: 0, width: 984, height: 700)
            mount.settle(60)
            try note(mount, name, "984")
            try toTheEnd(mount, name, "984")
        }
    }
}
