import HelmTestSupport
import XCTest

/// Every view model that can put files in the Trash refuses to do it twice at
/// once.
///
/// Four models remove a batch the person ticked — the Uninstaller over
/// `trashPaths`, Duplicates, Disk and Leftovers by calling their engine's
/// `trash` — and in
/// three of them the destructive button was live for the whole
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
/// `OneRemovalAtATimeTests` in Leftovers proves the behaviour against a fake
/// `LeftoversWork` that does not answer until it is told to — a fake that answers
/// synchronously releases the gate before the call it is gating returns, and a
/// test built on one passes whether or not the gate exists. This test is the
/// other half, and a coarser one: that in a file which sends a removal, every
/// method that sets `busy = true` holds a `guard` on `!busy` before that line. It
/// keys on the method that takes the flag, not on the call that removes: the
/// Uninstaller's `trashPaths` is a pass-through whose callers are the ones that
/// take it.
final class OneRemovalAtATimeEverywhereTests: XCTestCase {

    func testEveryFileThatSendsARemovalRefusesASecondPress() throws {
        // `RepoSource.root`, not three `deletingLastPathComponent`s: that count is
        // a fact about where this file sits, and moving the file makes the walk
        // land somewhere with no `Sources/Modules` in it — an enumerator over
        // nothing, `checked.count == 0`, and a scan that fails for a reason that
        // reads like the finding it is looking for. `RepoSource` walks up to
        // `Package.swift` and answers the same from any depth (CLAUDE.md § Where
        // things go).
        let modules = RepoSource.root.appendingPathComponent("Sources/Modules")

        var checked: [String] = []
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: modules, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  Self.sendsARemoval(source)
            else { continue }
            checked.append(url.lastPathComponent)
            let methods = Self.methodsTakingTheFlag(in: source)
            if methods.isEmpty {
                offenders.append("\(url.lastPathComponent) (no method sets busy = true)")
            }
            for method in methods where !method.guarded {
                offenders.append("\(url.lastPathComponent) \(method.name)")
            }
        }

        XCTAssertEqual(checked.count, 6,
                       "\(checked.count) files that send a removal were found rather than six, "
                       + "so this scan is looking for something that has changed shape: "
                       + "\(checked.sorted())")
        XCTAssertTrue(offenders.isEmpty,
                      "these can start a second removal while the first is still running, "
                      + "which reports the first as having failed: "
                      + offenders.sorted().joined(separator: ", "))
    }

    /// The guard is read per method, so each of these is a method that takes the
    /// flag and the answer says whether a `guard` holding `!busy` comes before it.
    func testTheReadingTellsAGuardedMethodFromAnUnguardedOne() {
        func verdicts(_ body: String) -> [Bool] {
            Self.methodsTakingTheFlag(in: "final class M {\n\(body)\n}").map(\.guarded)
        }
        XCTAssertEqual(verdicts("func a() { guard !busy else { return }; busy = true }"), [true])
        XCTAssertEqual(verdicts("func a() {\n guard !busy, !stopped else { return }\n busy = true }"), [true])
        XCTAssertEqual(verdicts("func a() {\n guard let x = y,\n !self.busy else { return }\n self.busy = true }"), [true])
        XCTAssertEqual(verdicts("func a() { guard !stopped else { return }; busy = true }"), [false],
                       "a guard that does not hold !busy is not the guard")
        XCTAssertEqual(verdicts("func a() { busy = true }"), [false])
        XCTAssertEqual(verdicts("func a() { busy = true; guard !busy else { return } }"), [false],
                       "a guard after the flag is taken guards nothing")
        XCTAssertEqual(verdicts("func a() { // guard !busy\n busy = true }"), [false],
                       "a comment is not a guard")
        XCTAssertEqual(verdicts("func a() { guard !busy else { return }; busy = true }\nfunc b() { busy = true }"),
                       [true, false], "one method's guard is not another's")
        XCTAssertEqual(verdicts("func a() { guard !stopped, !busy else { return }; Task { busy = true } }"), [true])
        XCTAssertEqual(verdicts("func a() { phase = .busy; isBusy = true }"), [],
                       "another name is not the flag")
    }

    /// Every method of `source` that sets `busy = true`, by name, and whether a
    /// `guard` holding `!busy` stands before the first such line in it. The
    /// innermost method around the line owns it, so a closure inside a method
    /// belongs to that method.
    private static func methodsTakingTheFlag(in source: String) -> [(name: String, guarded: Bool)] {
        let code = SwiftSource.code(source)
        let characters = Array(code)
        let needle = Array("busy = true")
        let bodies = SwiftSource.functionBodies(in: code)
        var first: [Int: Int] = [:]
        var index = 0
        while index + needle.count <= characters.count {
            defer { index += 1 }
            guard Array(characters[index..<(index + needle.count)]) == needle else { continue }
            if index > 0 {
                let before = characters[index - 1]
                guard !(before.isLetter || before.isNumber || before == "_") else { continue }
            }
            guard let owner = SwiftSource.innermost(bodies, around: index),
                  let at = bodies.firstIndex(of: owner) else { continue }
            first[at] = min(first[at] ?? index, index)
        }
        return first.keys.sorted().map { at in
            let body = bodies[at]
            let before = String(characters[(body.open + 1)..<first[at]!])
            return (body.name,
                    before.range(of: #"guard\b[^{}]*!(self\.)?busy\b"#, options: .regularExpression) != nil)
        }
    }

    /// **The subject is a file that sends a removal, not a file called a view
    /// model.**
    ///
    /// It was `lastPathComponent.contains("ViewModel")` and it missed two doors,
    /// both found by an adversarial pass on 2026-08-20 and both real: the Trash
    /// offer's model lives in `TrashedLeftoversView.swift` and started a batch
    /// whatever was already in flight, and the Leftovers tab sends straight
    /// through `trashPaths`, which is the one route around
    /// `UninstallerViewModel.removeSelection`'s own guard. Naming the *type* was
    /// naming the place a removal is usually written rather than the thing that
    /// makes it dangerous.
    ///
    /// Three spellings: the Uninstaller's model calls its engine's `trashPaths`
    /// through `work`, its Leftovers tab and Trash offer call the model's
    /// `uvm.trashPaths`, and Disk, Duplicates and Leftovers call their engine's
    /// `trash` through `work`.
    private static func sendsARemoval(_ source: String) -> Bool {
        source.contains("work.trash(") || source.contains("work.trashPaths(")
            || source.contains("uvm.trashPaths(")
    }
}
