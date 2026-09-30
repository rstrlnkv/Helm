import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The real `OrphansView`, scanned, is at the declared pitch.**
///
/// Its groups are a `@State` filled only by the Scan button, and offscreen
/// that button is no `NSButton` and the hosting view publishes no
/// accessibility children to press it by (measured 2026-09-29: the tree under
/// `host` is one `AXGroup` with none). It does draw a `_FocusRingView`, and a mouse
/// down and up sent to this test process's own window at that view's centre is
/// a press: the empty state's button is the topmost control on the page
/// (the watch row and the footer sit under it). No other process is involved.
///
/// The wire answers the orphan scan with two groups, so the list has headers,
/// rows taller than the pitch (a checkbox over two lines) and an empty area.
/// If the click lands anywhere but Scan, no list is drawn and the first
/// precondition after it says so.
@MainActor
final class TheOrphansListIsAtThePitchTests: XCTestCase {

    private static let pitch = HelmSpace.s8

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

    private static func group(_ id: String, _ count: Int) -> OrphanGroup {
        OrphanGroup(bundleID: id, leftovers: (0..<count).map {
            Leftover(path: "\(NSHomeDirectory())/Library/Caches/\(id)/item\($0)",
                     kind: .caches, sizeBytes: 1_024, matchedByName: false)
        })
    }

    func testTheScannedListIsAtThePitchAndTallRowsKeepTheirOwn() throws {
        let wire = OrphansWire(groups: [Self.group("com.gone.one", 3), Self.group("com.gone.two", 2)])
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        let mount = MountedRender(OrphansView(uvm: uvm), width: 700, height: 640, appearance: .aqua)
        defer { mount.drop() }
        mount.settle(30)
        XCTAssertTrue(mount.host.everyView(ofType: NSTableView.self).isEmpty,
                      "precondition: no list before the scan")

        mount.window?.orderFrontRegardless()
        mount.settle(10)
        let window = try XCTUnwrap(mount.window)
        let rings = mount.host.everyView(named: "_FocusRingView")
        let target = try XCTUnwrap(rings.max { $0.convert($0.bounds, to: nil).midY < $1.convert($1.bounds, to: nil).midY },
                                   "no control drew under the page")
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
        // Wall-clock turns of the run loop, bounded: the press starts a main-actor
        // task that asks the wire and fills the `@State`.
        for _ in 0..<20 where mount.host.everyView(ofType: NSTableView.self).isEmpty {
            mount.settle(10)
        }

        let tables = mount.host.everyView(ofType: NSTableView.self)
        XCTAssertEqual(tables.count, 1, "precondition: the scan drew one list")
        let table = try XCTUnwrap(tables.first)
        let rows = StripedListPitch.realRowHeights(in: table)
        let painted = StripedEmptyAreaPitch.read(mount.host, table)
        print("PITCH[orphans] rowHeight=\(table.rowHeight) rows=\(rows) numberOfRows=\(table.numberOfRows) "
              + "painted \(painted.map { "\($0)" } ?? "unreadable")")
        XCTAssertTrue(table.usesAlternatingRowBackgroundColors, "Orphans' list is not striped")
        XCTAssertEqual(rows.count, 5, "precondition: five leftovers drawn as rows, headers left out")
        XCTAssertEqual(table.rowHeight, Self.pitch, accuracy: 0.5, """
            Orphans: rowHeight is \(table.rowHeight) where the list declared \(Self.pitch)
            """)
        XCTAssertEqual(painted?.pitch ?? -1, Self.pitch, accuracy: 1, """
            Orphans: the empty area is painted at \(painted?.pitch.map { "\($0)" } ?? "no readable pitch") \
            where the list declared \(Self.pitch)
            """)
        for height in rows {
            XCTAssertGreaterThan(height, Self.pitch + 0.5, """
                Orphans: a row drew \(height) pt under a \(Self.pitch) pt pitch — a checkbox over \
                two lines keeps its own height
                """)
        }
    }
}
