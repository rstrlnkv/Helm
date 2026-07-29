import XCTest
@testable import Module_Uninstaller_Engine

/// `LeftoverMatcher` builds every candidate by pasting a bundle id or a display
/// name onto a shared `~/Library` folder, and the review screen arrives with
/// what `UninstallPlan.defaultSelection` returns already ticked.
/// So a candidate that resolves to the shared folder itself, or walks out of it,
/// is one click away from the Trash. These pin the two invariants that keep that
/// from happening: a candidate is always strictly *inside* its kind folder, and
/// a glob is always anchored to something the app actually owns.
///
/// The names here are not invented: `CFBundleDisplayName` and `CFBundleName` are
/// free-form plist strings. `WorkspaceAppLister.installedApps()` takes the first
/// one that casts to `String` — an empty string casts fine — and only the bundle
/// id is checked for emptiness.
final class LeftoverMatcherHostileNamesTests: XCTestCase {
    private let lib = URL(fileURLWithPath: "/Users/x/Library")

    private func candidates(id: String, name: String) -> [LeftoverMatcher.Candidate] {
        LeftoverMatcher.candidates(bundleID: id, appName: name, library: lib)
    }

    /// Trap: `URL.appendingPathComponent("")` returns the parent unchanged —
    /// "Application Support" + "" is "Application Support". An app shipping
    /// `CFBundleDisplayName = ""` therefore claims the whole shared folder (and
    /// the whole shared Logs folder) as its own leftover, `fs.exists` confirms
    /// it, and the row arrives pre-selected with every other app's data in it.
    func testEmptyAppNameNeverTargetsAWholeLibraryFolder() {
        let paths = candidates(id: "com.acme.tool", name: "").map(\.url.path)
        XCTAssertFalse(paths.contains("/Users/x/Library/Application Support"),
                       "an empty display name claimed the shared folder: \(paths)")
        XCTAssertFalse(paths.contains("/Users/x/Library/Logs"),
                       "an empty display name claimed the shared folder: \(paths)")
    }

    /// The structural form of the same rule, so a new candidate line cannot
    /// reintroduce it under another kind: every candidate lives at least two
    /// components below `~/Library` — one for the kind folder, one for the app's
    /// own entry inside it. Exactly one component below IS a shared folder.
    func testEveryCandidateSitsAtLeastTwoLevelsBelowTheLibrary() {
        for (id, name) in [("com.acme.tool", ""), ("", "Tool"), ("", ""),
                           ("com.acme.tool", "Tool")] {
            for c in candidates(id: id, name: name) {
                let relative = c.url.path.dropFirst(lib.path.count)
                let parts = relative.split(separator: "/")
                XCTAssertGreaterThanOrEqual(
                    parts.count, 2,
                    "id=\(id.debugDescription) name=\(name.debugDescription) produced \(c.url.path)")
            }
        }
    }

    /// Trap: the same joining is done with no sanitising, so a name carrying a
    /// path separator escapes the folder it was meant to scope. `FileManager`
    /// resolves `..` before answering `fileExists`, so the escape is invisible
    /// to the engine's existence filter and `trashItem` acts on the resolved path.
    func testNoCandidateWalksOutOfTheLibrary() {
        for name in ["../../..", "..", "../Preferences"] {
            for c in candidates(id: "com.acme.tool", name: name) {
                XCTAssertFalse(c.url.pathComponents.contains(".."),
                               "name \(name.debugDescription) produced \(c.url.path)")
                XCTAssertTrue(c.url.standardizedFileURL.path.hasPrefix(lib.path + "/"),
                              "name \(name.debugDescription) escaped to \(c.url.standardizedFileURL.path)")
            }
        }
    }

    /// Trap: the sibling of `testPrefixGlobsStayScopedToTheId`, which only ever
    /// asked the question with a well-formed id. Every glob is `"\(id)*"` or
    /// `"*\(id)*"`; with an empty id those collapse to `*` and `**`, which
    /// `GlobMatch` matches against every sibling in Caches, Containers,
    /// Application Scripts, Group Containers — and `*.plist`, which is every
    /// LaunchAgent and every ByHost preference on the machine.
    func testEmptyBundleIdNeverProducesAMatchEverythingGlob() {
        let strangers = ["com.unrelated.app", "com.unrelated.app.plist", "Stranger"]
        for c in candidates(id: "", name: "Tool") where c.isGlob {
            let pattern = c.url.lastPathComponent
            for stranger in strangers {
                XCTAssertFalse(GlobMatch.matches(stranger, pattern: pattern),
                               "empty id produced pattern \(pattern.debugDescription), which swallows \(stranger)")
            }
        }
    }

    /// Positive control: the same assertions must hold — and be non-vacuous —
    /// for a well-formed app, so a future guard that returns nothing at all
    /// cannot make the tests above pass by emptiness.
    func testWellFormedInputStillProducesScopedCandidates() {
        let all = candidates(id: "com.acme.tool", name: "Tool")
        XCTAssertFalse(all.isEmpty)
        XCTAssertTrue(all.contains { $0.isGlob })
        for c in all where c.isGlob {
            XCTAssertFalse(GlobMatch.matches("com.unrelated.app", pattern: c.url.lastPathComponent))
        }
        for c in all {
            XCTAssertTrue(c.url.path.hasPrefix(lib.path + "/"))
            XCTAssertFalse(c.url.pathComponents.contains(".."))
        }
    }
}
