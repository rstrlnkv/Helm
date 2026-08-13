import Foundation
import HelmRuntime
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

        XCTAssertEqual(items, [], """
            the scan followed `~/Library/QuickLook` to \
            `~/Library/Containers/com.victim.app/Data` and came back with \
            \(items.map { "\($0.path) status=\($0.status.rawValue) removable=\($0.removable)" }) — \
            a row for a file in another app's container, spelled as if it sat in the plug-in \
            folder, which is what «Show in Finder» opens and what the checkbox trashes. A \
            directory that is a link is not the directory it names, and a scan source cannot be \
            taken on the strength of its spelling.
            """)
    }

    /// And the same escape one component up, which is why the question is about the
    /// whole path. `~/Library/QuickLook` is not a link here; `~/Library` is.
    func testASourceUnderARedirectedAncestorIsNotScannedEither() {
        var files = LeftoversFakeFiles()
        files.redirects["/Users/x/Library"] = "/Volumes/Elsewhere/Library"
        files.listing["/Volumes/Elsewhere/Library/Preferences"] = ["com.gone.vendor.app.plist"]

        let items = scan(files)

        XCTAssertEqual(items, [], """
            `~/Library` is the link and `~/Library/Preferences` is an ordinary directory name \
            under it, so a check on the source's own last component says nothing — and the scan \
            listed \(items.map(\.path)) from /Volumes/Elsewhere. This is the ancestor case \
            `PathCanonical` exists for, one layer above the removal gate.
            """)
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

        XCTAssertEqual(items.map(\.path), ["/Users/x/Library/LaunchAgents/com.gone.vendor.agent.plist"])
        XCTAssertEqual(try XCTUnwrap(items.first).status, .orphaned)
    }
}
