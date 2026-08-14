import HelmRuntime
import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// **A symlinked app bundle was listed as installed and weighed at zero.**
///
/// Measured in a scratch directory: a link named `Linked.app` pointing at a real
/// bundle is returned by `contentsOfDirectory`, has `pathExtension == "app"`, and
/// `NSDictionary(contentsOf:)` reads the *target's* `Info.plist` through it — so
/// the row carried the real bundle id and the real name, while `FileWeight`
/// answered **0** bytes for it. `RemovableScope.isRemovable` allows it, so a
/// tick, a review and a press all went through.
///
/// What `FileManager.trashItem` does with such a leaf — move the link or move the
/// target — is deliberately unmeasured here: it needs a real write to somebody's
/// Trash, and **both answers are defects**. If it moves the link, «The app itself
/// — always removed» is false and the app is still installed with its containers
/// gone; if it moves the target, ARCHITECTURE § Removal scope's "the leaf is left
/// unresolved on purpose" is false. So the offer is withdrawn instead: an entry
/// whose path does not lead to itself is not listed among the apps this module
/// offers to remove.
///
/// Who has one: anyone whose apps arrive as links into `/Applications` or
/// `~/Applications` — nix-darwin, some cask layouts, hand-made links. **And every
/// Mac**: measured against the real `/Applications` on this one, 39 bundles of
/// which exactly one is a link — `Safari.app`, into
/// `/System/Volumes/Preboot/Cryptexes/App/…`. That is why the rule below has an
/// exception rather than being "no links": a `com.apple.` row carries no checkbox
/// and `setChecked` refuses the id, so it is not an offer to remove anything, and
/// withdrawing it would only take a visible row away from a person who can see
/// the app in Finder. Both halves are guarded here.
final class ALinkedBundleIsNotOfferedTests: XCTestCase {
    /// Resolved, so the *entries* under it are canonical and the link below is the
    /// only thing that is not. `$TMPDIR` is `/var/folders/…`, and `/var` is itself
    /// a link to `/private/var` — without this every entry in the scratch tree
    /// answers "not canonical" and the test would pass for a reason that has
    /// nothing to do with the subject.
    private var home: URL!
    private var apps: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("linked-app").resolvingSymlinksInPath()
        apps = home.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == UninstallerEngine.moduleID }
            .map(\.message)
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

    /// `WorkspaceAppLister` reads `/Applications` as well as the home it is given,
    /// so every assertion here is about this test's own tree. The owner's machine
    /// is read and left alone; it is not the subject.
    ///
    /// Matched on the scratch folder's own name and not on its path, because the
    /// two spellings of it are not the same string: `contentsOfDirectory` hands
    /// back `/private/var/folders/…` for a directory asked for as `/var/folders/…`.
    /// A prefix test filtered every row of this tree out, and the claim below —
    /// that a link is *not* listed — then passed with the whole fixture invisible.
    private func listedHere() -> [InstalledApp] {
        let mine = home.lastPathComponent
        return lister().installedApps().filter { $0.path.contains("/\(mine)/") }
    }

    // MARK: -

    /// The precondition, and the survey's own measurement: the link really is
    /// listed, really does carry the target's identity, and really weighs nothing.
    /// An assertion about an absence passes when the subject never happened.
    func test_the_link_is_there_and_weighs_nothing() throws {
        let target = try makeBundle(at: home.appendingPathComponent("Store/Target.app"),
                                    bundleID: "com.acme.target", name: "Target")
        let link = apps.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let entries = try FileManager.default.contentsOfDirectory(at: apps,
                                                                 includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.map(\.lastPathComponent), ["Linked.app"],
                       "the directory listing the lister runs does not return the link")
        let info = NSDictionary(contentsOf: link.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(info?["CFBundleIdentifier"] as? String, "com.acme.target",
                       "the link does not carry the target's identity, so nothing would list it")
        XCTAssertEqual(FileWeight.allocated(of: link), 0,
                       "the link weighs something, so a zero-byte row is not the claim")
        XCTAssertGreaterThan(FileWeight.allocated(of: target), 0,
                             "the target weighs nothing either — the fixture is wrong")
    }

    /// **The claim**, with its own control beside it: the link is not among the
    /// apps offered for removal, and the real bundle in the same folder still is.
    ///
    /// One test rather than two, because the control is what makes the claim mean
    /// anything — an empty answer proves nothing about the link if the fixture was
    /// never seen at all.
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

    /// **The exception, and it is Apple's own.** `/Applications/Safari.app` is a
    /// link on this Mac, and its row is not an offer: no checkbox is drawn and the
    /// id is refused at the model. So it stays listed, where the person can see
    /// it, and the rule above is about rows that offer a removal.
    func test_a_linked_system_bundle_is_still_listed() throws {
        let target = try makeBundle(at: home.appendingPathComponent("Cryptex/Safari.app"),
                                    bundleID: "com.apple.Safari", name: "Safari")
        try FileManager.default.createSymbolicLink(
            at: apps.appendingPathComponent("Safari.app"), withDestinationURL: target)

        let listed = listedHere()

        XCTAssertEqual(listed.map(\.bundleID), ["com.apple.Safari"], """
            the row that says «System» over an app macOS ships as a link into a cryptex is \
            gone from the list, and the person can still see the app in Finder
            """)
        XCTAssertTrue(SystemApp.isSystem(bundleID: "com.apple.Safari"),
                      "and the reason it may stay is that nothing can tick it")
    }

    /// **A different question, deliberately answered differently.**
    /// `installedBundleIDs()` is not an offer to remove anything — it is the
    /// evidence `LeftoverOwnership` and `OrphanDetector` weigh when they ask
    /// "is an app with this id still installed?". An app reached through a link
    /// is installed, so its id stays: dropping it would make every file named
    /// after it an orphan and offer *those* for removal instead.
    func test_the_id_behind_a_link_still_counts_as_installed() throws {
        let target = try makeBundle(at: home.appendingPathComponent("Store/Target.app"),
                                    bundleID: "com.acme.target", name: "Target")
        try FileManager.default.createSymbolicLink(
            at: apps.appendingPathComponent("Linked.app"), withDestinationURL: target)

        XCTAssertTrue(lister().installedBundleIDs().contains("com.acme.target"),
                      "the files of an app that is installed became orphans")
    }
}
