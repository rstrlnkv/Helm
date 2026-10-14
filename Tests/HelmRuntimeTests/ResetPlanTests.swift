import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// What a reset is allowed to remove. The gate exists because this is the one
/// feature in the app whose whole purpose is deletion, and the list it produces
/// is handed straight to the Trash.
final class ResetPlanTests: XCTestCase {
    private let home = "/Users/someone"

    func testItNamesTheTwoHelmDirectories() {
        let paths = ResetPlan.removablePaths(home: home)
        XCTAssertTrue(Set(paths).isSuperset(of: [
            "\(home)/Library/Application Support/Helm",
            "\(home)/Library/Logs/Helm",
        ]))
    }

    func testEveryPathItProducesIsInsideTheHome() {
        for path in ResetPlan.removablePaths(home: home) {
            XCTAssertTrue(path.hasPrefix(home + "/"), "\(path) escaped the home directory")
        }
    }

    /// The gate, asked the questions somebody would ask it by accident.
    func testItRefusesAnythingThatIsNotHelmsOwn() {
        for path in ["\(home)/Library", "\(home)/Documents", "\(home)",
                     "/", "/System/Library", "\(home)/Library/Application Support",
                     "\(home)/Library/Logs", "\(home)/Library/Application Support/Helmet",
                     "\(home)/Library/Application Support/Helm/../../Documents"] {
            XCTAssertFalse(ResetPlan.mayRemove(path, home: home),
                           "\(path) must not be removable by a reset")
        }
    }

    func testItAllowsHelmsOwnDirectoriesAndWhatIsInThem() {
        for path in ["\(home)/Library/Application Support/Helm",
                     "\(home)/Library/Application Support/Helm/Disk",
                     "\(home)/Library/Logs/Helm",
                     "\(home)/Library/Logs/Helm/helm.log"] {
            XCTAssertTrue(ResetPlan.mayRemove(path, home: home), "\(path) is Helm's own")
        }
    }

    /// Everything the plan produces must pass its own gate. A list and a gate
    /// that disagree is the shape of the bug this pair exists to prevent.
    func testThePlanAgreesWithItsOwnGate() {
        for path in ResetPlan.removablePaths(home: home) {
            XCTAssertTrue(ResetPlan.mayRemove(path, home: home))
        }
    }

    // MARK: The folders named for the bundle that is running

    /// A home that exists, with the `Caches` and `HTTPStorages` folders an app
    /// leaves in it for each identifier given, each holding a file and a
    /// folder. The gate is asked about paths that are there.
    private func homeWithTheFoldersAnAppLeaves(_ ids: [String]) throws -> String {
        let scratch = scratchDirectory("reset-plan").path
        for id in ids {
            for container in ["Caches", "HTTPStorages"] {
                let folder = "\(scratch)/Library/\(container)/\(id)"
                try FileManager.default.createDirectory(atPath: folder + "/fsCachedData",
                                                        withIntermediateDirectories: true)
                try "x".write(toFile: folder + "/Cache.db", atomically: true, encoding: .utf8)
            }
        }
        return scratch
    }

    /// The identifier this process runs as, printed so a run says whose
    /// folders the plan was asked for.
    private func runningBundleIdentifier() throws -> String {
        let id = try XCTUnwrap(Bundle.main.bundleIdentifier,
                               "this process has no bundle identifier")
        XCTAssertFalse(id.isEmpty, "this process has an empty bundle identifier")
        print("ResetPlanTests: the bundle identifier this process runs as is \(id)")
        return id
    }

    func testItNamesTheCachesAndTheHTTPStorageOfTheRunningBundle() throws {
        let id = try runningBundleIdentifier()
        let scratch = try homeWithTheFoldersAnAppLeaves([id])
        XCTAssertEqual(Set(ResetPlan.removablePaths(home: scratch)), [
            "\(scratch)/Library/Application Support/Helm",
            "\(scratch)/Library/Logs/Helm",
            "\(scratch)/Library/Caches/\(id)",
            "\(scratch)/Library/HTTPStorages/\(id)",
        ])
    }

