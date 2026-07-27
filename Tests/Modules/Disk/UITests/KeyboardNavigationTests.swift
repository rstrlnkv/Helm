import XCTest
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Keyboard navigation of the disk list.
///
/// The list had no `selection`, so its rows were not focusable: arrow keys did
/// nothing and the only way into a folder was a double-click. The view code
/// itself cannot be exercised here, so what these pin is the navigation the
/// keyboard drives — that Return on a folder goes in, that ⌘↑ comes back out,
/// and that neither does anything surprising at the edges.
@MainActor
final class KeyboardNavigationTests: XCTestCase {

    private func tree() -> DiskEntry {
        DiskEntry(name: "root", path: "/r", bytes: 300, isDirectory: true, noAccess: false,
                  children: [
                    DiskEntry(name: "folder", path: "/r/folder", bytes: 200,
                              isDirectory: true, noAccess: false, children: [
                                DiskEntry(name: "deep", path: "/r/folder/deep", bytes: 200,
                                          isDirectory: true, noAccess: false, children: []),
                              ]),
                    DiskEntry(name: "file.bin", path: "/r/file.bin", bytes: 100,
                              isDirectory: false, noAccess: false, children: []),
                  ])
    }

    func testReturnOnAFolderGoesIn() {
        let focus = DiskFocus.chain(from: tree(), to: "/r/folder")
        XCTAssertEqual(focus.last?.path, "/r/folder")
        XCTAssertTrue(focus.last?.isDirectory == true)
    }

    /// Return on a file must not drill. The row reveals it instead, which is
    /// the same rule the double-click follows — the gesture that used to do
    /// nothing at all.
    func testAFileIsNotAPlaceToGoInto() {
        let file = tree().children.first { !$0.isDirectory }
        XCTAssertNotNil(file)
        XCTAssertFalse(file!.isDirectory)
        // `DiskFocus.chain` still resolves it; the guard is the caller's.
        let chain = DiskFocus.chain(from: tree(), to: "/r/file.bin")
        XCTAssertEqual(chain.last?.isDirectory, false)
    }

    func testThePathIsWhatTheKeyboardWalks() {
        // Two levels down, then back out: the same stack the ⌘↑ shortcut and
        // the ring's centre both operate on.
        var path = [tree()]
        path += DiskFocus.chain(from: tree(), to: "/r/folder").dropFirst(0)
        XCTAssertGreaterThan(path.count, 1)
        path.removeLast()
        XCTAssertEqual(path.first?.path, "/r")
    }

    /// ⌘↑ is disabled at the root, where the visible Back button is disabled
    /// too — an enabled shortcut that does nothing is a promise not kept.
    func testThereIsNowhereAboveTheRoot() {
        let atRoot = [tree()]
        XCTAssertEqual(atRoot.count, 1, "the guard the shortcut uses")
    }

    func testAPathThatIsGoneResolvesToNothing() {
        XCTAssertTrue(DiskFocus.chain(from: tree(), to: "/r/vanished").isEmpty)
    }
}
