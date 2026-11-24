import HelmRuntime
import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// A symlinked app bundle is not offered for removal. It lists like a bundle,
/// reads the target's `Info.plist` and weighs zero, and whether `trashItem`
/// moves the link or the target, both are defects
/// (Architecture/TheGates.md § The gates; `WorkspaceAppLister.leadsElsewhere`).
///
/// A `com.apple.` link (`Safari.app` into the Cryptexes) stays listed: its row
/// is no offer. Both halves are guarded here.
final class ALinkedBundleIsNotOfferedTests: XCTestCase {
    /// Resolved, so the link below is the only thing not canonical: `/var` is a
    /// link to `/private/var`, and every entry would otherwise answer "not canonical".
    private var home: URL!
    private var apps: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("linked-app").resolvingSymlinksInPath()
        apps = home.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        tailTheLog()
    }

    private var logged: [String] {
        loggedLines(UninstallerEngine.moduleID)
    }

    /// A bundle with an `Info.plist` and enough bytes in it to weigh.
    @discardableResult
    private func makeBundle(at url: URL, bundleID: String, name: String) throws -> URL {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try (["CFBundleIdentifier": bundleID, "CFBundleName": name] as NSDictionary)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x41, count: 32_768)
            .write(to: contents.appendingPathComponent("MacOS-binary"))
        return url
    }

    private func lister() -> WorkspaceAppLister {
        WorkspaceAppLister(home: home, fs: FMFileSystem())
    }

    /// `WorkspaceAppLister` reads `/Applications` too, so every assertion is about
    /// this test's own tree.
    ///
    /// Matched on the scratch folder's name, not its path: `contentsOfDirectory`
    /// answers `/private/var/…` for `/var/…`, and a prefix test would hide the
    /// whole fixture and pass the absence below vacuously.
    private func listedHere() -> [InstalledApp] {
        let mine = home.lastPathComponent
        return lister().installedApps().filter { $0.path.contains("/\(mine)/") }
    }

    // MARK: -

    /// The precondition: the link really is listed, carries the target's identity
    /// and weighs nothing. An assertion about an absence passes when the subject
    /// never happened.
    func test_the_link_is_there_and_weighs_nothing() throws {
        let target = try makeBundle(at: home.appendingPathComponent("Store/Target.app"),
                                    bundleID: "com.acme.target", name: "Target")
        let link = apps.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let entries = try FileManager.default.contentsOfDirectory(at: apps,
                                                                 includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.map(\.lastPathComponent), ["Linked.app"],
                       "the directory listing the lister runs does not return the link")
        let info = PropertyListFile.infoPlist(ofBundleAt: link)
        XCTAssertEqual(info?["CFBundleIdentifier"] as? String, "com.acme.target",
                       "the link does not carry the target's identity, so nothing would list it")
        XCTAssertEqual(FileWeight.allocated(of: link), 0,
                       "the link weighs something, so a zero-byte row is not the claim")
        XCTAssertGreaterThan(FileWeight.allocated(of: target), 0,
                             "the target weighs nothing either — the fixture is wrong")
    }

    /// The claim, with its control: the link is not offered, and the real bundle
    /// in the same folder still is. One test, since an empty answer proves
    /// nothing if the fixture was never seen.
    func test_a_linked_bundle_is_not_offered_and_a_real_one_beside_it_is() throws {
        try makeBundle(at: apps.appendingPathComponent("Real.app"),
                       bundleID: "com.acme.real", name: "Real")
        let target = try makeBundle(at: home.appendingPathComponent("Store/Target.app"),
                                    bundleID: "com.acme.target", name: "Target")
        try FileManager.default.createSymbolicLink(
            at: apps.appendingPathComponent("Linked.app"), withDestinationURL: target)

        let listed = listedHere()

        XCTAssertEqual(listed.map(\.bundleID), ["com.acme.real"], """
            a row offering to remove a link that weighs 0 bytes, where what the press moves — \
            the link or the 32 KB bundle behind it — is not a question this app has an answer to
            """)
        XCTAssertEqual(listed.map { ($0.path as NSString).lastPathComponent }, ["Real.app"],
                       "the row that is offered is not the bundle that is really there")
    }

    /// A refusal that leaves no trace reads like a folder with nothing in it.
    /// Counts only — a bundle id names somebody's habits.
    func test_a_linked_bundle_says_so_in_the_log() throws {
        let target = try makeBundle(at: home.appendingPathComponent("Store/Target.app"),
                                    bundleID: "com.acme.target", name: "Target")
        try FileManager.default.createSymbolicLink(
            at: apps.appendingPathComponent("Linked.app"), withDestinationURL: target)

        _ = listedHere()

        XCTAssertTrue(logged.contains { $0.contains("linked") }, """
            an app the person can see in Finder is missing from the list with nothing anywhere \
            saying why: \(logged)
            """)
        XCTAssertFalse(logged.contains { $0.contains("com.acme.target") },
                       "and the line must not name the software: \(logged)")
    }

    /// The exception: a `com.apple.` link's row is not an offer (no checkbox, the
    /// id refused at the model), so it stays listed.
    func test_a_linked_system_bundle_is_still_listed() throws {
        let target = try makeBundle(at: home.appendingPathComponent("Cryptex/Safari.app"),
                                    bundleID: "com.apple.Safari", name: "Safari")
        try FileManager.default.createSymbolicLink(
            at: apps.appendingPathComponent("Safari.app"), withDestinationURL: target)

        let listed = listedHere()

        XCTAssertEqual(listed.map(\.bundleID), ["com.apple.Safari"], """
            the row that says «System app» over an app macOS ships as a link into a cryptex is \
            gone from the list, and the person can still see the app in Finder
            """)
        XCTAssertTrue(SystemApp.isSystem(bundleID: "com.apple.Safari"),
                      "and the reason it may stay is that nothing can tick it")
    }

    /// `installedBundleIDs()` is not an offer but the evidence `LeftoverOwnership`
    /// and `OrphanDetector` weigh. An app reached through a link is installed, so
    /// its id stays, or every file named after it would become an orphan.
    func test_the_id_behind_a_link_still_counts_as_installed() throws {
        let target = try makeBundle(at: home.appendingPathComponent("Store/Target.app"),
                                    bundleID: "com.acme.target", name: "Target")
        try FileManager.default.createSymbolicLink(
            at: apps.appendingPathComponent("Linked.app"), withDestinationURL: target)

        XCTAssertTrue(lister().installedBundleIDs().contains("com.acme.target"),
                      "the files of an app that is installed became orphans")
    }

    // MARK: - The name a row carries

    private func writeBundle(_ name: String, plist: [String: Any]) throws {
        let contents = apps.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
    }

    /// The display name beats the bundle name, and a plist with neither falls back
    /// to the folder's name rather than to an empty row.
    func test_the_row_name_is_display_name_then_bundle_name_then_folder_name() throws {
        try writeBundle("Folder1", plist: ["CFBundleIdentifier": "com.acme.one",
                                           "CFBundleDisplayName": "Shown", "CFBundleName": "Short"])
        try writeBundle("Folder2", plist: ["CFBundleIdentifier": "com.acme.two", "CFBundleName": "Short"])
        try writeBundle("Folder3", plist: ["CFBundleIdentifier": "com.acme.three"])

        let names = Dictionary(uniqueKeysWithValues: listedHere().map { ($0.bundleID, $0.name) })

        XCTAssertEqual(names["com.acme.one"], "Shown")
        XCTAssertEqual(names["com.acme.two"], "Short")
        XCTAssertEqual(names["com.acme.three"], "Folder3")
    }

    /// A bundle whose plist has no identifier, or an empty one, is not a row: an
    /// app without an id cannot be told from another by anything the engine keeps.
    func test_a_bundle_without_an_identifier_is_not_listed() throws {
        try writeBundle("NoId", plist: ["CFBundleName": "NoId"])
        try writeBundle("EmptyId", plist: ["CFBundleIdentifier": "", "CFBundleName": "EmptyId"])
        try writeBundle("Fine", plist: ["CFBundleIdentifier": "com.acme.fine"])

        XCTAssertEqual(listedHere().map(\.bundleID), ["com.acme.fine"])
    }

    // MARK: - The Trash's readability

    /// A missing and an empty Trash are readable; one that will not open is not.
    func test_the_trash_is_readable_when_missing_or_empty_and_not_when_it_will_not_open() throws {
        XCTAssertTrue(lister().trashIsReadable(), "a missing Trash is a Trash with nothing in it")
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        XCTAssertTrue(lister().trashIsReadable())
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: trash.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: trash.path) }
        XCTAssertFalse(lister().trashIsReadable(), "an unopenable Trash was reported readable")
    }
}
