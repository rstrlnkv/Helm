import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **A source that is a symbolic link passes «is this the directory it names»
/// whenever the link's target is not there yet — and then vanishes from the scan
/// entirely.**
///
/// `LeftoversScanner.isItsOwnPlace` is the whole defence against a planted source:
/// four of the seven directories the scan is compiled with do not exist on a stock
/// install, so any process running as the person can create one as a link and have
/// the enumeration happen wherever it points, under Helm's Full Disk Access, with
/// every row still spelling the folder that was compiled in. The guard is
///
///     files.resolvingSymlinks(directory).path == directory.path
///
/// and `FileSystemLeftovers.resolvingSymlinks` was `URL.resolvingSymlinksInPath()`,
/// which is `realpath` underneath. **`realpath` fails on a link whose target does
/// not exist**, and Foundation's answer to a failure is the path it was handed,
/// unchanged. So a link to a folder that is not there read as its own place.
///
/// The port now answers through `PathCanonical.followingEveryLink`, which follows the
/// leaf with `readlink` — the call that answers whether or not the target is there.
/// The Foundation reading has not changed and is not Helm's to change: it is measured
/// below off `URL.resolvingSymlinksInPath()` itself, and what this file guards is that
/// the port keeps answering something else.
///
/// The second half is what makes it silent rather than merely mislabelled.
/// `DirectoryListing.contents` calls `opendir`, which for that same link fails with
/// `ENOENT`, and `ENOENT` is read — correctly, for an ordinary path — as «there is
/// nothing there»: `.listed([])`, not `.refused`. A source that answers `.listed([])`
/// produces no row of any kind. So the planted link is not a redirected source, not
/// an unreadable source, and not an item: it is **nothing at all**, and with the
/// other sources honest the page draws «No leftovers found» under a green check —
/// the message `ASourceNobodyWalkedIsNotACleanMacTests` was written to stop, reached
/// by the one route that leaves no row behind to be counted.
///
/// And the planting is a two-step: the link is placed while its target does not
/// exist, so nothing is reported; the target is created afterwards, and from the
/// next scan onward the walk runs there while `isItsOwnPlace` — which resolves the
/// live link and now refuses it — is the only thing between them. Whether the
/// second step is ever taken, the first step is already invisible, and invisible is
/// what this guard exists not to be.
///
/// **Why the existing coverage does not reach it.**
/// `ADirectoryThatIsNotTheOneItNamesTests` drives `LeftoversFakeFiles.redirects`,
/// a dictionary lookup that resolves a link to a target whether or not the target
/// exists — so the fake can resolve what the real port cannot. That is a fake
/// *freer* than its port (CLAUDE.md § A fake can also be freer than the port), and
/// what it buys is a branch that is proven for a state production never reaches:
/// the dangling case has no fixture there, because in that fake there is no such
/// thing as dangling. This file therefore drives the real `FileSystemLeftovers` and
/// the real filesystem, and nothing else on this Mac.
final class ADanglingSourceIsNotItsOwnPlaceTests: XCTestCase {

    /// The real port, fenced to one directory.
    ///
    /// The finding is about `realpath` and `opendir`, so the port must be the
    /// shipping one; everything outside the scratch home must be invisible, or the
    /// scan reads `/Library/LaunchAgents` and `/Library/LaunchDaemons` and the
    /// answers become facts about whoever runs the suite. `.listed([])` for those
    /// two, which is what an absent directory answers anyway, and `resolvingSymlinks`
    /// hands the path straight back so they pass `isItsOwnPlace` and contribute no
    /// row.
    ///
    /// A local helper that does *more* than the shared one keeps its own body and
    /// calls it — CLAUDE.md § Test plumbing. It calls `FileSystemLeftovers` for
    /// everything it answers.
    private struct FilesUnder: LeftoversFilePort {
        let root: String
        private let real = FileSystemLeftovers()
        private func mine(_ path: String) -> Bool { path == root || path.hasPrefix(root + "/") }

        func isWritableDirectory(_ url: URL) -> Bool {
            mine(url.path) ? real.isWritableDirectory(url) : false
        }
        func resolvingSymlinks(_ url: URL) -> URL {
            mine(url.path) ? real.resolvingSymlinks(url) : url
        }
        func contents(of url: URL) -> DirectoryListing.Contents {
            mine(url.path) ? real.contents(of: url) : .listed([])
        }
        func exists(_ path: String) -> Bool? { mine(path) ? real.exists(path) : false }
        func size(_ url: URL) -> Int { mine(url.path) ? real.size(url) : 0 }
        func readPlist(_ url: URL) -> PlistData? { mine(url.path) ? real.readPlist(url) : nil }
    }

