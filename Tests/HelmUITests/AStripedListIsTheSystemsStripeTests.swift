import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **`helmStripedList(rowPitch:)` turns the system's alternating row fill on;
/// a bare `.listStyle(.inset)` does not.** Both mounts start with the same
/// guard — `tables.isEmpty` reads as "SwiftUI stopped building a `List` on an
/// `NSTableView`", a total failure of the modifier that would otherwise look
/// exactly like the control passing.
@MainActor
final class AStripedListIsTheSystemsStripeTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    private func mount(striped: Bool) -> MountedRender {
        let view = Group {
            if striped {
                List { ForEach(0..<5, id: \.self) { Text("\($0)") } }
                    .helmStripedList(rowPitch: HelmSpace.s8)
            } else {
                List { ForEach(0..<5, id: \.self) { Text("\($0)") } }
                    .listStyle(.inset)
            }
        }
        let render = MountedRender(view, width: 300, height: 200, appearance: .aqua)
        renders.append(render)
        return render
    }

    func testABareInsetListDoesNotStripe() throws {
        let render = mount(striped: false)
        let tables = render.host.everyView(ofType: NSTableView.self)
        XCTAssertFalse(tables.isEmpty, "no NSTableView under the mount")
        for table in tables {
            XCTAssertFalse(table.usesAlternatingRowBackgroundColors,
                           "a plain .listStyle(.inset) list already stripes — the control is wrong")
        }
    }

    func testHelmStripedListStripes() throws {
        let render = mount(striped: true)
        let tables = render.host.everyView(ofType: NSTableView.self)
        XCTAssertFalse(tables.isEmpty, "no NSTableView under the mount")
        for table in tables {
            XCTAssertTrue(table.usesAlternatingRowBackgroundColors,
                          "helmStripedList(rowPitch:) did not turn on the system's alternating fill")
        }
    }
}
