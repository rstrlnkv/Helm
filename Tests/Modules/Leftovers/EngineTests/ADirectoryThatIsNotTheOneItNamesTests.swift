import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **A scanned directory that is a symbolic link redirects the whole scan, and the
/// row shows the spelling the file does not have.**
///
/// `LeftoversScanner` enumerates seven directories it is compiled with — three
/// launch folders, `~/Library/Preferences`, four plug-in folders — and never asks
/// whether the directory it got is the one it named. `DirectoryListing.children`
/// hands back the contents of wherever the name leads, and the item's `path` is
/// then `dir.appendingPathComponent(name)`: the *false* spelling, which is what the
/// row draws and what «Show in Finder» opens.
///
/// Four of those directories do not exist on a stock install, so creating one as a
/// link needs no privilege at all — and the ordinary-mistake version of this is
/// anybody who has ever symlinked a plug-in folder onto another volume.
///
/// `RemovableScope` resolves ancestors, so the documented escape into `~/Documents`
/// is closed; what it still permits is anything under `~/Library` and anything
/// ending in `.app` wherever it lives. So the redirected target is enumerated,
/// judged, shown under a name it does not have, ticked by «Select all» and moved to
/// the Trash — a process with no Full Disk Access of its own borrowing Helm's to
/// reach another app's container.
///
/// The two tests below are the two halves of the same escape, and the second is the
/// reason the fix is not `isSymbolicLinkKey`: a link at `~/Library` redirects
/// `~/Library/QuickLook` without `~/Library/QuickLook` being a link.
///
/// **What «not scanned» is asserted over.** These two read `items == []` until the
/// refusal grew a voice: a source the scan will not walk now comes back as one row
/// standing for the *folder* — `ItemStatus.sourceRedirected`, unjudged, offering
/// nothing — because a refusal that reached only the log left the page drawing «No
/// leftovers found» under a green check over a folder nobody opened
/// (`ASourceNobodyWalkedIsNotACleanMacTests`). So what is asserted is the thing
/// this file is about, and it is the stronger reading of the two: **nothing from
/// behind the link is in the list**, and what is there says the folder went
/// unread rather than standing in for a file.
///
/// The last group is the same question put to the real port over a real folder,
/// about a spelling and not a link: `isItsOwnPlace` takes a source as its own place
/// when resolving it leaves the string as it was, so a string that is not the
/// spelling of the place it names — a doubled separator, a name in another case
/// below a regular file — has to come back changed, whether or not the kernel can
/// open it.
final class ADirectoryThatIsNotTheOneItNamesTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    private func scan(_ files: LeftoversFakeFiles) -> [StaleItem] {
        LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                         extensions: LeftoversFakeLoaded()).scan()
    }

    /// A plug-in folder pointed at another app's container, holding one bundle.
    private func filesWithARedirectedPlugInFolder() -> LeftoversFakeFiles {
        var files = LeftoversFakeFiles()
        files.redirects["/Users/x/Library/QuickLook"] =
            "/Users/x/Library/Containers/com.victim.app/Data"
        files.listing["/Users/x/Library/Containers/com.victim.app/Data"] = ["Victim.app"]
        files.plists["/Users/x/Library/Containers/com.victim.app/Data/Victim.app/Contents/Info.plist"] =
            PlistData(["CFBundleIdentifier": "com.victim.app.helper"])
        return files
    }

    /// **The finding.** The source is a link, and the scan follows it.
    func testASourceThatIsALinkIsNotScanned() {
        let items = scan(filesWithARedirectedPlugInFolder())

        XCTAssertEqual(items.filter { !$0.status.isSource }, [], """
            the scan followed `~/Library/QuickLook` to \
            `~/Library/Containers/com.victim.app/Data` and came back with \
            \(items.map { "\($0.path) status=\($0.status.rawValue) removable=\($0.removable)" }) — \
            a row for a file in another app's container, spelled as if it sat in the plug-in \
            folder, which is what «Show in Finder» opens and what the checkbox trashes. A \
            directory that is a link is not the directory it names, and a scan source cannot be \
            taken on the strength of its spelling.
            """)
        // The one row that is allowed is the folder saying it went unread, and it
        // stands for the source as it is spelled — never for what the link leads to.
        XCTAssertEqual(items.map(\.path), ["/Users/x/Library/QuickLook"])
        XCTAssertEqual(items.map(\.status), [.sourceRedirected])
        XCTAssertFalse(items.contains { $0.removable || $0.canToggle || $0.writable })
    }

    /// And the same escape one component up, which is why the question is about the
    /// whole path. `~/Library/QuickLook` is not a link here; `~/Library` is.
    func testASourceUnderARedirectedAncestorIsNotScannedEither() {
        var files = LeftoversFakeFiles()
        files.redirects["/Users/x/Library"] = "/Volumes/Elsewhere/Library"
        files.listing["/Volumes/Elsewhere/Library/Preferences"] = ["com.gone.vendor.app.plist"]

        let items = scan(files)

        XCTAssertEqual(items.filter { !$0.status.isSource }, [], """
            `~/Library` is the link and `~/Library/Preferences` is an ordinary directory name \
            under it, so a check on the source's own last component says nothing — and the scan \
            listed \(items.map(\.path)) from /Volumes/Elsewhere. This is the ancestor case \
            `PathCanonical` exists for, one layer above the removal gate.
            """)
        // Six of the seven sources are under the redirected `~/Library`, and each
        // says so on its own row: nothing here is a file, and every one of them is
        // counted as unchecked rather than as a Mac with nothing left over.
        XCTAssertEqual(items.count { $0.status == .sourceRedirected }, 6)
        XCTAssertFalse(items.contains(where: \.status.judged))
    }

    /// **The control, without which both assertions above hold for a scanner that
    /// finds nothing.** The same fixtures with the redirect taken out have to come
    /// back with the rows.
    func testTheSameDirectoriesAreStillScannedWhenTheyAreThemselves() throws {
        var files = filesWithARedirectedPlugInFolder()
        files.redirects = [:]
        files.listing["/Users/x/Library/QuickLook"] = ["Gone.qlgenerator"]
        files.plists["/Users/x/Library/QuickLook/Gone.qlgenerator/Contents/Info.plist"] =
            PlistData(["CFBundleIdentifier": "com.gone.vendor.quicklook"])

        let item = try XCTUnwrap(scan(files).first { $0.kind == .plugin })

        XCTAssertEqual(item.path, "/Users/x/Library/QuickLook/Gone.qlgenerator")
        XCTAssertTrue(item.removable, "the module's own job must survive the fix")
    }

    /// One redirected source is not the whole scan: the other six directories are
    /// separate questions, and a person whose plug-in folder is a link still wants
    /// to know about their launch agents.
    func testARedirectedSourceDoesNotSilenceTheRest() throws {
        var files = filesWithARedirectedPlugInFolder()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.gone.vendor.agent.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.gone.vendor.agent.plist"] =
            PlistData(["Label": "com.gone.vendor.agent",
                       "Program": "/Applications/Gone.app/Contents/MacOS/agent"])

        let items = scan(files)
        let judged = items.filter { !$0.status.isSource }

        XCTAssertEqual(judged.map(\.path),
                       ["/Users/x/Library/LaunchAgents/com.gone.vendor.agent.plist"])
        XCTAssertEqual(try XCTUnwrap(judged.first).status, .orphaned)
        // And the redirected folder is still reported, in the row that says the
        // scan did not read it — «the rest was scanned» must not become «the one
        // that was not went quiet».
        XCTAssertEqual(items.filter { $0.status.isSource }.map(\.path),
                       ["/Users/x/Library/QuickLook"])
    }

    // MARK: - The spelling, not the link

    /// A scratch folder put through `URL.resolvingSymlinksInPath()` first, as
    /// `PathCanonical.followingEveryLink` puts what it resolves, so that no
    /// answer differs from a typed string by a `/private` in front of `/var`.
    private func canonicalScratch() -> URL {
        scratchDirectory("leftovers-spelling").resolvingSymlinksInPath()
    }

    private func lstatError(_ path: String) -> Int32 {
        var info = stat()
        return lstat(path, &info) == 0 ? 0 : errno
    }

    /// What the shipping port answers for `typed`, compared with it by bytes.
    private func portKeepsTheSpelling(_ typed: String) -> (kept: Bool, answer: String) {
        let url = URL(fileURLWithPath: typed)
        XCTAssertTrue(url.path.utf8.elementsEqual(typed.utf8),
                      "premise: the URL changed the spelling before the port saw it: \(url.path)")
        let answer = FileSystemLeftovers().resolvingSymlinks(url).path
        return (answer.utf8.elementsEqual(typed.utf8), answer)
    }

    /// **A doubled separator in front of a plug-in folder that is not there.**
    /// `Library//QuickLook` is not how the place `Library/QuickLook` is spelled,
    /// and a source typed that way is not the directory it names.
    func testADoubledSeparatorBeforeAnAbsentFolderIsNotItsOwnPlace() throws {
        let scratch = canonicalScratch()
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("Library"),
                                                withIntermediateDirectories: true)
        let typed = scratch.path + "/Library//QuickLook"
        XCTAssertEqual(lstatError(typed), ENOENT, "premise: the folder is absent")

        let (kept, answer) = portKeepsTheSpelling(typed)

        XCTAssertFalse(kept, """
            the port handed `\(typed)` back letter for letter. A doubled separator is not \
            the spelling of the place, and a source typed that way is not its own place.
            """)
        XCTAssertNotEqual(answer, "", "premise: the port answered something")
    }

    /// **A doubled separator inside the part of the path that is not there.**
    /// The same spelling one level further down: `Library` is a folder, `Nope`
    /// and `QuickLook` are absent, and the string has two separators between
    /// them.
    func testADoubledSeparatorInsideAnAbsentTailIsNotItsOwnPlace() throws {
        let scratch = canonicalScratch()
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("Library"),
                                                withIntermediateDirectories: true)
        let typed = scratch.path + "/Library/Nope//QuickLook"
        XCTAssertEqual(lstatError(typed), ENOENT, "premise: neither folder is there")

        let (kept, answer) = portKeepsTheSpelling(typed)

        XCTAssertFalse(kept, """
            the port handed `\(typed)` back letter for letter. A doubled separator is not \
            the spelling of the place, whether or not the folders after it are there.
            """)
        XCTAssertNotEqual(answer, "", "premise: the port answered something")
    }

    /// **A name in another case below a regular file.** The volume reads
    /// `FILE` as `file`, so `FILE/missing` is a name below a file and the kernel
    /// answers `ENOTDIR`; the place that spelling is a variant of is
    /// `file/missing`, and a string that differs from it is not its own place.
    func testANameInAnotherCaseBelowARegularFileIsNotItsOwnPlace() throws {
        let scratch = canonicalScratch()
        try Data("x".utf8).write(to: scratch.appendingPathComponent("file"))
        let typed = scratch.path + "/FILE/missing"
        try XCTSkipUnless(lstatError(scratch.path + "/FILE") == 0,
                          "this volume tells FILE from file, and the string is then another place")
        XCTAssertEqual(lstatError(typed), ENOTDIR, "premise: a name below a regular file")

        let (kept, answer) = portKeepsTheSpelling(typed)

        XCTAssertFalse(kept, """
            the port handed `\(typed)` back letter for letter, though `FILE` is the file \
            called `file` and the string is not the spelling of the place it names.
            """)
        XCTAssertNotEqual(answer, "", "premise: the port answered something")
    }

    /// **The control: a source that is its own place stays so.** The same folder
    /// as the first row, spelled with one separator and absent: nothing in the
    /// string differs from the place, so the port hands it back. Without this the
    /// rows above hold for a port that changes every string it is given.
    func testAnAbsentFolderSpelledAsItIsIsItsOwnPlace() throws {
        let scratch = canonicalScratch()
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("Library"),
                                                withIntermediateDirectories: true)
        let typed = scratch.path + "/Library/QuickLook"
        XCTAssertEqual(lstatError(typed), ENOENT, "premise: the folder is absent")

        let (kept, answer) = portKeepsTheSpelling(typed)

        XCTAssertTrue(kept, "the port changed `\(typed)` into `\(answer)`")
    }
}
