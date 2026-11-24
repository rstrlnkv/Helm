import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **A source the scan refused to walk does not leave the page saying «No
/// leftovers found».**
///
/// `isItsOwnPlace` is right to skip a directory that is not the directory it
/// names (`ADirectoryThatIsNotTheOneItNamesTests`). The refusal must also reach
/// the page: without a row, the scan comes back one source short with nothing
/// to mark the hole, `uncheckedCount` is zero, and on the ordinary Mac — where
/// the default filter shows leftovers only and an honest scan finds none — the
/// page draws `LeftoversEmpty.Reason.nothingFound`, «No leftovers found.» in
/// green, on a scan that did not look.
///
/// A scan holding rows it could not judge says `notEverythingChecked` instead,
/// with a question mark over it; a source nobody walked is the same fact one
/// step earlier. It needs no attacker — anybody who has symlinked a plug-in
/// folder onto another volume — and one of the eight is enough, because it is
/// the *filtered* list that has to be empty for this message, not the scan.
final class ASourceNobodyWalkedIsNotACleanMacTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// One installed app's settings file, so an honest scan of this Mac has a row
    /// to return and the emptiness on screen is the *filter's*, which is the
    /// ordinary shape of this page.
    private let installedApps = LeftoversFakeApps(ids: ["com.installed.vendor.app"])

    /// A Mac whose QuickLook folder is a link onto another volume, with a dead
    /// plug-in sitting in it.
    ///
    /// - Parameter redirected: false builds the same Mac with the folder where it
    ///   says it is — the control, without which «the scan found no leftovers»
    ///   would be true of both.
    private func files(redirected: Bool) -> LeftoversFakeFiles {
        var files = LeftoversFakeFiles()
        let elsewhere = "/Volumes/Plugins/QuickLook"
        let quickLook = "/Users/x/Library/QuickLook"
        if redirected { files.redirects[quickLook] = elsewhere }
        files.listing[redirected ? elsewhere : quickLook] = ["Gone.qlgenerator"]
        files.plists["\(redirected ? elsewhere : quickLook)/Gone.qlgenerator/Contents/Info.plist"] =
            PlistData(["CFBundleIdentifier": "com.gone.vendor.quicklook"])
        // And an ordinary settings file belonging to something still installed:
        // the row the honest scan returns, and the reason the *list* is empty
        // under the default filter rather than the scan.
        files.listing["/Users/x/Library/Preferences"] = ["com.installed.vendor.app.plist"]
        return files
    }

    private func scan(redirected: Bool) -> [StaleItem] {
        LeftoversScanner(home: home, files: files(redirected: redirected),
                         apps: installedApps, extensions: LeftoversFakeLoaded()).scan()
    }

    /// What the page puts over an empty list, from the counts this scan gives it.
    ///
    /// The default filter is «Leftovers», which is `status == .orphaned`
    /// (`LeftoversViewModel.matchingStatus`), and no kind is hidden until somebody
    /// hides one. `unchecked` is the whole scan's unjudged rows, as
    /// `LeftoversViewModel.uncheckedCount` counts them.
    private func message(over items: [StaleItem]) -> LeftoversEmpty.Reason? {
        LeftoversEmpty.reason(scanned: true,
                              visible: items.count { $0.status == .orphaned },
                              hiddenByKind: 0,
                              unchecked: items.count { !$0.status.judged })
    }

    /// **The control.** With the folder where it says it is, the dead plug-in is
    /// found and offered — so the fixture really does hold a leftover, and the
    /// redirected run below is a scan that missed one rather than a Mac with none.
    func testTheFolderReallyHoldsALeftoverWhenItIsWhereItSaysItIs() throws {
        let items = scan(redirected: false)
        let plugin = try XCTUnwrap(items.first { $0.kind == .plugin },
                                   "precondition: the plug-in folder holds a dead plug-in")

        XCTAssertEqual(plugin.identifier, "com.gone.vendor.quicklook")
        XCTAssertTrue(plugin.removable, "precondition: and Helm would offer to remove it")
        XCTAssertNil(message(over: items), "precondition: with a row to draw there is no message")
    }

    /// **The guard.** A dead plug-in behind a link and a Mac with nothing left
    /// over must not draw one screen.
    ///
    /// Asserted as a difference between two scans rather than against a named
    /// reason, so any channel that carries the refusal upward satisfies it; the
    /// honest side is pinned to `.nothingFound` first.
    func testAScanThatSkippedASourceDoesNotSayTheMacIsClean() {
        let blind = scan(redirected: true)
        let clean = scan(redirected: false).filter { $0.kind != .plugin }

        XCTAssertEqual(message(over: clean), .nothingFound,
                       "precondition: a Mac with nothing left over says so")
        // The dead plug-in, not «no plug-in row»: a scan that says out loud it
        // could not read the folder may well say so with a row.
        XCTAssertEqual(blind.count { $0.identifier == "com.gone.vendor.quicklook" }, 0,
                       "precondition: the redirected folder was not walked")

        XCTAssertNotEqual(message(over: blind), .nothingFound, """
            The scan skipped `~/Library/QuickLook` because it is a link, and the \
            page then drew «No leftovers found» under checkmark.circle — the same \
            screen, to the word and to the glyph, as a Mac with nothing left over. \
            Nothing in `[StaleItem]` says a folder went unread: the refusal is in \
            the log, by kind, where the person reading the green tick is not. This \
            module already refuses to draw that tick over rows it could not judge \
            (`LeftoversEmpty.notEverythingChecked`); a folder it could not open is \
            the same fact one step earlier, and the only one that leaves no row \
            behind to be counted.

            And the sentence carries no verb: `LeftoversEmpty.invites` gives \
            `nothingFound` no Scan button, so the screen is a statement about a \
            Mac nobody looked at with nothing on it to press.
            """)
    }

    /// **The same hole with no symbolic link in it, over the real port.**
    ///
    /// A directory that is not there and one this process may not read must not
    /// be one answer: the second is a permission, not «nothing in it».
    /// `LeftoversFilePort.contents` carries the third answer, `.refused`, as
    /// `exists` carries `nil` for «I could not tell».
    ///
    /// Run against a real directory at mode 000 rather than a fake, so the port
    /// itself is shown to say «this folder would not open».
    func testAFolderThisProcessMayNotReadIsNotAnEmptyFolder() throws {
        // Resolved: `$TMPDIR` is `/var/folders/…` and `/var` is a link, which
        // `isItsOwnPlace` would refuse — the scan would then skip every source and
        // pass this test for the wrong reason.
        let root = scratchDirectory("leftovers-unreadable").resolvingSymlinksInPath()
        let preferences = root.appendingPathComponent("Library/Preferences")
        try write("Library/Preferences/com.gone.vendor.app.plist", in: root, bytes: 512)
        // Ahead of the mode change and therefore run before the scratch drain,
        // which cannot remove what it cannot enumerate.
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: preferences.path)
        }

        let files = FileSystemLeftovers()
        let scanner = LeftoversScanner(home: root, files: files,
                                       apps: LeftoversFakeApps(ids: []),
                                       extensions: LeftoversFakeLoaded())
        // This Mac's own `/Library/LaunchAgents` and `/Library/LaunchDaemons` are
        // scanned too — they are absolute paths, not children of a home — and
        // whatever they hold is a fact about whoever is running this. Only the
        // tree this test built is read, or the reading is somebody's machine.
        func mine(_ items: [StaleItem]) -> [StaleItem] {
            items.filter { $0.path.hasPrefix(root.path + "/") }
        }
        XCTAssertEqual(mine(scanner.scan()).map(\.status), [.orphaned],
                       "precondition: readable, the folder holds one leftover")

        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: preferences.path)
        // `contents(of:)` rather than its `.entries`, and the difference is this
        // test's subject: the entries alone fold «refused» back into «empty».
        // `.refused` says the port really was turned away.
        XCTAssertEqual(files.contents(of: preferences), .refused,
                       "precondition: this process really cannot read the folder now")

        XCTAssertNotEqual(message(over: mine(scanner.scan())), .nothingFound, """
            `~/Library/Preferences` would not open, and the scan reported it as \
            holding nothing — so the page says «No leftovers found» about a \
            folder it never read. This is what the module's own permission note \
            warns about («a short list of leftovers looks exactly like a Mac with \
            none»), except that the note is drawn off a Full Disk Access probe and \
            this needs no TCC at all: a mode, an ACL, or a folder belonging to \
            somebody else does it.
            """)
    }
}
