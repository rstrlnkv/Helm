import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **Uninstaller's and Orphans' lists, scrolled to their end, stop at their
/// last row** — the same reading as `TheListEndsAtItsLastRowTests` on
/// Homebrew, where the owner saw three empty striped rows under the last
/// package. Each list is given enough rows to scroll, scrolled to the furthest
/// offset its clip view allows (`StripedListEnd`), and judged against its own
/// row step. Light and Dark.
@MainActor
final class TheUninstallerListsEndAtTheirLastRowTests: XCTestCase {

    private static let appCount = 60

    private static var apps: [InstalledApp] {
        (0..<appCount).map {
            InstalledApp(name: String(format: "App %03d", $0), bundleID: "com.acme.app\($0)",
                         path: "/Applications/App \($0).app", sizeBytes: 4_096)
        }
    }

    private static var leftovers: [Leftover] {
        (0..<appCount).map {
            Leftover(path: "\(NSHomeDirectory())/Library/Caches/com.acme.app0/item\($0)",
                     kind: .caches, sizeBytes: 1_024, matchedByName: false)
        }
    }

    private func wire() -> UninstallerWire {
        let first = Self.apps[0]
        return UninstallerWire(
            apps: Self.apps,
            scans: [first.bundleID: ScanResult(bundleID: first.bundleID, appPath: first.path,
                                               appSizeBytes: 0, leftovers: Self.leftovers,
                                               runningNow: false)])
    }

    private func mountPage(_ vm: ModuleViewModel, _ appearance: NSAppearance.Name) -> MountedRender {
        MountedRender(UninstallerSettingsPage(vm: vm)
                        .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted)),
                      width: 700, height: 540, appearance: appearance)
    }

    private func judge(_ mount: MountedRender, _ name: String, atLeast count: Int,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let table = try XCTUnwrap(StripedListEnd.table(in: mount.host), "\(name): no table", file: file, line: line)
        XCTAssertGreaterThanOrEqual(table.numberOfRows, count, """
            \(name): \(table.numberOfRows) rows where \(count) were given — the subject never arrived
            """, file: file, line: line)
        let reading = try XCTUnwrap(StripedListEnd.read(table, host: mount.host), "\(name): no scroll view",
                                    file: file, line: line)
        print("[list-end] \(name): \(reading)")
        XCTAssertTrue(reading.scrollable, "\(name): the list did not scroll — \(reading)", file: file, line: line)
        XCTAssertLessThan(reading.overscroll, table.rowHeight / 2, """
            \(name): scrolled to its end the list shows \(reading.overscroll) pt of empty rows under \
            the last one — \(reading)
            """, file: file, line: line)
    }

    private func pickAndReview(_ appearance: NSAppearance.Name) async throws {
        let vm = ModuleViewModel(transport: wire())
        let uvm = UninstallerViewModel.shared(vm: vm)
        let mount = mountPage(vm, appearance)
        defer { mount.drop() }
        let tag = appearance == .aqua ? "Light" : "Dark"
        await uvm.loadAppsIfNeeded()
        mount.settle(30)
        XCTAssertEqual(uvm.step, .pick, "precondition: the picker is up first")
        try judge(mount, "Uninstaller pick \(tag)", atLeast: Self.appCount)

        uvm.setChecked(Self.apps[0].bundleID, true)
        await uvm.prepareReview()
        mount.settle(30)
        XCTAssertEqual(uvm.step, .review, "precondition: review followed the pick")
        try judge(mount, "Uninstaller review \(tag)", atLeast: Self.appCount)
    }

    func testPickAndReviewEndAtTheirLastRowInLight() async throws { try await pickAndReview(.aqua) }
    func testPickAndReviewEndAtTheirLastRowInDark() async throws { try await pickAndReview(.darkAqua) }

    // MARK: - Orphans

    private final class OrphansWire: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        let groups: [OrphanGroup]
        init(groups: [OrphanGroup]) { self.groups = groups }
        func send(_ command: EngineCommand) async throws -> Data {
            switch UninstallerCommand(rawValue: command.name) {
            case .scanOrphans: return try JSONEncoder().encode(groups)
            case .watchingTrash: return try JSONEncoder().encode(TrashWatch.off)
            default: return Data()
            }
        }
    }

    private func orphans(_ appearance: NSAppearance.Name) throws {
        let groups = (0..<3).map { g in
            OrphanGroup(bundleID: "com.gone.\(g)", leftovers: (0..<20).map {
                Leftover(path: "\(NSHomeDirectory())/Library/Caches/com.gone.\(g)/item\($0)",
                         kind: .caches, sizeBytes: 1_024, matchedByName: false)
            })
        }
        let vm = ModuleViewModel(transport: OrphansWire(groups: groups))
        let uvm = UninstallerViewModel.shared(vm: vm)
        let mount = MountedRender(OrphansView(uvm: uvm), width: 700, height: 640, appearance: appearance)
        defer { mount.drop() }
        mount.settle(30)
        mount.window?.orderFrontRegardless()
        mount.settle(10)
        let window = try XCTUnwrap(mount.window)
        // The scan button: the lowest control on the page before any list.
        let rings = mount.host.everyView(named: "_FocusRingView")
        let target = try XCTUnwrap(rings.max {
            $0.convert($0.bounds, to: nil).midY < $1.convert($1.bounds, to: nil).midY
        }, "no control drew under the page")
        let rect = target.convert(target.bounds, to: nil)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil,
                                                         eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
            mount.settle(2)
        }
        for _ in 0..<20 where mount.host.everyView(ofType: NSTableView.self).isEmpty {
            mount.settle(10)
        }
        try judge(mount, "Orphans \(appearance == .aqua ? "Light" : "Dark")", atLeast: 60)
    }

    func testOrphansEndAtTheirLastRowInLight() throws { try orphans(.aqua) }
    func testOrphansEndAtTheirLastRowInDark() throws { try orphans(.darkAqua) }
}