    /// A scratch home already canonical in every component.
    ///
    /// `$TMPDIR` is under `/var/folders/…` and `/var` is itself a link to
    /// `/private/var`, so an *unresolved* scratch path would make every source under
    /// it fail `isItsOwnPlace` for a reason that has nothing to do with this test —
    /// a red run that proves the harness rather than the code.
    private func canonicalHome(_ label: String) -> URL {
        scratchDirectory(label).resolvingSymlinksInPath()
    }

    private func scan(_ home: URL) -> [StaleItem] {
        LeftoversScanner(home: home, files: FilesUnder(root: home.path),
                         apps: LeftoversFakeApps(), extensions: LeftoversFakeLoaded()).scan()
    }

    private func link(_ relative: String, to target: String, in home: URL) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        return url
    }

    // MARK: - The mechanism, measured on this Mac

    /// **The three readings the defect is made of**: two facts about the system
    /// calls, taken off Foundation itself, and the demand they put on the shipping
    /// port.
    ///
    /// The Foundation half is green before the repair and after it — `realpath` and
    /// `opendir` are not Helm's to change. Read it off `URL.resolvingSymlinksInPath()`
    /// **directly**, never off `FileSystemLeftovers.resolvingSymlinks`: taken off the
    /// port, «unchanged» is a statement about Helm's own choice of call, and it froze
    /// the defect as the expected answer — that is how this file first went red at the
    /// repair rather than at the defect.
    ///
    /// The port's own reading is the opposite demand, and it is the one that is red
    /// against any port that answers a dangling link the way Foundation does.
    func testFoundationCannotFollowADanglingLinkAndTheShippingPortMust() throws {
        let home = canonicalHome("leftovers-dangling-port")
        let target = home.appendingPathComponent("elsewhere")
        let planted = try link("Library/QuickLook", to: target.path, in: home)
        let port = FileSystemLeftovers()

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: planted.path),
                       target.path, "the fixture really planted a symbolic link")
        XCTAssertFalse(FileManager.default.fileExists(atPath: planted.path),
                       "and its target is not there, which is what makes it dangling")

        XCTAssertEqual(planted.resolvingSymlinksInPath().path, planted.path, """
            `URL.resolvingSymlinksInPath()` handed back the spelling unchanged for a \
            path that is a symbolic link. `realpath` fails with ENOENT on a link whose \
            target is missing and Foundation falls back to the input — so a guard whose \
            whole question is «did resolving this change it» is told no.
            """)

        // The positive control for the reading above. Without it, «unchanged» would
        // also be what a fixture that planted no link at all produces, and what a
        // Foundation that resolved nothing anywhere would produce: it has to be shown
        // that this same call *does* change the spelling when it can follow the link.
        let liveTarget = home.appendingPathComponent("there")
        try FileManager.default.createDirectory(at: liveTarget, withIntermediateDirectories: true)
        let live = try link("Library/Spotlight", to: liveTarget.path, in: home)
        XCTAssertEqual(live.resolvingSymlinksInPath().path, liveTarget.path, """
            the same Foundation call on a link whose target does exist did not follow \
            it either, so «unchanged» above says nothing about dangling links — it says \
            the fixture or the call is not doing what this file assumes.
            """)

        XCTAssertEqual(port.contents(of: planted), .listed([]), """
            `opendir` fails with ENOENT for the same link, which \
            `DirectoryListing.contents` reads as «there is nothing there» rather than \
            `.refused` — so nothing downstream of the guard can recover the source: if \
            `isItsOwnPlace` passes the link, it produces no row at all, not even the \
            unread one.
            """)

        XCTAssertEqual(port.resolvingSymlinks(planted).path, target.path, """
            and this is what the port owes over Foundation's answer. \
            `LeftoversFilePort.resolvingSymlinks` is read by exactly one caller, \
            `LeftoversScanner.isItsOwnPlace`, and the question it is asked is «is this \
            directory the place it names». A port that hands the spelling back — which \
            is what `URL.resolvingSymlinksInPath()` alone does, measured above — answers \
            yes about a link somebody planted at a source, and with `opendir` reading \
            ENOENT as an empty folder the source then leaves no row of any kind. The \
            port must follow the link with `readlink`, which answers whether or not the \
            target is there, and name where it leads.
            """)
    }

    // MARK: - The finding

    /// **A planted link the scan cannot follow leaves no trace in the scan.**
    func testADanglingSourceIsReportedAsASourceThatIsNotItsOwnPlace() throws {
        let home = canonicalHome("leftovers-dangling")
        let planted = try link("Library/QuickLook",
                               to: home.appendingPathComponent("planted/QuickLook").path,
                               in: home)

        let items = scan(home)
        let row = items.first { $0.path == planted.path }

        XCTAssertEqual(row?.status, .sourceRedirected, """
            `\(planted.lastPathComponent)` is a symbolic link pointing outside the folder \
            it names, and the scan came back with \
            \(row == nil ? "no row for it at all" : "status \(row!.status.rawValue)").

            The whole scan returned \(items.count) row(s): \
            \(items.map { "\($0.path) [\($0.status.rawValue)]" }.joined(separator: ", ")).

            `isItsOwnPlace` passed it, because `realpath` cannot resolve a link whose \
            target does not exist and Foundation hands the spelling back; `opendir` then \
            failed with ENOENT, which `DirectoryListing` reads as an empty directory \
            rather than a refused one. Neither the redirect row nor the unread row is \
            produced, `LeftoversViewModel.uncheckedCount` counts nothing, and \
            `LeftoversEmpty.reason` answers `.nothingFound` — «No leftovers found» under \
            a green check, over a source somebody replaced with a link.
            """)
        XCTAssertNotNil(row?.leadsTo, """
            and a row that stands for a redirect has to name where it leads — the link's \
            destination, which `readlink` answers for a dangling link and `realpath` does \
            not. That string is the fact that tells the person whether the folder is \
            theirs; the row carries `\(row?.leadsTo ?? "nil")`.
            """)
    }

    /// The same planting on a source that *does* exist on a stock install — the
    /// person's own Preferences folder replaced by a link — because «four of the
    /// seven do not exist» is the easy case and not the only one.
    func testADanglingLinkOverAnOrdinarySourceIsAlsoReported() throws {
        let home = canonicalHome("leftovers-dangling-prefs")
        let planted = try link("Library/Preferences",
                               to: home.appendingPathComponent("planted/Preferences").path,
                               in: home)

        let row = scan(home).first { $0.path == planted.path }

        XCTAssertEqual(row?.status, .sourceRedirected,
                       "a link at ~/Library/Preferences with nothing on the other end of it "
                       + "yet reads as an ordinary empty Preferences folder: "
                       + "\(row.map { $0.status.rawValue } ?? "no row at all")")
    }

    // MARK: - Controls

    /// **The control that proves the harness reaches the guard.** The same planting
    /// with the target created first — a link the port *can* resolve — is reported
    /// today.
    ///
    /// Without it, a red result above would be indistinguishable from a fixture that
    /// never reached `isItsOwnPlace` at all: a wrong home, a source name that moved,
    /// a fenced port answering `.listed([])` for everything.
    func testALiveRedirectedSourceIsReportedToday() throws {
        let home = canonicalHome("leftovers-live-redirect")
        let target = home.appendingPathComponent("planted/QuickLook")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let planted = try link("Library/QuickLook", to: target.path, in: home)

        let row = scan(home).first { $0.path == planted.path }

        XCTAssertEqual(row?.status, .sourceRedirected,
                       "the guard does fire for a link it can follow, so the fixture, the "
                       + "fenced port and the source name are all wired")
        XCTAssertEqual(row?.leadsTo, target.path)
        XCTAssertEqual(row?.identifier, "QuickLook")
    }

    /// **The control that keeps the scan.** An ordinary directory with an ordinary
    /// file in it produces its item and no source row.
    ///
    /// So a repair cannot be «treat every source as redirected»: that would leave
    /// this red, and it is what a guard written from the failure message alone would
    /// most easily become.
    func testAnOrdinarySourceIsWalkedAndProducesNoSourceRow() throws {
        let home = canonicalHome("leftovers-ordinary-source")
        let plist = try write("Library/Preferences/com.nobody.leftover.plist", in: home)

        let items = scan(home)

        XCTAssertTrue(items.contains { $0.path == plist.path },
                      "the ordinary source was walked and its file is in the scan: "
                      + "\(items.map(\.path))")
        XCTAssertFalse(items.contains {
            $0.path == home.appendingPathComponent("Library/Preferences").path
        }, "and a directory that is the directory it names leaves no source row behind")
    }

    /// **The control on the fence.** Nothing outside the scratch home reaches the
    /// scan, so every reading above is about the fixture and not about this Mac's
    /// own `/Library/LaunchAgents`.
    func testTheScanReadsNothingOutsideTheScratchHome() throws {
        let home = canonicalHome("leftovers-fence")

        let outside = scan(home).filter { !$0.path.hasPrefix(home.path) }

        XCTAssertEqual(outside, [], "the fenced port answered for a path outside the fixture: "
                       + "\(outside.map(\.path))")
    }
}