    func testItAllowsTheRunningBundlesFoldersAndWhatIsInThem() throws {
        let id = try runningBundleIdentifier()
        let scratch = try homeWithTheFoldersAnAppLeaves([id])
        for path in ["\(scratch)/Library/Caches/\(id)",
                     "\(scratch)/Library/Caches/\(id)/Cache.db",
                     "\(scratch)/Library/Caches/\(id)/fsCachedData",
                     "\(scratch)/Library/HTTPStorages/\(id)",
                     "\(scratch)/Library/HTTPStorages/\(id)/Cache.db"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "\(path) was not made")
            XCTAssertTrue(ResetPlan.mayRemove(path, home: scratch),
                          "\(path) belongs to the running bundle, \(id)")
        }
    }

    /// What stands beside the two folders, or only looks like them. The
    /// siblings and the containers exist on the scratch home, so the answer
    /// for them is the gate's and not a missing file's.
    func testItRefusesWhatStandsBesideTheRunningBundlesFolders() throws {
        let id = try runningBundleIdentifier()
        let others = ["com.apple.Safari", id + ".other", "x" + id]
        let scratch = try homeWithTheFoldersAnAppLeaves([id] + others)
        var refused = ["\(scratch)/Library/Caches", "\(scratch)/Library/HTTPStorages",
                       "\(scratch)/Library", scratch,
                       "\(scratch)/Library/Caches/\(id)/../com.apple.Safari",
                       "\(scratch)/Library/Caches/\(id)/../../Application Support",
                       "\(scratch)/Library/HTTPStorages/\(id)/../com.apple.Safari/Cache.db",
                       // The other container, under the running bundle's name.
                       "\(scratch)/Library/Preferences/\(id)",
                       "\(scratch)/Library/Containers/\(id)"]
        for other in others {
            refused.append("\(scratch)/Library/Caches/\(other)")
            refused.append("\(scratch)/Library/Caches/\(other)/Cache.db")
            refused.append("\(scratch)/Library/HTTPStorages/\(other)")
            refused.append("\(scratch)/Library/HTTPStorages/\(other)/Cache.db")
        }
        for path in refused {
            XCTAssertFalse(ResetPlan.mayRemove(path, home: scratch),
                           "\(path) must not be removable by a reset run as \(id)")
        }
    }

    /// Helm Dev and the real Helm share a `Library` and differ by one word. A
    /// process that is neither (this one) names neither's folders; the only
    /// identifiers the plan may name are the running one's.
    func testItNamesNoOtherBuildOfHelm() throws {
        let id = try runningBundleIdentifier()
        let builds = ["com.helm.app", "com.helm.app.dev"].filter { $0 != id }
        let scratch = try homeWithTheFoldersAnAppLeaves([id] + builds)
        for build in builds {
            for container in ["Caches", "HTTPStorages"] {
                let folder = "\(scratch)/Library/\(container)/\(build)"
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder))
                XCTAssertFalse(ResetPlan.removablePaths(home: scratch).contains(folder),
                               "a reset run as \(id) lists \(folder)")
                XCTAssertFalse(ResetPlan.mayRemove(folder, home: scratch),
                               "a reset run as \(id) may remove \(folder)")
                XCTAssertFalse(ResetPlan.mayRemove(folder + "/Cache.db", home: scratch),
                               "a reset run as \(id) may remove inside \(folder)")
            }
        }
    }

    /// The list and the gate on a home that exists: every root the plan names
    /// is a folder there and passes the gate.
    func testEveryRootOfThePlanPassesTheGateOnAHomeThatExists() throws {
        let id = try runningBundleIdentifier()
        let scratch = try homeWithTheFoldersAnAppLeaves([id])
        for path in ["\(scratch)/Library/Application Support/Helm",
                     "\(scratch)/Library/Logs/Helm"] {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        let paths = ResetPlan.removablePaths(home: scratch)
        XCTAssertEqual(paths.count, 4, "the plan names \(paths.count) roots")
        for path in paths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "\(path) is not there")
            XCTAssertTrue(ResetPlan.mayRemove(path, home: scratch))
        }
    }

    // MARK: Whose identifier it is

    /// The identifier is a parameter, so Helm Dev and the real Helm each name
    /// their own two folders and neither names the other's, nor those of
    /// `com.helm.app.shot`, an identifier no build of Helm has.
    func testEachBuildOfHelmNamesItsOwnFoldersAndNobodyElses() throws {
        let builds = ["com.helm.app", "com.helm.app.dev", "com.helm.app.shot"]
        let scratch = try homeWithTheFoldersAnAppLeaves(builds)
        for build in builds {
            let own = ["Caches", "HTTPStorages"].map { "\(scratch)/Library/\($0)/\(build)" }
            let listed = ResetPlan.removablePaths(home: scratch, bundleIdentifier: build)
            XCTAssertEqual(Set(listed), Set(own + ["\(scratch)/Library/Application Support/Helm",
                                                   "\(scratch)/Library/Logs/Helm"]))
            XCTAssertEqual(listed.count, Set(listed).count, "a path is listed twice")
            for path in listed {
                XCTAssertTrue(ResetPlan.mayRemove(path, home: scratch, bundleIdentifier: build),
                              "the plan for \(build) names \(path) and its gate refuses it")
            }
            for other in builds where other != build {
                for container in ["Caches", "HTTPStorages"] {
                    for path in ["\(scratch)/Library/\(container)/\(other)",
                                 "\(scratch)/Library/\(container)/\(other)/Cache.db"] {
                        XCTAssertFalse(ResetPlan.mayRemove(path, home: scratch,
                                                           bundleIdentifier: build),
                                       "a reset run as \(build) may remove \(path)")
                    }
                }
            }
        }
    }

    /// An identifier that is not one name in a folder adds no root, and what
    /// it would have meant (the container itself, a folder above, another
    /// folder) stays refused.
    func testAnIdentifierThatIsNotOneNameNamesNothing() throws {
        let scratch = try homeWithTheFoldersAnAppLeaves(["a", "b"])
        let helms = ["\(scratch)/Library/Application Support/Helm",
                     "\(scratch)/Library/Logs/Helm"]
        let notNames: [String?] = [nil, "", ".", "..", "a/b", "../b", "a/", "/", "a/..", "/a",
                                   "a\u{0}b", "a\nb", "a\r\nb", "a\tb", "a\u{7f}b",
                                   "a/\u{301}b"]
        for id in notNames {
            XCTAssertEqual(ResetPlan.roots(home: scratch, bundleIdentifier: id), helms,
                           "\(String(describing: id)) added a root")
            XCTAssertEqual(ResetPlan.removablePaths(home: scratch, bundleIdentifier: id), helms)
            for path in ["\(scratch)/Library/Caches", "\(scratch)/Library/HTTPStorages",
                         "\(scratch)/Library/Caches/a", "\(scratch)/Library/Caches/a/Cache.db",
                         "\(scratch)/Library/HTTPStorages/b", "\(scratch)/Library/Caches/",
                         "\(scratch)/Library/Caches/\(id ?? "")"] {
                XCTAssertFalse(ResetPlan.mayRemove(path, home: scratch, bundleIdentifier: id),
                               "\(path) is removable for the identifier \(String(describing: id))")
            }
        }
    }

    /// A name that only looks like another: `a.b` is not `a`, and `a` is not
    /// `ab`, in either container.
    func testTheIdentifierIsAWholeComponent() throws {
        let scratch = try homeWithTheFoldersAnAppLeaves(["a", "a.b", "ab"])
        for other in ["a.b", "ab"] {
            for container in ["Caches", "HTTPStorages"] {
                XCTAssertFalse(ResetPlan.mayRemove("\(scratch)/Library/\(container)/\(other)",
                                                   home: scratch, bundleIdentifier: "a"))
                XCTAssertFalse(ResetPlan.mayRemove("\(scratch)/Library/\(container)/\(other)/Cache.db",
                                                   home: scratch, bundleIdentifier: "a"))
                XCTAssertFalse(ResetPlan.mayRemove("\(scratch)/Library/\(container)/a",
                                                   home: scratch, bundleIdentifier: other))
            }
        }
    }

    /// The same identifier under other folders of `Library` (`Preferences`,
    /// `Containers`, `Application Support`, `Logs`, `Saved Application State`)
    /// is refused, and so is a name that is the identifier with something after
    /// it or a letter in front, for a build of Helm asked by id, with the path
    /// in both spellings of the home.
    func testOtherFoldersUnderTheIdentifiersNameAreRefused() throws {
        let id = "com.helm.app"
        let lookalikes = [id + "X", id + ".dev", "x" + id, id + "-"]
        let scratch = try homeWithTheFoldersAnAppLeaves([id] + lookalikes)
        for container in ["Preferences", "Containers", "Application Support", "Logs", "Saved Application State"] {
            try FileManager.default.createDirectory(atPath: "\(scratch)/Library/\(container)/\(id)",
                                                    withIntermediateDirectories: true)
        }
        let other = scratch.hasPrefix("/private/") ? String(scratch.dropFirst("/private".count))
                                                   : "/private" + scratch
        try XCTSkipUnless(FileManager.default.fileExists(atPath: other),
                          "the scratch home has no second spelling here")
        for spelling in [scratch, other] {
            var refused = ["Preferences", "Containers", "Application Support", "Logs",
                           "Saved Application State"].map { "\(spelling)/Library/\($0)/\(id)" }
            for name in lookalikes {
                refused += ["Caches", "HTTPStorages"].flatMap {
                    ["\(spelling)/Library/\($0)/\(name)", "\(spelling)/Library/\($0)/\(name)/Cache.db"]
                }
            }
            for path in refused {
                XCTAssertFalse(ResetPlan.mayRemove(path, home: scratch, bundleIdentifier: id),
                               "\(path) is removable by a reset run as \(id)")
            }
            for container in ["Caches", "HTTPStorages"] {
                XCTAssertTrue(ResetPlan.mayRemove("\(spelling)/Library/\(container)/\(id)/Cache.db",
                                                  home: scratch, bundleIdentifier: id))
            }
        }
    }

    // MARK: What the kernel names

    /// The home spelled with `/private` in front and without it, which the
    /// kernel's name for a folder under `/var` does not leave to the caller.
    func testBothSpellingsOfPrivateAreOneHome() throws {
        let id = try runningBundleIdentifier()
        let scratch = try homeWithTheFoldersAnAppLeaves([id])
        let other = scratch.hasPrefix("/private/") ? String(scratch.dropFirst("/private".count))
                                                   : "/private" + scratch
        try XCTSkipUnless(FileManager.default.fileExists(atPath: other),
                          "the scratch home has no second spelling here")
        for (home, path) in [(scratch, other), (other, scratch)] {
            for tail in ["Library/Caches/\(id)", "Library/HTTPStorages/\(id)/Cache.db",
                         "Library/Application Support/Helm", "Library/Logs/Helm/helm.log"] {
                XCTAssertTrue(ResetPlan.mayRemove("\(path)/\(tail)", home: home),
                              "\(path)/\(tail) is Helm's own, asked of the home \(home)")
            }
            XCTAssertFalse(ResetPlan.mayRemove("\(path)/Library/Caches", home: home))
            XCTAssertFalse(ResetPlan.mayRemove(path, home: home))
        }
    }

    /// A link on the way is read where it leads. The link itself is a thing in
    /// the folder and goes with it; what is behind it is not Helm's.
    func testALinkOutOfTheFoldersIsReadWhereItLeads() throws {
        let id = try runningBundleIdentifier()
        let scratch = try homeWithTheFoldersAnAppLeaves([id])
        let elsewhere = "\(scratch)/Documents"
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
        try "mine".write(toFile: elsewhere + "/report.txt", atomically: true, encoding: .utf8)
        let inside = "\(scratch)/Library/Caches/\(id)/link"
        try FileManager.default.createSymbolicLink(atPath: inside, withDestinationPath: elsewhere)
        // The whole folder a link: `HTTPStorages/<id>` leads to Documents.
        let storage = "\(scratch)/Library/HTTPStorages/\(id)"
        try FileManager.default.removeItem(atPath: storage)
        try FileManager.default.createSymbolicLink(atPath: storage, withDestinationPath: elsewhere)

        XCTAssertTrue(ResetPlan.mayRemove(inside, home: scratch), "the link is in the folder")
        XCTAssertTrue(ResetPlan.mayRemove(storage, home: scratch), "the link is in the folder")
        for path in [inside + "/report.txt", inside + "/../Documents/report.txt",
                     storage + "/report.txt", storage + "/../Documents"] {
            XCTAssertFalse(ResetPlan.mayRemove(path, home: scratch),
                           "\(path) leads out of the folders and a reset may remove it")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere + "/report.txt"))
    }

    /// Every string the gate is asked goes into one of its two lists, and the
    /// paths in the running bundle's folders, a link there included, into
    /// `allowed`.
    func testTheGateAnswersWhatItJudged() throws {
        let id = try runningBundleIdentifier()
        let scratch = try homeWithTheFoldersAnAppLeaves([id])
        let elsewhere = "\(scratch)/Documents"
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
        let link = "\(scratch)/Library/Caches/\(id)/link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: elsewhere)

        let asked = ["\(scratch)/Library/Caches/\(id)", "\(scratch)/Library/HTTPStorages/\(id)/Cache.db",
                     link, link + "/report.txt", "\(scratch)/Library/Caches", elsewhere, "relative/path"]
        let (allowed, refused) = ResetPlan.gate(asked, home: scratch)
        XCTAssertEqual(allowed.map(\.asked), Array(asked[0...2]))
        XCTAssertEqual(refused.map(\.path), Array(asked[3...]))
        XCTAssertTrue(refused.allSatisfy { $0.reason == .outOfScope })
        for gated in allowed {
            XCTAssertEqual(gated.name, PathCanonical.reading(of: gated.asked).name,
                           "the gate judged one name and handed on another")
            XCTAssertTrue(ResetPlan.mayRemove(gated.name, home: scratch),
                          "the name \(gated.name) was judged and fails the gate it passed")
        }
    }
}
