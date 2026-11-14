import HelmTestSupport
import XCTest

/// A file that resolves one of the person's own folders has to ask whether this
/// is a test run.
///
/// `TestProcess` exists for exactly this question and says so at its
/// declaration: "asked by anything that would otherwise write into somebody's
/// real files". `HelmSupport` is the one place that resolves Application
/// Support, and it asks; `ScreenshotsState` (Documents) and Autopilot's
/// `SystemPorts` (Downloads) ask too. Duplicates' `KeepPolicy` (Downloads,
/// Desktop) does not ask: it only names `TestProcess` in a doc comment saying
/// so, and the per-file mention check below passes on that. A store that
/// skipped the question would read — and could delete — the person's own files
/// in a suite run, which is what `TheSuiteDoesNotReadTheUsersLastScanTests`
/// measured for the last Disk scan. That one names the file and the
/// measurement; this one is the family, so the next store to be written arrives
/// with the question already asked of it.
///
/// **Why the source and not the behaviour.** The behaviour can only be asked of
/// a store that already exists, from a target that can see it — nine engine
/// targets, and a guard per store is a guard somebody has to remember to write.
/// The rule is one line of source per site, so the source is where it can be
/// held for the whole tree at once.
///
/// The rule is coarse on purpose: it asks that the file *mentions* the question,
/// not that it answers it correctly. A file that names `TestProcess` and ignores
/// what it says is a defect this cannot see, and the two behaviour guards —
/// here and in Disk's engine tests — are what cover that.
final class StoresOfTheirsAskIfThisIsATestTests: XCTestCase {

    /// The folders that are the person's to keep, as `FileManager` spells them.
    /// Not `homeDirectoryForCurrentUser`, which the scope gates and the
    /// permission probe take as a *parameter* and never write into — a rule that
    /// reports those is a rule somebody switches off.
    private static let theirFolders = [
        ".applicationSupportDirectory", ".cachesDirectory",
        ".documentDirectory", ".libraryDirectory", ".downloadsDirectory",
    ]

    private struct Site {
        let file: String
        let line: Int
        let folder: String
    }

    // MARK: - The rule

    func testEverySiteThatResolvesOneOfTheirFoldersNamesTestProcess() throws {
        let sites = try self.sites()
        let unguarded = try sites.filter { site in
            try !RepoSource.text(of: site.file).contains("TestProcess")
        }
        XCTAssertEqual(unguarded.map { "\($0.file):\($0.line) \($0.folder)" }, [], """
            these resolve a folder of the person's without asking TestProcess.isRunning, so a \
            suite run lands in it: the log and the scan journal both ask, and the file that does \
            not is the one whose contents a test reads by accident.
            """)
    }

    /// The rule above passes on a file that names `TestProcess` anywhere, a
    /// doc comment included, so `HelmSupport` and `ScanJournal` could lose the
    /// branch and keep the comment that explains it. These two are held in code.
    func testTheTwoFoldersTheSuiteWouldOtherwiseWriteIntoAskInCode() throws {
        for file in ["Sources/HelmRuntime/HelmSupport.swift", "Sources/HelmRuntime/ScanJournal.swift"] {
            let asks = try RepoSource.lines(of: file).contains {
                RepoSource.code($0).contains("TestProcess.isRunning")
            }
            XCTAssertTrue(asks, "\(file) no longer asks TestProcess.isRunning in code")
        }
    }

    // MARK: - The scan itself, which is the half that goes quiet

    /// A `grep` that has stopped matching is a green test about nothing. The two
    /// known sites are the floor: `HelmSupport` is one of them and it is not going
    /// anywhere, so a reading below two means the walk, the extension filter or
    /// the spelling has broken rather than that the tree has improved.
    ///
    /// It named `ScanJournal` until the folder it resolved by hand moved to
    /// `HelmSupport`, which three places had spelled out — the journal reads it
    /// from there now, so the site is one file over. A floor naming a file is the
    /// price of a floor that cannot be satisfied by a scan reading nothing.
    func testTheScanIsStillReadingTheTree() throws {
        let sites = try self.sites()
        XCTAssertGreaterThanOrEqual(sites.count, 2, """
            \(sites.count) sites resolve one of the person's folders, where the tree has at least \
            two — the scan is not reading anything.
            """)
        XCTAssertTrue(sites.contains { $0.file.hasSuffix("HelmSupport.swift") },
                      "HelmSupport resolves Application Support and the scan did not find it")
    }

    /// And it reads code rather than prose — asserted on the line reader the scan
    /// itself uses, not on a filtered view of the tree.
    ///
    /// This has to be a fixture. No comment in `Sources/` spells one of these
    /// five today, so a test phrased as "the scan did not report a comment"
    /// passes whether or not the strip is wired in at all, and would go on
    /// passing after somebody removed it.
    func testTheReaderSeesCodeAndNotProse() {
        XCTAssertEqual(folders(in: "  let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)"),
                       [".cachesDirectory"])
        XCTAssertEqual(folders(in: "    // never .cachesDirectory — see ScanJournal"), [],
                       "an explanation was read as the offence it explains")
        XCTAssertEqual(folders(in: "    let url = home  // not .documentDirectory"), [],
                       "the comment tail of a code line was read as code")
    }

    // MARK: - Plumbing

    private func sites() throws -> [Site] {
        var out: [Site] = []
        for file in try RepoSource.swiftFiles(under: "Sources") {
            for (index, raw) in try RepoSource.lines(of: file).enumerated() {
                for folder in folders(in: raw) {
                    out.append(Site(file: file, line: index + 1, folder: folder))
                }
            }
        }
        return out
    }

    /// One line's worth of the scan, so the rule above and the walk below cannot
    /// drift apart.
    private func folders(in line: String) -> [String] {
        let code = RepoSource.code(line)
        return Self.theirFolders.filter { code.contains($0) }
    }
}
