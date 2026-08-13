import HelmTestSupport
import XCTest

/// Every view model that can put files in the Trash refuses to do it twice at
/// once.
///
/// Four modules send a `trash` command: Disk, Duplicates, Leftovers and the
/// Uninstaller. In three of them the destructive button was live for the whole
/// length of the request, because what dims it — an empty basket, an empty
/// selection — is not emptied until the answer comes back. A second press is
/// not a second deletion; the files are already in the Trash. It is a
/// **refusal per path**, because a path that is no longer there is refused with
/// a reason, and the model then overwrites the report of the removal that
/// worked. The person is told nothing moved, and shown a list of everything
/// that did.
///
/// Disk's is the worst of the three: its second round comes back with
/// `removed` empty, so the tree is not pruned either — the files that left are
/// still drawn, under a banner saying nothing was freed.
///
/// The Uninstaller had the flag and no guard: it set `busy` for the page to
/// read and trusted `.disabled(model.busy)` to keep a second press out, which
/// is a redraw away and does not cover the row menu. **The model refuses; the
/// page dims. Both, or neither is reliable.**
///
/// `OneRemovalAtATimeTests` in Leftovers proves the behaviour against a
/// transport that does not answer until it is told to — a fake that answers
/// synchronously releases the gate before the call it is gating returns, and a
/// test built on one passes whether or not the gate exists. This test is the
/// other half: that nobody drops the guard, in a module that has one today or
/// in the next module to grow a basket.
final class OneRemovalAtATimeEverywhereTests: XCTestCase {

    func testEveryTrashingViewModelRefusesASecondRun() throws {
        // `RepoSource.root`, not three `deletingLastPathComponent`s: that count is a
        // fact about where this file sits, and moving the file makes the walk land
        // somewhere with no `Sources/Modules` in it — an enumerator over nothing,
        // `checked.count == 0`, and a scan that fails for a reason that reads like
        // the finding it is looking for. `RepoSource` walks up to `Package.swift`
        // and answers the same from any depth (CLAUDE.md § Test plumbing).
        let modules = RepoSource.root.appendingPathComponent("Sources/Modules")

        var checked: [String] = []
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: modules, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  url.lastPathComponent.hasSuffix("ViewModel.swift"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  source.contains("Command.trash")
            else { continue }
            checked.append(url.lastPathComponent)
            if !source.contains("guard !busy") {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertEqual(checked.count, 4,
                       "\(checked.count) trashing view models were found rather than four, "
                       + "so this scan is looking for something that has changed shape: "
                       + "\(checked.sorted())")
        XCTAssertTrue(offenders.isEmpty,
                      "these can start a second removal while the first is still running, "
                      + "which reports the first as having failed: "
                      + offenders.sorted().joined(separator: ", "))
    }
}
