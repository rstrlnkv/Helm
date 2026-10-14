import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A removal gate is asked about a string, and the filesystem acts on an
/// object. Two gates, `RemovableScope` and `UserFileScope`, judge a name by
/// prefixes, depth and the `.app` suffix, and both take the name from one
/// reading of what the kernel says the string names
/// (`PathCanonical.readingForRemoval`). Five spellings that a judge of the
/// letters of a path could pass, each held here as refused:
///
/// - **a relative path.** It names an object only against the working
///   directory, which no gate is told. The reading gives a string that does
///   not start at `/` as typed no name, `~` included, both gates refuse it, and
///   `PathCanonical.resolvingAncestors` hands one back untouched.
/// - **the forbidden folder with its last component in another case.** The
///   boot volume is case-insensitive. The reading gives every level that is
///   there the case the disk holds; a last component that is no directory, a
///   tail that is not there and a place on a list that is not on this Mac keep
///   the case that was typed. Both gates compare component by component,
///   without regard to case, through `PathCanonical.isAtOrBelow`:
///   `RemovableScope` its `forbidden` list, `UserFileScope` its protected
///   prefixes, the home directory and `/Volumes`. The fold is
///   `.caseInsensitive` (`PathCanonical.isAtOrBelow` says why not
///   `lowercased()`). The rows below that ask a gate about a folder spelled
///   with a long s do not hold that choice: the folder is there, the reading
///   gives it the disk's spelling, and the comparison is handed no long s. The
///   row that holds the choice asks `PathCanonical.isAtOrBelow` itself, with
///   components that carry a long s
///   (`testThePredicateFoldsALongSAsTheVolumeDoesAndOnlyThat`).
/// - **a `/.vol/<device>/<inode>` path.** Under that prefix the kernel
///   answers for an object by its device and inode; nothing is mounted there,
///   and the rows below call the prefix the mount. Both gates refuse a path
///   whose first component left at the root is `.vol` in any case, the path
///   read left to right with each `.` dropped and each `..` popping the name
///   before it, asked of the string as typed before the kernel is asked and,
///   after, of the name the reading made of it less a `/private` in front
///   (`PathCanonical.beginsWithAKernelPrefix`, which asks the same of the two
///   prefixes below; `TheGatesTakeOneReadingOfTheObjectTests` holds the
///   prefix behind `/private`).
/// - **a `/.nofollow/<path>` or `/.resolve/<n>/<path>` path.** The kernel
///   answers either with the object `/<path>` names or with an error where the
///   prefix forbids the way there (a link in `<path>` under `/.nofollow`; some
///   numbers `n` whatever follows), and the path it returns for the object
///   keeps the prefix in front. Both gates refuse a path that begins so,
///   whatever the case of the prefix, read as above (each `.` dropped, each
///   `..` popping the name before it), and whatever follows it: a protected
///   prefix, the home directory, a top-level folder of the volume, and the
///   volume's root, which `/.nofollow/` and `/.resolve/<n>/` name.
/// - **a kernel prefix followed by `..`.** The kernel answers
///   `/.vol/<device>/<inode>` with the object and climbs that object's real
///   parents for each `..` after it, behind `/.nofollow` and `/.resolve/1` as
///   well; a number after `/.resolve` whose flags forbid `..` answers with an
///   error instead. When the whole string names an object that resolves,
///   Foundation puts the object's ordinary name where the mount and its `..`
///   stood and leaves `/.nofollow` or `/.resolve/1` in front of it. When the
///   last component is a link to nothing, or is not there, Foundation collapses
///   the `..` by the letters: as many of them as the prefix, the device and the
///   inode have components pop all of it, and what is left begins with an
///   ordinary name that is not the object's. Both gates refuse the string in
///   either case, because the prefix is read from the string as typed, before a
///   `..` after it can pop it, and whatever follows it. Repeated slashes in it,
///   and a `.` or a `..` in front of the prefix in a spelling that starts at
///   `/`, change nothing.
///
/// One more spelling is refused as a string the kernel takes for no path. A
/// file reference URL writes its object as `/.file/id=<volume>.<inode>`; the
/// kernel does not answer for that string, because `/.file` is a file, so the
/// reading gives it no name and both gates refuse it whatever it would name.
/// One test here holds that the protected objects stay refused when written
/// so, and `TheGatesTakeOneReadingOfTheObjectTests` holds the rest.
///
/// **How the subject is made real.** A relative path names an object only
/// against a working directory, and that is the process's, shared by every
/// test; no test here changes it. A relative spelling of an object that
/// exists is built the other way: as many `..` as the working directory is
/// deep, then the object's absolute path. The kernel resolves that against
/// whatever the directory is, to the same object the absolute spelling names,
/// and each test reads both identities (device and inode) before it asks the
/// gate anything. The literal `x/Foo.app`, `Applications/Utilities/X.app` and
/// `System/Applications/Mail.app` are asked as strings: what each names
/// depends on the working directory, and the test prints whether it exists
/// from there.
///
/// Where the kernel answers for a spelling, the test proves which object it
/// names before it asserts the gate's answer: by device and inode against the
/// other spelling's, or, in the row that re-cases a component above the last,
/// by existence and the path `resolvingAncestors` prints. A test whose subject
/// cannot be proved on the machine it runs on skips and says why, or fails
/// saying that nothing was asked. A spelling of the mount in another case,
/// through `.` or `..`, or through a link to `/` is a string a gate is asked
/// about whether or not the kernel answers for it: each such test prints what
/// `lstat` answered and asserts nothing about it, and proves its subject
/// through the literal `/.vol` spelling, which has to answer; the row whose
/// link points at that spelling asserts on what the kernel answered, because
/// that is its measurement. Each test that asks a gate prints one line per
/// spelling, tagged, with the gate's answer, so a run can be read without
/// opening the assertion; the row that asks the predicate alone prints
/// nothing.
///
/// The same holds for `/.nofollow` and `/.resolve/<n>` in another case,
/// through `.` or `..`, or through a link to `/`: the literal prefix has to
/// answer for the same object, and the string with the prefix changed is
/// asked whether or not it does. The row for a file reference path has no
/// kernel answer to read; it proves its subject through Foundation, whose
/// resource identifier for the string's URL has to equal the object's.
final class TheGatesRefuseAnObjectsOtherSpellingsTests: XCTestCase {

    // MARK: - Reading an object

    /// What the kernel calls an object: the device and the inode.
    private struct ObjectOnDisk: Equatable, CustomStringConvertible {
        let device: UInt32
        let inode: UInt64
        var description: String { "device \(device) inode \(inode)" }
    }

    /// The identity of what `path` names, or the system's reason it names
    /// nothing. `lstat` does not follow a final link; `stat` does, and that is
    /// the question about a `/.vol` spelling, which is answered for the object
    /// and not for a link to it.
    private func identity(of path: String, followingLinks: Bool = false)
    -> (object: ObjectOnDisk?, failure: String) {
        var info = stat()
        let status: Int32
        if followingLinks { status = stat(path, &info) } else { status = lstat(path, &info) }
        guard status == 0 else { return (nil, String(cString: strerror(errno))) }
        return (ObjectOnDisk(device: UInt32(bitPattern: info.st_dev),
                             inode: UInt64(info.st_ino)), "")
    }

    /// `/.vol/<device>/<inode>` for what `path` names, after the volume file
    /// system has answered for it with the same identity `lstat` gave the
    /// path. A Mac where it does not answer, or answers with another object,
    /// skips the test and prints what it printed.
    private func volfsSpelling(of path: String) throws -> String {
        let direct = identity(of: path)
        guard let object = direct.object else {
            throw XCTSkip("\(path) could not be read: \(direct.failure)")
        }
        let spelling = "/.vol/\(object.device)/\(object.inode)"
        let through = identity(of: spelling, followingLinks: true)
        print("[gates] volfs: \(path) is \(object); \(spelling) answers "
              + (through.object.map { "\($0)" } ?? "nothing (\(through.failure))"))
        guard through.object == object else {
            throw XCTSkip("\(spelling) does not name \(path) on this Mac: "
                          + (through.object.map { "it names \($0)" } ?? through.failure))
        }
        return spelling
    }

    /// A relative spelling of an absolute path: one `..` for each component of
    /// the working directory, then the path. Extra `..` at the root stay at the
    /// root, so the depth needs no more than the count.
    private func spellingRelativeToTheWorkingDirectory(of absolute: String) -> String {
        let depth = FileManager.default.currentDirectoryPath.split(separator: "/").count
        return String(repeating: "../", count: depth) + absolute.drop(while: { $0 == "/" })
    }

    /// Proves a relative spelling names the same object as the absolute one,
    /// from the working directory the process has. Skips when it does not.
    private func proveRelativeSpelling(_ relative: String, names absolute: String) throws {
        let cwd = FileManager.default.currentDirectoryPath
        let viaRelative = identity(of: relative)
        let viaAbsolute = identity(of: absolute)
        print("[gates] relative: \(relative.debugDescription) from \(cwd.debugDescription) is "
              + (viaRelative.object.map { "\($0)" } ?? "nothing (\(viaRelative.failure))")
              + "; \(absolute.debugDescription) is "
              + (viaAbsolute.object.map { "\($0)" } ?? "nothing (\(viaAbsolute.failure))")
              + "; fileExists(relative) = \(FileManager.default.fileExists(atPath: relative))")
        guard let object = viaAbsolute.object, viaRelative.object == object else {
            throw XCTSkip("\(relative.debugDescription) does not name \(absolute) from \(cwd)")
        }
    }

    /// A scratch directory standing in for the home directory, so the answer
    /// does not depend on whose Mac this is.
    private func scratchHome() -> URL { scratchDirectory("gate-spellings") }

    // MARK: - A relative path

    /// A bundle that exists, spelled relative to the working directory. The
    /// absolute spelling of the same object is a bundle the gate would remove;
    /// a relative one has no place to be judged from.
    func testARelativeSpellingOfABundleThatExistsIsRefused() throws {
        let home = scratchHome()
        let bundle = home.appendingPathComponent("x/Foo.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let relative = spellingRelativeToTheWorkingDirectory(of: bundle.path)
        try proveRelativeSpelling(relative, names: bundle.path)

        let answer = RemovableScope.isRemovable(relative, home: home.path)
        print("[gates] RemovableScope.isRemovable(\(relative.debugDescription)) = \(answer)")
        XCTAssertFalse(answer,
                       "a relative path of several components ending .app is removable: \(relative)")
    }

    /// A relative spelling that leads from the working directory to a bundle in
    /// `/System`. The absolute spelling is refused by `forbidden`; the relative
    /// one is refused before that compare is consulted, because the gate asks
    /// first that a path start at `/`.
    func testARelativeSpellingThatLeadsToABundleInSystemIsRefused() throws {
        let absolute = "/System/Applications/Mail.app"
        guard FileManager.default.fileExists(atPath: absolute) else {
            throw XCTSkip("\(absolute) is not on this Mac")
        }
        let relative = spellingRelativeToTheWorkingDirectory(of: absolute)
        try proveRelativeSpelling(relative, names: absolute)

        let home = scratchHome().path
        let control = RemovableScope.isRemovable(absolute, home: home)
        let answer = RemovableScope.isRemovable(relative, home: home)
        print("[gates] RemovableScope.isRemovable(\(absolute)) = \(control); "
              + "(\(relative.debugDescription)) = \(answer)")
        XCTAssertFalse(control, "the absolute spelling is the control, and it was removable")
        XCTAssertFalse(answer,
                       "a relative spelling of \(absolute) is removable: \(relative)")
    }

    /// The same for a bundle inside the one forbidden folder that sits inside
    /// an allowed root.
    func testARelativeSpellingThatLeadsToABundleInTheUtilitiesFolderIsRefused() throws {
        let folder = "/Applications/Utilities"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        guard let app = names.sorted().first(where: { $0.hasSuffix(".app") }) else {
            throw XCTSkip("\(folder) holds no .app on this Mac")
        }
        let absolute = folder + "/" + app
        let relative = spellingRelativeToTheWorkingDirectory(of: absolute)
        try proveRelativeSpelling(relative, names: absolute)

        let home = scratchHome().path
        let control = RemovableScope.isRemovable(absolute, home: home)
        let answer = RemovableScope.isRemovable(relative, home: home)
        print("[gates] RemovableScope.isRemovable(\(absolute.debugDescription)) = \(control); "
              + "(\(relative.debugDescription)) = \(answer)")
        XCTAssertFalse(control, "the absolute spelling is the control, and it was removable")
        XCTAssertFalse(answer,
                       "a relative spelling of \(absolute) is removable: \(relative)")
    }

    /// The three literal spellings, asked as strings. What each names depends
    /// on the working directory, and the line printed says whether it exists
    /// from there, so this proves what the gate answers to the string and not
    /// what a removal would do; the three tests above are the ones whose
    /// subject exists.
    func testRelativeSpellingsAreRefusedWhateverTheyWouldResolveTo() {
        let home = scratchHome().path
        for spelling in ["x/Foo.app", "Applications/Utilities/X.app", "System/Applications/Mail.app"] {
            let exists = FileManager.default.fileExists(atPath: spelling)
            let answer = RemovableScope.isRemovable(spelling, home: home)
            print("[gates] literal: RemovableScope.isRemovable(\(spelling.debugDescription)) = \(answer); "
                  + "fileExists from \(FileManager.default.currentDirectoryPath) = \(exists)")
            XCTAssertFalse(answer, "\(spelling.debugDescription) reached the gate as a removable path")
        }
    }

    // MARK: - The forbidden folder in another case

    /// `path` with its last component put through `transform`. Whether the
    /// result names the same object is for the caller to prove.
    private func recased(_ path: String, by transform: (String) -> String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent()
            .appendingPathComponent(transform(url.lastPathComponent)).path
    }

    /// The entries of `RemovableScope.forbidden`, read from the source: the
    /// list is private, and a hand-copied one would stop being the list the day
    /// the gate gains an entry.
    private func forbiddenEntries() throws -> [String] {
        let source = try RepoSource.text(of: "Sources/HelmRuntime/RemovableScope.swift")
        let opening = try XCTUnwrap(source.range(of: "private static let forbidden = ["),
                                    "the forbidden list is no longer declared that way")
        let closing = try XCTUnwrap(source[opening.upperBound...].firstIndex(of: "]"))
        let quoted = source[opening.upperBound..<closing]
            .split(separator: "\"", omittingEmptySubsequences: false)
        // Between the quotes: the odd-numbered pieces.
        let entries = quoted.indices.filter { $0 % 2 == 1 }.map { String(quoted[$0]) }
        XCTAssertFalse(entries.isEmpty, "no entry was read from the forbidden list")
        for entry in entries {
            XCTAssertTrue(entry.hasPrefix("/"), "\(entry.debugDescription) is not an absolute entry")
        }
        return entries
    }

    /// The volume is case-insensitive, or these tests have no subject.
    private func requireACaseInsensitiveVolume() throws {
        let original = identity(of: "/System").object
        let flipped = identity(of: "/system").object
        guard original != nil, original == flipped else {
            throw XCTSkip("/system does not name /System on this volume: it is case-sensitive")
        }
    }

    /// The folder itself, with its last component in another case.
    func testTheForbiddenFolderInAnotherCaseIsRefused() throws {
        try requireACaseInsensitiveVolume()
        let original = "/Applications/Utilities", spelling = "/Applications/utilities"
        let before = identity(of: original).object, after = identity(of: spelling).object
        print("[gates] case: \(original) is \(before.map { "\($0)" } ?? "nothing"); "
              + "\(spelling) is \(after.map { "\($0)" } ?? "nothing"); "
              + "fileExists = \(FileManager.default.fileExists(atPath: spelling))")
        guard before != nil, before == after else {
            throw XCTSkip("\(spelling) does not name \(original) on this Mac")
        }

        let answer = RemovableScope.isRemovable(spelling, home: scratchHome().path)
        print("[gates] RemovableScope.isRemovable(\(spelling)) = \(answer)")
        XCTAssertFalse(answer, "\(spelling) names the forbidden \(original) and is removable")
    }

    /// Every entry of the forbidden list that exists on this Mac, with its last
    /// component folded to lower case and to upper case. The list refuses
    /// each; an entry the gate would refuse without the list as well (it sits
    /// at the top level of the volume, or outside every root) stays green when
    /// the compare stops disregarding case, so a pass is read together with
    /// the printed line that names the entry.
    func testEveryForbiddenEntryWithItsLastComponentInAnotherCaseIsRefused() throws {
        try requireACaseInsensitiveVolume()
        let home = scratchHome().path
        var asked = 0
        for entry in try forbiddenEntries() {
            guard FileManager.default.fileExists(atPath: entry) else {
                print("[gates] forbidden entry \(entry) is not on this Mac; not asked")
                continue
            }
            let original = identity(of: entry).object
            let folds: [(label: String, transform: (String) -> String)] = [
                ("lower", { $0.lowercased() }), ("upper", { $0.uppercased() }),
            ]
            for (label, transform) in folds {
                let spelling = recased(entry, by: transform)
                guard spelling != entry else { continue }
                guard original != nil, identity(of: spelling).object == original else {
                    print("[gates] forbidden entry \(entry): \(spelling) does not name it; not asked")
                    continue
                }
                asked += 1
                let answer = RemovableScope.isRemovable(spelling, home: home)
                print("[gates] forbidden entry \(entry) leaf \(label)-cased "
                      + "\(spelling.debugDescription): isRemovable = \(answer)")
                XCTAssertFalse(answer, "\(spelling) names the forbidden \(entry) and is removable")
            }
        }
        XCTAssertGreaterThan(asked, 0, "no spelling of any forbidden entry was proved and asked")
    }

    /// A component above the last in another case. The gate resolves
    /// ancestors before it compares, so the case of every existing component
    /// above the last comes back first and the last component is the only one
    /// that keeps its spelling.
    func testAnAncestorInAnotherCaseIsRefused() throws {
        try requireACaseInsensitiveVolume()
        let utilities = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications/Utilities")) ?? []
        var spellings = ["/system/Applications/Mail.app"]
        if let app = utilities.sorted().first(where: { $0.hasSuffix(".app") }) {
            spellings.append("/applications/utilities/" + app)
        }
        let home = scratchHome().path
        var asked = 0
        for spelling in spellings {
            guard FileManager.default.fileExists(atPath: spelling) else {
                print("[gates] ancestor case: \(spelling) names nothing on this Mac; not asked")
                continue
            }
            asked += 1
            let answer = RemovableScope.isRemovable(spelling, home: home)
            print("[gates] ancestor case: \(spelling.debugDescription) resolves to "
                  + "\(PathCanonical.resolvingAncestors(spelling).debugDescription); isRemovable = \(answer)")
            XCTAssertFalse(answer, "\(spelling) is under a forbidden folder and is removable")
        }
        XCTAssertGreaterThan(asked, 0, "no spelling was proved and asked")
    }

    // MARK: - A volume file system path

    /// An ordinary folder, removable under its own name, named by inode.
    func testAVolfsSpellingOfAFolderIsRefusedByTheUserGate() throws {
        let folder = scratchHome()
        let spelling = try volfsSpelling(of: folder.path)

        let control = UserFileScope.isRemovable(folder.path)
        let answer = UserFileScope.isRemovable(spelling)
        print("[gates] UserFileScope.isRemovable(\(folder.path)) = \(control); "
              + "(\(spelling)) = \(answer)")
        XCTAssertFalse(answer, "\(spelling) names a folder by inode and is removable")
    }

    /// The home directory, which the gate refuses by name, named by device and
    /// inode.
    func testAVolfsSpellingOfTheHomeDirectoryIsRefusedByTheUserGate() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let spelling = try volfsSpelling(of: home)

        let control = UserFileScope.isRemovable(home)
        let answer = UserFileScope.isRemovable(spelling)
        print("[gates] UserFileScope.isRemovable(\(home)) = \(control); (\(spelling)) = \(answer)")
        XCTAssertFalse(control, "the home directory by name is the control, and it was removable")
        XCTAssertFalse(answer, "\(spelling) names the home directory and is removable")
    }

    /// A bundle inside a folder named by device and inode.
    /// `resolvingAncestors` turns the folder into its real path, and the real
    /// bundle is one the gate accepts under its own name; the spelling is
    /// refused all the same, because it names its place by number, as the
    /// user gate refuses it.
    func testAVolfsSpellingOfAFolderHoldingABundleIsRefusedByTheAppGate() throws {
        let home = scratchHome()
        let bundle = home.appendingPathComponent("Foo.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let folder = try volfsSpelling(of: home.path)
        let spelling = folder + "/Foo.app"
        let reached = identity(of: spelling)
        print("[gates] volfs bundle: \(spelling) is "
              + (reached.object.map { "\($0)" } ?? "nothing (\(reached.failure))")
              + "; \(bundle.path) is \(identity(of: bundle.path).object.map { "\($0)" } ?? "nothing")")
        guard reached.object != nil, reached.object == identity(of: bundle.path).object else {
            throw XCTSkip("\(spelling) does not name \(bundle.path) on this Mac")
        }

        let answer = RemovableScope.isRemovable(spelling, home: home.path)
        print("[gates] RemovableScope.isRemovable(\(spelling)) = \(answer); "
              + "resolvingAncestors gives \(PathCanonical.resolvingAncestors(spelling).debugDescription)")
        XCTAssertFalse(answer, "\(spelling) names a bundle by inode and is removable")
    }

    /// Bundles in folders `forbidden` names, reached through the folder's
    /// device and inode. The absolute spelling of each is the control.
    func testAVolfsSpellingOfAForbiddenFolderHoldingABundleIsRefusedByTheAppGate() throws {
        let home = scratchHome().path
        var candidates = [("/System/Applications", "Mail.app")]
        let utilities = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications/Utilities")) ?? []
        if let app = utilities.sorted().first(where: { $0.hasSuffix(".app") }) {
            candidates.append(("/Applications/Utilities", app))
        }
        var asked = 0
        for (folder, app) in candidates {
            let absolute = folder + "/" + app
            guard FileManager.default.fileExists(atPath: absolute),
                  let spelling = try? volfsSpelling(of: folder) else {
                print("[gates] volfs forbidden: \(absolute.debugDescription) is not proved reachable; not asked")
                continue
            }
            let through = spelling + "/" + app
            guard let reached = identity(of: through).object,
                  reached == identity(of: absolute).object else {
                print("[gates] volfs forbidden: \(through.debugDescription) does not name \(absolute); not asked")
                continue
            }
            asked += 1
            let control = RemovableScope.isRemovable(absolute, home: home)
            let answer = RemovableScope.isRemovable(through, home: home)
            print("[gates] volfs forbidden: RemovableScope.isRemovable(\(absolute.debugDescription)) = \(control); "
                  + "(\(through.debugDescription)) = \(answer)")
            XCTAssertEqual(PathCanonical.resolvingAncestors(through), absolute,
                           "the folder in \(through) does not resolve to \(folder)")
            XCTAssertFalse(control, "the absolute spelling is the control, and it was removable")
            XCTAssertFalse(answer, "\(through) names \(absolute) and is removable")
        }
        if asked == 0 { throw XCTSkip("no bundle in a forbidden folder was reachable through /.vol here") }
    }

    // MARK: - Reading what a spelling reaches

    private var homePath: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// What `lstat` says of a spelling, in one printable phrase.
    private func reach(_ path: String, followingLinks: Bool = false) -> String {
        let read = identity(of: path, followingLinks: followingLinks)
        return read.object.map { "\($0)" } ?? "nothing (\(read.failure))"
    }

    /// A scratch folder holding `Foo.app`, and the mount's own spelling of the
    /// folder, `/.vol/<device>/<inode>`, proved to answer for it.
    private func scratchFolderWithABundle() throws -> (folder: URL, bundle: URL, mount: String) {
        let folder = scratchHome()
        let bundle = folder.appendingPathComponent("Foo.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        return (folder, bundle, try volfsSpelling(of: folder.path))
    }

    /// `mount`, which begins `/.vol`, with its first component spelled `name`.
    private func respelled(_ mount: String, as name: String) -> String {
        "/" + name + String(mount.dropFirst("/.vol".count))
    }

    // MARK: - The mount in other spellings

    /// The mount named in another case, for a bundle (the app gate) and for
    /// the home directory (the user gate). `resolvingAncestors` restores the
    /// case of a component above the last, so the resolved spelling is
    /// `/.vol/...` and that half would refuse it by itself, as the spelling as
    /// given does; the line printed carries both spellings, with what `lstat`
    /// answered for the re-cased one, which is not asserted.
    func testTheMountInAnotherCaseIsRefusedByBothGates() throws {
        let scratch = try scratchFolderWithABundle()
        let homeMount = try volfsSpelling(of: homePath)
        for name in [".VOL", ".Vol", ".vOL"] {
            let bundle = respelled(scratch.mount, as: name) + "/Foo.app"
            let app = RemovableScope.isRemovable(bundle, home: scratch.folder.path)
            print("[gates] mount case: \(bundle.debugDescription): lstat \(reach(bundle)); "
                  + "resolvingAncestors \(PathCanonical.resolvingAncestors(bundle).debugDescription); "
                  + "RemovableScope.isRemovable = \(app)")
            XCTAssertFalse(app, "\(bundle) names a bundle by number in another case and is removable")

            let home = respelled(homeMount, as: name)
            let user = UserFileScope.isRemovable(home)
            print("[gates] mount case: \(home.debugDescription): lstat \(reach(home)); "
                  + "resolvingAncestors \(PathCanonical.resolvingAncestors(home).debugDescription); "
                  + "UserFileScope.isRemovable = \(user)")
            XCTAssertFalse(user, "\(home) names the home directory by number in another case and is removable")
        }
    }

    /// The predicate asked directly, on strings that spell the mount: its name
    /// is read without regard to case, as the first component left at the root
    /// only (a `.` dropped, a `..` popping the name before it), from either
    /// spelling alone. Through a gate on a case-insensitive volume the case of
    /// `/.VOL` is restored before the resolved spelling is asked, so only a
    /// question put to the predicate holds that the spelling as given is read
    /// without regard to case.
    func testThePredicateReadsTheMountsNameWithoutRegardToCaseFromEitherSpelling() {
        let ordinary = "/ordinary/place"
        let named = ["/.vol", "/.vol/1/2", "/.VOL/1/2", "/.Vol/1/2", "/.vOL/1/2/Foo.app",
                     "/./.VOL/1/2", "/x/../.Vol/1/2"]
        let notNamed = ["/", "/.volume/1/2", "/vol/1/2", "/.vo/1/2", "/a/.vol/1/2", "/.vol.app",
                        "/x/.VOL/1/2", ".vol/1/2", "vol", ""]
        for spelling in named {
            XCTAssertTrue(PathCanonical.beginsWithAKernelPrefix(spelling, resolved: ordinary),
                          "\(spelling) as given names its place by number and the predicate does not say so")
            XCTAssertTrue(PathCanonical.beginsWithAKernelPrefix(ordinary, resolved: spelling),
                          "\(spelling) as resolved names its place by number and the predicate does not say so")
        }
        for spelling in notNamed {
            XCTAssertFalse(PathCanonical.beginsWithAKernelPrefix(spelling, resolved: ordinary),
                           "\(spelling.debugDescription) as given is not the mount and the predicate says it is")
            XCTAssertFalse(PathCanonical.beginsWithAKernelPrefix(ordinary, resolved: spelling),
                           "\(spelling.debugDescription) as resolved is not the mount and the predicate says it is")
            XCTAssertFalse(PathCanonical.beginsWithAKernelPrefix(spelling, resolved: spelling),
                           "\(spelling.debugDescription) is not the mount and the predicate says it is")
        }
    }

    /// `PathCanonical.isAtOrBelow` handed the components of two paths, one with a
    /// long s (U+017F) in a name, which the volume reads as `s`: the list with the
    /// long s is at or below the plain folder's, at the same length and longer,
    /// because the fold is `.caseInsensitive`, and `lowercased()` leaves a long s
    /// alone. A name that differs by more than case, and a list shorter than the
    /// folder's, are not. No file system is asked, so no reading can give the
    /// predicate a plain `s` first.
    func testThePredicateFoldsALongSAsTheVolumeDoesAndOnlyThat() {
        let longS = String(UnicodeScalar(0x017F as UInt32)!)
        XCTAssertNotEqual(longS.lowercased(), "s", "a lowered long s is an s; the subject did not occur")
        func parts(_ path: String) -> [Substring] { path.split(separator: "/") }
        let folded = [("/cores", "/core\(longS)/x"), ("/cores", "/core\(longS)"), ("/cores", "/Core\(longS)"),
                      ("/Applications/Utilities", "/Applications/utilitie\(longS)/Foo.app"),
                      ("/Applications/Utilities", "/APPLICATION\(longS)/Utilitie\(longS)")]
        for (folder, spelling) in folded {
            XCTAssertTrue(PathCanonical.isAtOrBelow(parts(spelling), parts(folder)),
                          "\(spelling.debugDescription) (bytes \(KernelsOwnName.hex(spelling))) reads as "
                          + "\(folder) or a place below it on the volume and the predicate does not say it is at or below it")
        }
        let notFolded = [("/cores", "/core\(longS)z/x"), ("/cores", "/corez"), ("/cores", "/core"),
                         ("/cores", "/core\(longS)\(longS)"), ("/cores/x", "/core\(longS)"),
                         ("/cores", "/other/core\(longS)")]
        for (folder, spelling) in notFolded {
            XCTAssertFalse(PathCanonical.isAtOrBelow(parts(spelling), parts(folder)),
                           "\(spelling.debugDescription) (bytes \(KernelsOwnName.hex(spelling))) differs from "
                           + "\(folder) by more than case and the predicate says it is at or below it")
        }
    }

    /// The mount reached through `.` and `..`, or a doubled separator, in front
    /// of `.vol`. The kernel takes none of these strings for the mount: `lstat`
    /// of each answers that nothing is there (printed, and asserted below
    /// against the mount's own spelling, which reaches the bundle). So each
    /// names nothing; the reading climbs to `/.vol`, a folder at the root that
    /// the kernel answers for under each of these spellings and the deepest
    /// level that answers, and is a path to nothing whose name is that folder
    /// and the rest of the string by its letters, that is the mount's own
    /// spelling. `resolvingAncestors` collapses them and turns the folder into
    /// its real path, so the resolved spelling of the bundle is the bundle by its
    /// ordinary name — asserted below. Both gates refuse each one, because the
    /// string begins in the mount when read left to right with each `.` dropped
    /// and each `..` popping the name before it.
    func testTheMountReachedThroughDotAndDotDotIsRefusedByBothGates() throws {
        let scratch = try scratchFolderWithABundle()
        let homeMount = try volfsSpelling(of: homePath)
        XCTAssertNotNil(identity(of: scratch.mount + "/Foo.app").object,
                        "the mount's own spelling does not reach the bundle; the subject did not occur")
        for prefix in ["/.", "/Applications/..", "/System/../Applications/..", "/"] {
            let bundle = prefix + scratch.mount + "/Foo.app"
            let resolved = PathCanonical.resolvingAncestors(bundle)
            let app = RemovableScope.isRemovable(bundle, home: scratch.folder.path)
            print("[gates] mount dotted: \(bundle.debugDescription): lstat \(reach(bundle)); "
                  + "resolvingAncestors \(resolved.debugDescription); RemovableScope.isRemovable = \(app)")
            XCTAssertNil(identity(of: bundle).object, "the kernel takes \(bundle) for the bundle; the subject did not occur")
            let reading = PathCanonical.reading(of: bundle)
            XCTAssertEqual(reading.standing, .nothingThere, "\(bundle) names nothing, so it is a path to nothing")
            XCTAssertNil(reading.object, "\(bundle) names an object")
            XCTAssertTrue(reading.name.utf8.elementsEqual((scratch.mount + "/Foo.app").utf8),
                          "the reading names \(bundle) \(reading.name.debugDescription), not the mount's spelling")
            XCTAssertEqual(resolved, PathCanonical.resolvingAncestors(scratch.bundle.path),
                           "the dotted spelling does not resolve to the bundle's ordinary name")
            XCTAssertNil(PathCanonical.readingForRemoval(bundle).judgedName, "the gates' entry names \(bundle)")
            XCTAssertFalse(app, "\(bundle) names a bundle by number through . and .. and is removable")

            let home = prefix + homeMount
            let user = UserFileScope.isRemovable(home)
            print("[gates] mount dotted: \(home.debugDescription): lstat \(reach(home)); "
                  + "UserFileScope.isRemovable = \(user)")
            XCTAssertNil(identity(of: home).object, "the kernel takes \(home) for the home directory; the subject did not occur")
            XCTAssertNil(PathCanonical.readingForRemoval(home).judgedName, "the gates' entry names \(home)")
            XCTAssertFalse(user, "\(home) names the home directory by number through . and .. and is removable")
        }
    }

    /// The mount reached through a link to `/`. The spelling as given starts in
    /// the scratch folder and `resolvingAncestors` turns it into `/.vol/...`,
    /// so only the resolved spelling names the mount; the predicate is asked of
    /// each half alone below. What `lstat` says of the given spelling is
    /// printed: it is the string the gates are asked about.
    func testTheMountReachedThroughALinkToTheRootIsRefusedByBothGates() throws {
        let scratch = try scratchFolderWithABundle()
        let homeMount = try volfsSpelling(of: homePath)
        let link = scratch.folder.appendingPathComponent("root").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/")
        defer { unlink(link) }

        let bundle = link + scratch.mount + "/Foo.app"
        let resolved = PathCanonical.resolvingAncestors(bundle)
        let app = RemovableScope.isRemovable(bundle, home: scratch.folder.path)
        print("[gates] mount through a link to /: \(bundle.debugDescription): lstat \(reach(bundle)); "
              + "resolvingAncestors \(resolved.debugDescription); RemovableScope.isRemovable = \(app)")
        XCTAssertEqual(resolved, scratch.mount + "/Foo.app", "the link did not lead resolvingAncestors into the mount")
        XCTAssertFalse(PathCanonical.beginsWithAKernelPrefix(bundle, resolved: bundle),
                       "the spelling as given names the mount, so this row does not hold the resolved half")
        XCTAssertTrue(PathCanonical.beginsWithAKernelPrefix(bundle, resolved: resolved))
        XCTAssertFalse(app, "\(bundle) leads into the mount through a link and is removable")

        let home = link + homeMount
        let homeResolved = PathCanonical.resolvingAncestors(home)
        let user = UserFileScope.isRemovable(home)
        print("[gates] mount through a link to /: \(home.debugDescription): lstat \(reach(home)); "
              + "resolvingAncestors \(homeResolved.debugDescription); UserFileScope.isRemovable = \(user)")
        XCTAssertEqual(homeResolved, homeMount, "the link did not lead resolvingAncestors into the mount")
        XCTAssertFalse(PathCanonical.beginsWithAKernelPrefix(home, resolved: home),
                       "the spelling as given names the mount, so this row does not hold the resolved half")
        XCTAssertFalse(user, "\(home) leads into the mount through a link and is removable")
    }

    /// The home directory named by number with a component after it. The
    /// folder resolves to its real path, so the resolved spelling is the
    /// library by its ordinary name — asserted below to be no mount — and the
    /// refusal rests on the spelling as given.
    func testTheHomeDirectoryNamedByNumberWithAComponentAfterItIsRefusedByTheUserGate() throws {
        let library = homePath + "/Library"
        guard FileManager.default.fileExists(atPath: library) else {
            throw XCTSkip("\(library) is not on this Mac")
        }
        let spelling = try volfsSpelling(of: homePath) + "/Library"
        let named = identity(of: library).object
        print("[gates] volfs home component: \(spelling) is \(reach(spelling)); \(library) is \(reach(library))")
        guard named != nil, identity(of: spelling).object == named else {
            throw XCTSkip("\(spelling) does not name \(library) on this Mac")
        }

        let resolved = PathCanonical.resolvingAncestors(spelling)
        let control = UserFileScope.isRemovable(library)
        let answer = UserFileScope.isRemovable(spelling)
        print("[gates] UserFileScope.isRemovable(\(library)) = \(control); (\(spelling)) = \(answer); "
              + "resolvingAncestors gives \(resolved.debugDescription)")
        XCTAssertFalse(PathCanonical.beginsWithAKernelPrefix(resolved, resolved: resolved),
                       "the resolved spelling is itself a mount path, so this row does not hold the given half")
        XCTAssertFalse(answer, "\(spelling) names a folder in the home directory by number and is removable")
    }

    /// Nothing under the mount is judged, whether or not the number names an
    /// object: the refusal does not wait for the inode to exist.
    func testNothingUnderTheMountIsRemovableWhetherOrNotTheNumberNamesAnObject() throws {
        let scratch = try scratchFolderWithABundle()
        let device = scratch.mount.split(separator: "/")[1]
        let missing = "/.vol/\(device)/99999999999"
        guard identity(of: missing).object == nil else {
            throw XCTSkip("\(missing) names an object on this Mac")
        }
        let apps = ["/.vol/Foo.app", "/.vol/\(device)/Foo.app", missing + "/Foo.app"]
        for spelling in apps {
            let answer = RemovableScope.isRemovable(spelling, home: scratch.folder.path)
            print("[gates] mount, no object: \(spelling.debugDescription): lstat \(reach(spelling)); "
                  + "RemovableScope.isRemovable = \(answer)")
            XCTAssertFalse(answer, "\(spelling) is under the mount and removable")
        }
        for spelling in ["/.vol/1", "/.vol/\(device)/1", missing, missing + "/x"] {
            let answer = UserFileScope.isRemovable(spelling)
            print("[gates] mount, no object: \(spelling.debugDescription): lstat \(reach(spelling)); "
                  + "UserFileScope.isRemovable = \(answer)")
            XCTAssertFalse(answer, "\(spelling) is under the mount and removable")
        }
    }

    /// The same scratch objects by ordinary names, and names that only look
    /// like the mount, are accepted: a gate that refused everything would pass
    /// every row of this file that asserts only refusals.
    func testTheSameObjectsByOrdinaryNamesAreAcceptedAndOnlyTheMountIsNot() throws {
        let scratch = try scratchFolderWithABundle()
        for name in [".vol", ".volume"] {
            try FileManager.default.createDirectory(
                at: scratch.folder.appendingPathComponent(name + "/Foo.app"),
                withIntermediateDirectories: true)
        }
        let bundles = [scratch.bundle.path,
                       scratch.folder.path + "/.vol/Foo.app",
                       scratch.folder.path + "/.volume/Foo.app"]
        for bundle in bundles {
            let app = RemovableScope.isRemovable(bundle, home: scratch.folder.path)
            let resolved = PathCanonical.resolvingAncestors(bundle)
            print("[gates] ordinary: RemovableScope.isRemovable(\(bundle)) = \(app); "
                  + "named by number = \(PathCanonical.beginsWithAKernelPrefix(bundle, resolved: resolved))")
            XCTAssertTrue(app, "\(bundle) is an ordinary bundle and the gate refuses it")
            XCTAssertFalse(PathCanonical.beginsWithAKernelPrefix(bundle, resolved: resolved),
                           "\(bundle) is not in the mount and the predicate says it is")
        }
        for folder in [scratch.folder.path, scratch.folder.path + "/.vol"] {
            let user = UserFileScope.isRemovable(folder)
            print("[gates] ordinary: UserFileScope.isRemovable(\(folder)) = \(user)")
            XCTAssertTrue(user, "\(folder) is an ordinary folder and the gate refuses it")
        }
    }

    /// A link whose target is the mount's spelling of a folder, and `Foo.app`
    /// asked through it. The measurement is whether the kernel follows such a
    /// link at all. When it reaches the bundle, both gates must refuse the
    /// name, because it is a name that leads somewhere the gates cannot read;
    /// when it reaches nothing, the name names nothing, the gates judge a string
    /// with no object behind it, and their answers are printed and not asserted.
    func testALinkWhoseTargetIsTheMountReachesWhatItReachesAndTheGatesJudgeThatName() throws {
        let scratch = try scratchFolderWithABundle()
        let link = scratch.folder.appendingPathComponent("link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: scratch.mount)
        defer { unlink(link) }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), scratch.mount,
                       "the link does not point at the mount's spelling")
        XCTAssertNotNil(identity(of: link).object, "the link is not there")

        let through = link + "/Foo.app"
        let bundle = identity(of: scratch.bundle.path).object
        let reached = identity(of: through)
        let followed = identity(of: link, followingLinks: true)
        let app = RemovableScope.isRemovable(through, home: scratch.folder.path)
        let user = UserFileScope.isRemovable(through)
        print("[gates] link into the mount: \(through.debugDescription): lstat \(reach(through)); "
              + "stat of the link \(reach(link, followingLinks: true)); "
              + "fileExists = \(FileManager.default.fileExists(atPath: through)); "
              + "bundle is \(bundle.map { "\($0)" } ?? "nothing"); "
              + "resolvingAncestors \(PathCanonical.resolvingAncestors(through).debugDescription); "
              + "RemovableScope.isRemovable = \(app); UserFileScope.isRemovable = \(user)")
        if let object = reached.object {
            XCTAssertEqual(object, bundle, "the link leads to an object that is not the bundle")
            XCTAssertFalse(app, "\(through) leads to the bundle through a link into the mount and is removable")
            XCTAssertFalse(user, "\(through) leads to the bundle through a link into the mount and is removable")
        } else {
            XCTAssertNil(followed.object, "the kernel follows the link itself yet not the name under it")
        }
    }

    // MARK: - A spelling the volume folds onto the same name

    /// The forbidden folder's last component with a long s (U+017F), which the
    /// volume may read as `s`. Where it does, the spelling names the folder,
    /// the reading gives it the name the disk holds, and the gate refuses that
    /// name; the comparison in `PathCanonical.isAtOrBelow` is handed no long s,
    /// so this row passes whichever way that comparison folds. When the volume
    /// does not read it so, the spelling names another object or none, and the
    /// test skips and says which.
    func testTheForbiddenFolderSpelledWithALongSIsRefusedWhereTheVolumeReadsItAsTheFolder() throws {
        let folder = "/Applications/Utilities"
        guard let named = identity(of: folder).object else { throw XCTSkip("\(folder) is not on this Mac") }
        let home = scratchHome().path
        var spellings = ["/Applications/Utilitie\u{017F}", "/Applications/utilitie\u{017F}",
                         "/Applications/Utilitie\u{017F}/", "/Applications/Utilitie\u{017F}/."]
        if let app = (try? FileManager.default.contentsOfDirectory(atPath: folder))?
            .sorted().first(where: { $0.hasSuffix(".app") }) {
            spellings.append("/Applications/Utilitie\u{017F}/" + app)
        }
        for spelling in spellings {
            let reached = identity(of: spelling).object
            let answer = RemovableScope.isRemovable(spelling, home: home)
            print("[gates] long s: \(folder) is \(named); \(spelling.debugDescription) is "
                  + "\(reach(spelling)); RemovableScope.isRemovable = \(answer)")
            guard spelling.hasSuffix(".app") ? reached != nil : reached == named else {
                throw XCTSkip("\(spelling.debugDescription) does not name \(folder) on this volume: "
                              + reach(spelling))
            }
            XCTAssertFalse(answer, "\(spelling) names \(folder) and is removable")
        }
    }

    /// The home directory with its name spelled with long s in place of `s`.
    /// Where the volume reads that as the home, the reading gives it the name
    /// the disk holds and `UserFileScope` refuses the home by that name; the
    /// comparison in `PathCanonical.isAtOrBelow` is handed no long s, so this
    /// row passes whichever way that comparison folds.
    func testTheHomeDirectorySpelledWithALongSIsRefusedByTheUserGateWhereTheVolumeReadsItAsTheHome() throws {
        let leaf = (homePath as NSString).lastPathComponent
        let parent = (homePath as NSString).deletingLastPathComponent
        let folded = leaf.replacingOccurrences(of: "s", with: "\u{017F}")
            .replacingOccurrences(of: "S", with: "\u{017F}")
        guard folded != leaf else { throw XCTSkip("the home directory's name, \(leaf), has no s to spell as a long s") }
        let spelling = parent + "/" + folded
        let named = identity(of: homePath).object
        print("[gates] long s: \(homePath) is \(reach(homePath)); \(spelling.debugDescription) is \(reach(spelling))")
        guard named != nil, identity(of: spelling).object == named else {
            throw XCTSkip("\(spelling.debugDescription) does not name \(homePath) on this volume: \(reach(spelling))")
        }

        let control = UserFileScope.isRemovable(homePath)
        let answer = UserFileScope.isRemovable(spelling)
        print("[gates] UserFileScope.isRemovable(\(homePath)) = \(control); (\(spelling.debugDescription)) = \(answer); "
              + "resolvingAncestors gives \(PathCanonical.resolvingAncestors(spelling).debugDescription)")
        XCTAssertFalse(control, "the home directory by its name is the control, and it was removable")
        XCTAssertFalse(answer, "\(spelling) names the home directory and is removable")
    }

    // MARK: - An empty path, and a relative one with no bundle suffix

    /// Strings that name nothing a gate could judge from where it stands. The
    /// `.app` clause is not what refuses them: none ends in `.app`. A relative
    /// `home` is a parameter the roots are built from, and a path under it
    /// passes every prefix test unless the gate asks first that a path start
    /// at `/`. The first five are refused with or without that guard, by the
    /// tests that follow it; the two under the relative home are the ones the
    /// guard alone refuses.
    func testAnEmptyAndARelativePathWithoutABundleSuffixAreRefused() {
        for spelling in ["", "x", "x/y", "Library/Caches/x", "Applications/x"] {
            let app = RemovableScope.isRemovable(spelling, home: "/nonexistent-home")
            let user = UserFileScope.isRemovable(spelling)
            print("[gates] relative: \(spelling.debugDescription): RemovableScope.isRemovable = \(app); "
                  + "UserFileScope.isRemovable = \(user)")
            XCTAssertFalse(app, "\(spelling.debugDescription) reached RemovableScope as a removable path")
            XCTAssertFalse(user, "\(spelling.debugDescription) reached UserFileScope as a removable path")
        }
        for spelling in ["h/Library/Caches/x", "h/Applications/x"] {
            let app = RemovableScope.isRemovable(spelling, home: "h")
            print("[gates] relative under a relative home: \(spelling.debugDescription): "
                  + "RemovableScope.isRemovable = \(app)")
            XCTAssertFalse(app, "\(spelling.debugDescription) under the relative home \"h\" is removable")
        }
    }

    // MARK: - The forbidden folder, re-cased, with something after it

    /// The forbidden folder with its last component in another case and a
    /// slash, a slash and a dot, or two slashes after it: `resolvingAncestors`
    /// drops what follows, and the compare still has to see the folder.
    func testTheForbiddenFolderInAnotherCaseWithASlashOrADotAfterItIsRefused() throws {
        try requireACaseInsensitiveVolume()
        let original = "/Applications/Utilities"
        guard let named = identity(of: original).object else { throw XCTSkip("\(original) is not on this Mac") }
        let home = scratchHome().path
        for spelling in ["/Applications/utilities/", "/Applications/UTILITIES/", "/Applications/utilities/.",
                         "/Applications/UTILITIES/.", "/Applications/utilities//", "/Applications/utilities/./"] {
            let answer = RemovableScope.isRemovable(spelling, home: home)
            print("[gates] forbidden re-cased: \(spelling.debugDescription) is \(reach(spelling)); "
                  + "\(original) is \(named); resolvingAncestors \(PathCanonical.resolvingAncestors(spelling).debugDescription); "
                  + "RemovableScope.isRemovable = \(answer)")
            XCTAssertEqual(identity(of: spelling).object, named, "\(spelling.debugDescription) does not name \(original)")
            XCTAssertFalse(answer, "\(spelling.debugDescription) names the forbidden \(original) and is removable")
        }
    }

    // MARK: - The mount's siblings, /.nofollow and /.resolve/<n>

    /// The two prefixes beside `/.vol` that the kernel answers with the object
    /// the rest of the path names.
    private var siblingPrefixes: [String] { ["/.nofollow", "/.resolve/1"] }

    /// `prefix` in front of `path`, after the kernel has answered for the
    /// result with the device and inode `path` has. When the kernel answers
    /// otherwise it prints what was answered and throws a skip, which skips a
    /// test that calls it with `try` and drops the one entry in a test that
    /// calls it with `try?`.
    private func underPrefix(_ prefix: String, _ path: String) throws -> String {
        let direct = identity(of: path)
        guard let object = direct.object else {
            throw XCTSkip("\(path) could not be read: \(direct.failure)")
        }
        let spelling = prefix + path
        let through = identity(of: spelling)
        print("[gates] prefix: \(path) is \(object); \(spelling) answers "
              + (through.object.map { "\($0)" } ?? "nothing (\(through.failure))"))
        guard through.object == object else {
            throw XCTSkip("\(spelling) does not name \(path) on this Mac: "
                          + (through.object.map { "it names \($0)" } ?? through.failure))
        }
        return spelling
    }

    /// The literal `/.nofollow` and `/.resolve/1`, each in front of the home
    /// directory and of a bundle of Apple's, proved to answer for the object
    /// the path alone names. The rows that change the prefix prove their
    /// subject through this.
    private func proveTheSiblingPrefixesAnswer() throws {
        for prefix in siblingPrefixes {
            _ = try underPrefix(prefix, homePath)
            _ = try underPrefix(prefix, "/System/Applications/Mail.app")
        }
    }

    /// The home directory (for the user gate) and Mail (for the app gate)
    /// written behind `prefix`. Prints what `lstat` answers for each, what
    /// `resolvingAncestors` makes of it and the gate's answer, and asserts
    /// that the gate refuses it; the kernel's answer is not asserted.
    private func assertBothGatesRefuse(behind prefix: String, _ tag: String, home: String) {
        let bundle = prefix + "/System/Applications/Mail.app"
        let app = RemovableScope.isRemovable(bundle, home: home)
        print("[gates] \(tag): \(bundle.debugDescription): lstat \(reach(bundle)); "
              + "resolvingAncestors \(PathCanonical.resolvingAncestors(bundle).debugDescription); "
              + "RemovableScope.isRemovable = \(app)")
        XCTAssertFalse(app, "\(bundle) names Apple's Mail behind a sibling prefix and is removable")

        let user = prefix + homePath
        let answer = UserFileScope.isRemovable(user)
        print("[gates] \(tag): \(user.debugDescription): lstat \(reach(user)); "
              + "resolvingAncestors \(PathCanonical.resolvingAncestors(user).debugDescription); "
              + "UserFileScope.isRemovable = \(answer)")
        XCTAssertFalse(answer, "\(user) names the home directory behind a sibling prefix and is removable")
    }

    /// What `UserFileScope` refuses by name, behind `/.nofollow` and
    /// `/.resolve/1`: each protected prefix, the home directory, and the
    /// top-level folders `/Users` and `/Volumes`, which its depth guard
    /// refuses. A place that is not on this Mac is not asked.
    func testASiblingSpellingOfAPlaceTheUserGateRefusesIsRefused() throws {
        let places = UserFileScope.protectedPrefixes + [homePath, "/Users", "/Volumes"]
        var asked = 0
        for prefix in siblingPrefixes {
            for place in places {
                guard let spelling = try? underPrefix(prefix, place) else { continue }
                asked += 1
                let control = UserFileScope.isRemovable(place)
                let answer = UserFileScope.isRemovable(spelling)
                print("[gates] UserFileScope.isRemovable(\(place.debugDescription)) = \(control); "
                      + "(\(spelling.debugDescription)) = \(answer)")
                XCTAssertFalse(control, "\(place) by its name is the control, and it was removable")
                XCTAssertFalse(answer, "\(spelling) names \(place) and is removable")
            }
        }
        if asked == 0 { throw XCTSkip("the kernel answered under neither prefix here") }
    }

    /// Bundles under `/System/Applications` and `/Applications/Utilities`,
    /// which `RemovableScope` refuses by name, behind `/.nofollow` and
    /// `/.resolve/1`. The absolute spelling of each is the control.
    func testASiblingSpellingOfAProtectedBundleIsRefusedByTheAppGate() throws {
        let home = scratchHome().path
        var bundles = ["/System/Applications/Mail.app"]
        let utilities = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications/Utilities")) ?? []
        if let app = utilities.sorted().first(where: { $0.hasSuffix(".app") }) {
            bundles.append("/Applications/Utilities/" + app)
        }
        var asked = 0
        for prefix in siblingPrefixes {
            for bundle in bundles {
                guard let spelling = try? underPrefix(prefix, bundle) else { continue }
                asked += 1
                let control = RemovableScope.isRemovable(bundle, home: home)
                let answer = RemovableScope.isRemovable(spelling, home: home)
                print("[gates] RemovableScope.isRemovable(\(bundle.debugDescription)) = \(control); "
                      + "(\(spelling.debugDescription)) = \(answer); "
                      + "resolvingAncestors gives \(PathCanonical.resolvingAncestors(spelling).debugDescription)")
                XCTAssertFalse(control, "the absolute spelling is the control, and it was removable")
                XCTAssertFalse(answer, "\(spelling) names \(bundle) and is removable")
            }
        }
        if asked == 0 { throw XCTSkip("the kernel answered under neither prefix here") }
    }

    /// Numbers after `/.resolve`, those of the list below for which the kernel
    /// answers, for the home directory (the user gate) and for Apple's Mail
    /// (the app gate). The kernel reads the number as flags and answers for
    /// some and not for others; a number it does not answer for is printed and
    /// not asked.
    func testNumbersTheKernelTakesAfterResolveAreRefusedByBothGates() throws {
        let home = scratchHome().path
        let mail = "/System/Applications/Mail.app"
        var asked = 0
        for number in [0, 1, 2, 255, 256, 511, 512, 1024] {
            let prefix = "/.resolve/\(number)"
            if let spelling = try? underPrefix(prefix, homePath) {
                asked += 1
                let answer = UserFileScope.isRemovable(spelling)
                print("[gates] UserFileScope.isRemovable(\(spelling.debugDescription)) = \(answer)")
                XCTAssertFalse(answer, "\(spelling) names the home directory and is removable")
            }
            if let spelling = try? underPrefix(prefix, mail) {
                asked += 1
                let answer = RemovableScope.isRemovable(spelling, home: home)
                print("[gates] RemovableScope.isRemovable(\(spelling.debugDescription)) = \(answer)")
                XCTAssertFalse(answer, "\(spelling) names \(mail) and is removable")
            }
        }
        if asked == 0 { throw XCTSkip("the kernel answered under no /.resolve number here") }
    }

    /// The root of the volume. The kernel answers `/.nofollow/` and
    /// `/.resolve/<n>/` with the root's own device and inode. The user gate
    /// drops the trailing slash, which leaves `/.nofollow`, a top-level name
    /// its depth guard would refuse alone, and `/.resolve/<n>`, two components
    /// that guard passes; the prefix refusal, which both gates make ahead of
    /// every depth test, is what refuses both.
    func testTheVolumeRootBehindASiblingPrefixIsRefusedByBothGates() throws {
        guard let root = identity(of: "/").object else { throw XCTSkip("/ could not be read") }
        let home = scratchHome().path
        var asked = 0
        for spelling in ["/.nofollow/", "/.nofollow/.", "/.resolve/0/", "/.resolve/1/", "/.resolve/1/.",
                         "/.resolve/1//", "/.resolve/255/"] {
            let reached = identity(of: spelling).object
            print("[gates] root: \(spelling.debugDescription) is \(reach(spelling)); / is \(root)")
            guard reached == root else { continue }
            asked += 1
            let user = UserFileScope.isRemovable(spelling)
            let app = RemovableScope.isRemovable(spelling, home: home)
            print("[gates] root: UserFileScope.isRemovable(\(spelling.debugDescription)) = \(user); "
                  + "RemovableScope.isRemovable = \(app); "
                  + "resolvingAncestors gives \(PathCanonical.resolvingAncestors(spelling).debugDescription)")
            XCTAssertFalse(user, "\(spelling) names the root of the volume and is removable")
            XCTAssertFalse(app, "\(spelling) names the root of the volume and is removable")
        }
        if asked == 0 { throw XCTSkip("the kernel answered with the root under no sibling prefix here") }
    }

    /// A sibling prefix in front of the mount: `/.nofollow/.vol/<device>/<inode>`
    /// names the home directory and a scratch bundle, each as the mount alone
    /// does. The kernel's answer for each spelling is read before the gate is
    /// asked.
    func testASiblingPrefixInFrontOfTheMountIsRefusedByBothGates() throws {
        let scratch = try scratchFolderWithABundle()
        let homeMount = try volfsSpelling(of: homePath)
        let homeObject = identity(of: homePath).object
        let bundleObject = identity(of: scratch.bundle.path).object
        var asked = 0
        for prefix in siblingPrefixes {
            let home = prefix + homeMount
            let bundle = prefix + scratch.mount + "/Foo.app"
            print("[gates] prefix before the mount: \(home.debugDescription) is \(reach(home)), "
                  + "\(homePath) is \(reach(homePath)); \(bundle.debugDescription) is \(reach(bundle)), "
                  + "\(scratch.bundle.path) is \(reach(scratch.bundle.path))")
            if identity(of: home).object == homeObject {
                asked += 1
                let user = UserFileScope.isRemovable(home)
                print("[gates] prefix before the mount: UserFileScope.isRemovable(\(home.debugDescription)) = \(user)")
                XCTAssertFalse(user, "\(home) names the home directory and is removable")
            }
            if identity(of: bundle).object == bundleObject {
                asked += 1
                let app = RemovableScope.isRemovable(bundle, home: scratch.folder.path)
                print("[gates] prefix before the mount: RemovableScope.isRemovable(\(bundle.debugDescription)) = \(app)")
                XCTAssertFalse(app, "\(bundle) names a bundle behind a sibling prefix and the mount and is removable")
            }
        }
        if asked == 0 { throw XCTSkip("the kernel answered under no sibling prefix before the mount here") }
    }

    /// The sibling prefixes named in another case. These are strings a gate is
    /// asked about whether or not the kernel answers for them; the literal
    /// prefix has to answer, and the line printed says what `lstat` answered
    /// for the re-cased one and what `resolvingAncestors` made of it.
    func testASiblingPrefixInAnotherCaseIsRefusedByBothGates() throws {
        try proveTheSiblingPrefixesAnswer()
        let home = scratchHome().path
        for prefix in ["/.NOFOLLOW", "/.Nofollow", "/.nOFOLLOW", "/.RESOLVE/1", "/.Resolve/1", "/.rESOLVE/1"] {
            assertBothGatesRefuse(behind: prefix, "sibling case", home: home)
        }
    }

    /// The sibling prefixes reached through `.` and `..`, in front of them and
    /// after them. `resolvingAncestors` collapses both, the predicate reads the
    /// prefix as the first component left at the root before a `..` after it
    /// is read, and what `lstat` says of each spelling is printed.
    func testASiblingPrefixReachedThroughDotAndDotDotIsRefusedByBothGates() throws {
        try proveTheSiblingPrefixesAnswer()
        let home = scratchHome().path
        for sibling in siblingPrefixes {
            for lead in ["/.", "/Applications/..", "/System/../Applications/.."] {
                assertBothGatesRefuse(behind: lead + sibling, "sibling dotted", home: home)
            }
            assertBothGatesRefuse(behind: sibling + "/Applications/..", "sibling dotted", home: home)
        }
    }

    /// The sibling prefixes reached through a link to `/`. The link leads to
    /// the root, which is asserted; whether the kernel answers for the prefix
    /// after it is printed, and the gates are asked all the same.
    func testASiblingPrefixReachedThroughALinkToTheRootIsRefusedByBothGates() throws {
        try proveTheSiblingPrefixesAnswer()
        let folder = scratchHome()
        let link = folder.appendingPathComponent("root").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/")
        defer { unlink(link) }
        XCTAssertNotNil(identity(of: "/").object, "/ could not be read")
        XCTAssertEqual(identity(of: link, followingLinks: true).object, identity(of: "/").object,
                       "the link does not lead to /")
        for sibling in siblingPrefixes {
            assertBothGatesRefuse(behind: link + sibling, "sibling through a link to /", home: folder.path)
        }
    }

    /// Folders below an ordinary folder that are named like the prefixes, or
    /// only resemble them: a bundle in each is accepted by the app gate and
    /// the folder itself by the user gate. A gate that refused every path with
    /// such a name in it would pass every other row of this section.
    func testNamesThatOnlyResembleTheSiblingPrefixesAreAccepted() throws {
        let folder = scratchHome()
        let names = [".nofollow", ".resolve", ".resolve/1", ".nofollowed", ".resolved", "nofollow", "resolve",
                     ".file"]
        for name in names {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent(name + "/Foo.app"), withIntermediateDirectories: true)
        }
        for name in names {
            let parent = folder.path + "/" + name
            let bundle = parent + "/Foo.app"
            let app = RemovableScope.isRemovable(bundle, home: folder.path)
            let user = UserFileScope.isRemovable(parent)
            print("[gates] ordinary: RemovableScope.isRemovable(\(bundle)) = \(app); "
                  + "UserFileScope.isRemovable(\(parent)) = \(user); "
                  + "resolvingAncestors gives \(PathCanonical.resolvingAncestors(bundle).debugDescription)")
            XCTAssertTrue(app, "\(bundle) is an ordinary bundle and the gate refuses it")
            XCTAssertTrue(user, "\(parent) is an ordinary folder and the gate refuses it")
        }
    }

    // MARK: - A kernel prefix followed by `..`

    /// The strings that stand in front of `.vol` in a mount spelling: nothing,
    /// `/.nofollow` and `/.resolve/1`.
    private var prefixesInFrontOfTheMount: [String] { ["", "/.nofollow", "/.resolve/1"] }

    private enum Gate: String {
        case user = "UserFileScope", app = "RemovableScope"
    }

    private func asks(_ gate: Gate, _ path: String, home: String) -> Bool {
        switch gate {
        case .user: return UserFileScope.isRemovable(path)
        case .app: return RemovableScope.isRemovable(path, home: home)
        }
    }

    /// A scratch folder `landing` that holds `Sub`, and a folder `deep` below
    /// it, as many levels down as there are components in front of the object
    /// to pop: the prefix's, `.vol`, the device and the inode. `mount` is
    /// the kernel's `/.vol/<device>/<inode>` for `deep`, and `dots` is that
    /// count of `..`.
    private struct Climb {
        let prefix: String
        let landing: URL
        let mount: String
        let dots: Int

        /// The prefix, the mount, `dots` times `..`, then `Sub/<leaf>`: for the
        /// kernel `landing/Sub/<leaf>`, for a collapse by the letters
        /// `/Sub/<leaf>`.
        func spelling(_ leaf: String) -> String {
            prefix + mount + String(repeating: "/..", count: dots) + "/Sub/" + leaf
        }

        /// The leaf where the kernel puts it, by its own name:
        /// `landing/Sub/<leaf>`.
        func object(_ leaf: String) -> String { landing.path + "/Sub/" + leaf }
    }

    /// A `Climb` behind `prefix`, with a link to nothing in `Sub` for each of
    /// `leaves`: a relative target that no file bears.
    private func aClimb(behind prefix: String, linksToNothing leaves: [String]) throws -> Climb {
        let dots = prefix.split(separator: "/").count + 3
        let landing = scratchHome()
        var deep = landing
        for level in 1...dots { deep.appendPathComponent("level\(level)") }
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: landing.appendingPathComponent("Sub"),
                                                withIntermediateDirectories: true)
        for leaf in leaves {
            try FileManager.default.createSymbolicLink(atPath: landing.path + "/Sub/" + leaf,
                                                       withDestinationPath: "nothing-" + leaf)
        }
        return Climb(prefix: prefix, landing: landing, mount: try volfsSpelling(of: deep.path), dots: dots)
    }

    /// Proves what a climbing spelling is, prints it, and returns it.
    ///
    /// For a link to nothing, `lstat` of the spelling must give the link's own
    /// device and inode and `stat` must give nothing. For a leaf that is not
    /// there, nothing is named: `lstat` of the spelling must answer that it is
    /// not there, while the spelling cut short of the leaf must give the
    /// scratch `Sub`. A Mac whose kernel answers otherwise skips the test. In
    /// both, the reading names the leaf as the kernel does, by bytes (the
    /// kernel's name for the folder the spelling climbs to, `/`, the typed
    /// leaf), its standing is the object's for a link and a path to nothing for
    /// a leaf that is not there, and the folder `resolvingAncestors` puts the
    /// leaf in is asserted not to be that `Sub`, which is the case where a gate
    /// that judged the letters would judge a name that is not the object's.
    private func proveTheClimb(_ climb: Climb, leaf: String, linkToNothing: Bool) throws -> String {
        let spelling = climb.spelling(leaf)
        let object = climb.object(leaf)
        let sub = identity(of: climb.landing.path + "/Sub").object
        let judged = PathCanonical.resolvingAncestors(spelling)
        let judgedFolder = (judged as NSString).deletingLastPathComponent
        print("[gates] climb: \(spelling.debugDescription): lstat \(reach(spelling)); "
              + "\(object) is \(reach(object)), stat of it \(reach(object, followingLinks: true)); "
              + "resolvingAncestors gives \(judged.debugDescription), whose folder "
              + "\(judgedFolder.debugDescription) is \(reach(judgedFolder)) "
              + "and the object's folder is \(sub.map { "\($0)" } ?? "nothing")")
        if linkToNothing {
            guard let wanted = identity(of: object).object, identity(of: spelling).object == wanted else {
                throw XCTSkip("\(spelling.debugDescription) does not name \(object) on this Mac")
            }
            XCTAssertNil(identity(of: object, followingLinks: true).object,
                         "\(object) leads somewhere, so it is not a link to nothing")
        } else {
            let folder = String(spelling.dropLast(leaf.count + 1))
            guard sub != nil, identity(of: folder).object == sub,
                  identity(of: spelling).object == nil, identity(of: object).object == nil else {
                throw XCTSkip("\(folder.debugDescription) does not climb to the scratch Sub on this Mac, "
                              + "or \(leaf) is there")
            }
        }
        XCTAssertNotEqual(identity(of: judgedFolder).object, sub,
                          "\(spelling) resolves to the object's own folder; the subject did not occur")
        let reading = PathCanonical.reading(of: spelling)
        let standing: PathCanonical.Reading.Standing = linkToNothing ? .object : .nothingThere
        XCTAssertEqual(reading.standing, standing, "\(spelling) is read as \(reading.standing)")
        let kernelsName = KernelsOwnName.name(of: spelling)
        XCTAssertNotNil(kernelsName, "the kernel gave \(spelling) no name")
        XCTAssertTrue(kernelsName.map { reading.name.utf8.elementsEqual($0.utf8) } ?? false,
                      "the reading names \(spelling) \(reading.name.debugDescription), the kernel \(kernelsName.debugDescription)")
        return spelling
    }

    /// `spelling` is refused by `gate`. The object by its own name is the
    /// control, asserted accepted where the gate would take it by name: any
    /// name for the user gate, a `.app` for the app gate, unless the caller
    /// says the gate refuses the object by name too (`objectIsAccepted`).
    private func assertRefused(_ spelling: String, by gate: Gate, object: String, home: String, _ tag: String,
                               objectIsAccepted: Bool? = nil) {
        let control = asks(gate, object, home: home)
        let answer = asks(gate, spelling, home: home)
        print("[gates] \(tag): \(gate.rawValue).isRemovable(\(object.debugDescription)) = \(control); "
              + "(\(spelling.debugDescription)) = \(answer)")
        if objectIsAccepted ?? (gate == .user || object.hasSuffix(".app")) {
            XCTAssertTrue(control, "\(object) by its own name is the control, and \(gate.rawValue) refuses it")
        } else if objectIsAccepted == false {
            XCTAssertFalse(control, "\(object) by its own name is the control, and \(gate.rawValue) accepts it")
        }
        XCTAssertFalse(answer, "\(spelling) begins with a kernel prefix and \(gate.rawValue) accepts it")
    }

    /// A link to nothing reached by climbing from the mount's spelling of a
    /// folder, behind `prefix`, asked of one gate. The user gate's leaf is
    /// `dead`, the app gate's `dead.app`.
    private func assertAClimbToALinkToNothingIsRefused(behind prefix: String, by gate: Gate) throws {
        let leaf = gate == .user ? "dead" : "dead.app"
        let climb = try aClimb(behind: prefix, linksToNothing: [leaf])
        let spelling = try proveTheClimb(climb, leaf: leaf, linkToNothing: true)
        assertRefused(spelling, by: gate, object: climb.object(leaf), home: climb.landing.path, "climb")
    }

    /// The mount's spelling of a scratch folder some levels down, three `..`
    /// to the folder that holds a link to nothing: the kernel answers with the
    /// link. Collapsed by the letters the three `..` pop the mount, and what
    /// is left is an ordinary name the gate would accept.
    func testTheMountClimbingToALinkToNothingIsRefusedByTheUserGate() throws {
        try assertAClimbToALinkToNothingIsRefused(behind: "", by: .user)
    }

    /// The same with a link to nothing named `dead.app`, which the app gate
    /// takes for a bundle wherever it stands.
    func testTheMountClimbingToALinkToNothingIsRefusedByTheAppGate() throws {
        try assertAClimbToALinkToNothingIsRefused(behind: "", by: .app)
    }

    /// Behind `/.nofollow`, which a fourth `..` pops as well.
    func testNofollowBeforeTheMountClimbingToALinkToNothingIsRefusedByTheUserGate() throws {
        try assertAClimbToALinkToNothingIsRefused(behind: "/.nofollow", by: .user)
    }

    func testNofollowBeforeTheMountClimbingToALinkToNothingIsRefusedByTheAppGate() throws {
        try assertAClimbToALinkToNothingIsRefused(behind: "/.nofollow", by: .app)
    }

    /// Behind `/.resolve/1`, which a fourth and a fifth `..` pop as well.
    func testResolveBeforeTheMountClimbingToALinkToNothingIsRefusedByTheUserGate() throws {
        try assertAClimbToALinkToNothingIsRefused(behind: "/.resolve/1", by: .user)
    }

    func testResolveBeforeTheMountClimbingToALinkToNothingIsRefusedByTheAppGate() throws {
        try assertAClimbToALinkToNothingIsRefused(behind: "/.resolve/1", by: .app)
    }

    /// The same climb to a leaf that is not there, behind each prefix, with the
    /// leaf named `ghost.app` and `ghost`. Nothing is named: the kernel answers
    /// that the spelling is not there, and the proof of the subject is that
    /// the spelling cut short of the leaf names the scratch `Sub`. The gates
    /// answer for a string all the same, and a string that begins with a kernel
    /// prefix is refused whatever follows it. The app gate refuses `ghost` with
    /// or without the prefix, since it is no bundle and lies under none of its
    /// roots: those three answers are asked and counted, and hold nothing about
    /// the prefix.
    func testAClimbingSpellingOfALeafThatIsNotThereIsRefusedByBothGates() throws {
        var asked = 0
        for prefix in prefixesInFrontOfTheMount {
            let climb = try aClimb(behind: prefix, linksToNothing: [])
            for leaf in ["ghost.app", "ghost"] {
                let spelling = try proveTheClimb(climb, leaf: leaf, linkToNothing: false)
                for gate in [Gate.user, Gate.app] {
                    asked += 1
                    assertRefused(spelling, by: gate, object: climb.object(leaf),
                                  home: climb.landing.path, "climb, leaf not there")
                }
            }
        }
        XCTAssertEqual(asked, 12, "a prefix, a leaf or a gate was not asked")
    }

    /// A climbing spelling to a leaf that is not there, with something in front
    /// of the prefix that a reader of names drops: repeated slashes, a `.`, a
    /// `..` after a name. Nothing is named, and what `lstat` answers for each
    /// is printed and not asserted; the empty parts and the `.` in front of the
    /// prefix are dropped and each `..` pops the name before it, so the prefix
    /// is the first component left at the root and both gates refuse each.
    func testAClimbingSpellingWithDotsOrSlashesInFrontOfThePrefixIsRefusedByBothGates() throws {
        let climb = try aClimb(behind: "", linksToNothing: [])
        let plain = try proveTheClimb(climb, leaf: "ghost.app", linkToNothing: false)
        for lead in ["/", "//", "/.", "/./.", "/Applications/..", "/x/..", "/x/y/../.."] {
            let spelling = lead + plain
            print("[gates] climb, in front of the prefix: \(spelling.debugDescription): lstat \(reach(spelling))")
            for gate in [Gate.user, Gate.app] {
                assertRefused(spelling, by: gate, object: climb.object("ghost.app"),
                              home: climb.landing.path, "climb, in front of the prefix")
            }
        }
    }

    /// A climbing spelling to a link to nothing with one slash doubled, each
    /// slash in turn after the first. The kernel answers for a doubled slash
    /// after the device, after the inode, between two `..`, after the last
    /// `..` and before the leaf, and not for one right after `.vol`; every
    /// spelling it answers with the link is asked of the gate whose leaf it
    /// is, and the rest are printed.
    func testRepeatedSlashesInAClimbingSpellingDoNotHideThePrefix() throws {
        let climb = try aClimb(behind: "", linksToNothing: ["dead", "dead.app"])
        var asked = 0
        for (gate, leaf) in [(Gate.user, "dead"), (Gate.app, "dead.app")] {
            let plain = try proveTheClimb(climb, leaf: leaf, linkToNothing: true)
            let wanted = identity(of: climb.object(leaf)).object
            for index in plain.indices.filter({ plain[$0] == "/" }).dropFirst() {
                var spelling = plain
                spelling.insert("/", at: index)
                let offset = plain.distance(from: plain.startIndex, to: index)
                print("[gates] climb, slash doubled at \(offset): \(spelling.debugDescription): lstat \(reach(spelling))")
                guard identity(of: spelling).object == wanted else { continue }
                asked += 1
                assertRefused(spelling, by: gate, object: climb.object(leaf),
                              home: climb.landing.path, "climb, slash doubled at \(offset)")
            }
        }
        XCTAssertGreaterThanOrEqual(asked, 10, "the kernel answered for too few spellings with a doubled slash")
    }

    /// The literal start: the home directory's mount spelling and a scratch
    /// bundle's, with one slash doubled in turn, and with three more slashes
    /// put before the first. Which of them the kernel answers is printed with the answer of
    /// each gate; the gate is asked of all, and each is refused, because the
    /// empty parts the repeated slashes make are dropped before the prefix is
    /// read. The user gate is
    /// asked about the home directory, the app gate about the bundle.
    func testRepeatedSlashesInTheMountsSpellingAreRefusedWhetherOrNotTheKernelAnswers() throws {
        let scratch = try scratchFolderWithABundle()
        let homeMount = try volfsSpelling(of: homePath)
        let subjects: [(gate: Gate, mount: String, tail: String, object: String)] = [
            (.user, homeMount, "", homePath),
            (.app, scratch.mount, "/Foo.app", scratch.bundle.path),
        ]
        // The home directory is refused by its name as well, and a bundle in
        // a scratch folder is accepted by its own.
        var asked = 0
        for subject in subjects {
            let plain = subject.mount + subject.tail
            let wanted = identity(of: subject.object).object
            var spellings = [("///", "///" + plain)]
            for index in plain.indices.filter({ plain[$0] == "/" }) {
                var spelling = plain
                spelling.insert("/", at: index)
                spellings.append(("slash doubled at \(plain.distance(from: plain.startIndex, to: index))", spelling))
            }
            for (what, spelling) in spellings {
                let answers = identity(of: spelling).object == wanted
                print("[gates] mount, \(what): \(spelling.debugDescription): lstat \(reach(spelling)), "
                      + "kernel answers with the object = \(answers)")
                asked += 1
                assertRefused(spelling, by: subject.gate, object: subject.object,
                              home: scratch.folder.path, "mount, \(what)",
                              objectIsAccepted: subject.gate == .app)
            }
        }
        XCTAssertGreaterThan(asked, 4, "too few spellings were asked")
    }

    /// Ordinary folders named `.vol`, `.nofollow` and `.resolve` in a scratch
    /// folder, with a `..` run that pops each of them and lands where a link
    /// to nothing and a missing leaf are. These are names that only look like
    /// the kernel's prefixes, in front of nothing, so both gates accept the
    /// link and the missing leaf, spelled with the `..` and by their own name:
    /// a gate that refused every string with a `..` run after a prefix-like
    /// name would pass every row above.
    func testDotDotAfterFoldersNamedLikeTheKernelPrefixesIsAccepted() throws {
        let landing = scratchHome()
        try FileManager.default.createDirectory(at: landing.appendingPathComponent("Sub"),
                                                withIntermediateDirectories: true)
        for leaf in ["dead", "dead.app"] {
            try FileManager.default.createSymbolicLink(atPath: landing.path + "/Sub/" + leaf,
                                                       withDestinationPath: "nothing-" + leaf)
        }
        var asked = 0
        for (name, dots) in [(".vol", 3), (".nofollow", 4), (".resolve", 5)] {
            var deep = landing.appendingPathComponent(name)
            for level in 1..<dots { deep.appendPathComponent("level\(level)") }
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            let folder = deep.path + String(repeating: "/..", count: dots) + "/Sub"
            XCTAssertNotNil(identity(of: landing.path + "/Sub").object, "the scratch Sub is not there")
            XCTAssertEqual(identity(of: folder).object, identity(of: landing.path + "/Sub").object,
                           "\(folder) does not climb to the scratch Sub")
            for leaf in ["dead", "dead.app", "ghost.app"] {
                let spelling = folder + "/" + leaf
                let object = landing.path + "/Sub/" + leaf
                let reached = identity(of: spelling).object
                print("[gates] ordinary climb: \(spelling.debugDescription): lstat \(reach(spelling)), "
                      + "\(object) is \(reach(object))")
                XCTAssertEqual(reached, identity(of: object).object, "\(spelling) does not climb to \(object)")
                for gate in [Gate.user, Gate.app] where gate == .user || leaf.hasSuffix(".app") {
                    asked += 1
                    let answer = asks(gate, spelling, home: landing.path)
                    print("[gates] ordinary climb: \(gate.rawValue).isRemovable = \(answer)")
                    XCTAssertTrue(answer, "\(spelling) climbs out of ordinary folders and \(gate.rawValue) refuses it")
                }
            }
        }
        XCTAssertEqual(asked, 15, "a folder, a leaf or a gate was not asked")
    }

    // MARK: - A file reference path

    /// The path of the file reference URL for `path`, `/.file/id=<volume>.<inode>`
    /// with a slash after it for a folder, or nil when the system gives none.
    private func fileReferencePath(of path: String) -> String? {
        let url = NSURL(fileURLWithPath: path) as CFURL
        guard let reference = CFURLCreateFileReferenceURL(nil, url, nil)?.takeRetainedValue() else { return nil }
        return CFURLCopyPath(reference) as String
    }

    /// What Foundation calls the object a URL names: two URLs name one object
    /// when these are equal.
    private func resourceIdentifier(of url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject
    }

    /// A file reference path for a scratch bundle and for protected objects,
    /// and for something inside two of them. `lstat` of the string answers
    /// that it is not a directory; Foundation, which a removal reaches through
    /// `URL(fileURLWithPath:)`, turns the string into the object's real path.
    /// The test proves that Foundation reaches the object, then asserts that
    /// both gates refuse the protected ones; the scratch bundle's answers are
    /// printed beside the answers for its name.
    func testAFileReferencePathOfAProtectedObjectIsRefusedByBothGates() throws {
        let folder = scratchHome()
        let bundle = folder.appendingPathComponent("Foo.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let subjects: [(path: String, inside: String?, isProtected: Bool)] = [
            (bundle.path, nil, false), (homePath, nil, true), ("/usr/bin", "env", true),
            ("/System/Applications/Mail.app", "Contents", true),
        ]
        var asked = 0
        for subject in subjects {
            guard let reference = fileReferencePath(of: subject.path) else {
                print("[gates] file reference: the system gives no file reference URL for \(subject.path); not asked")
                continue
            }
            let url = URL(fileURLWithPath: reference)
            let named = resourceIdentifier(of: URL(fileURLWithPath: subject.path))
            let reaches = named != nil && resourceIdentifier(of: url)?.isEqual(named) == true
            print("[gates] file reference: \(subject.path) is \(reach(subject.path)); "
                  + "\(reference.debugDescription): lstat \(reach(reference)), "
                  + "fileExists(atPath:) \(FileManager.default.fileExists(atPath: reference)); "
                  + "URL(fileURLWithPath:).path \(url.path.debugDescription); "
                  + "Foundation reaches the object = \(reaches); "
                  + "resolvingAncestors \(PathCanonical.resolvingAncestors(reference).debugDescription)")
            guard reaches else { continue }
            let app = RemovableScope.isRemovable(reference, home: folder.path)
            let user = UserFileScope.isRemovable(reference)
            print("[gates] file reference: RemovableScope.isRemovable = \(app), "
                  + "UserFileScope.isRemovable = \(user); by its name \(RemovableScope.isRemovable(subject.path, home: folder.path)), "
                  + "\(UserFileScope.isRemovable(subject.path))")
            if subject.isProtected {
                asked += 1
                XCTAssertFalse(app, "\(reference) names \(subject.path) and RemovableScope accepts it")
                XCTAssertFalse(user, "\(reference) names \(subject.path) and UserFileScope accepts it")
            }
            guard let name = subject.inside else { continue }
            let inside = (reference.hasSuffix("/") ? reference : reference + "/") + name
            let insideObject = identity(of: URL(fileURLWithPath: inside).path).object
            print("[gates] file reference: \(inside.debugDescription) reaches "
                  + "\(insideObject.map { "\($0)" } ?? "nothing") through Foundation; "
                  + "\(subject.path + "/" + name) is \(reach(subject.path + "/" + name))")
            guard insideObject != nil, insideObject == identity(of: subject.path + "/" + name).object else { continue }
            asked += 1
            let insideApp = RemovableScope.isRemovable(inside, home: folder.path)
            let insideUser = UserFileScope.isRemovable(inside)
            print("[gates] file reference: RemovableScope.isRemovable(\(inside.debugDescription)) = \(insideApp), "
                  + "UserFileScope.isRemovable = \(insideUser)")
            XCTAssertFalse(insideApp, "\(inside) names something inside \(subject.path) and RemovableScope accepts it")
            XCTAssertFalse(insideUser, "\(inside) names something inside \(subject.path) and UserFileScope accepts it")
        }
        XCTAssertGreaterThan(asked, 0, "Foundation reached no object through a file reference path")
    }
}

// MARK: - One answer for one object

/// For every spelling of an existing object, each gate answers as it does for
/// the object's own name. The own name is what the kernel returns
/// (`KernelsOwnName`), not what the letters of the string make of it. Two kinds
/// of spelling are refused instead, whatever the own name's answer, and a row
/// that has one names it: a string that begins with a kernel prefix (the
/// mount), and a string the kernel takes for no object. Every other spelling
/// is held to the own name's answer, and its reading is asserted to be an
/// object first, so the answer is not excused by a reading that gave it no
/// name.
extension TheGatesRefuseAnObjectsOtherSpellingsTests {

    private func assertTheOwnAnswerOrRefused(_ spellings: [String], ownName: String, home: URL,
                                             _ tag: String, refused: Set<String> = []) {
        for gate in [Gate.user, Gate.app] {
            let own = asks(gate, ownName, home: home.path)
            for spelling in spellings {
                let answer = asks(gate, spelling, home: home.path)
                print("[gates] one answer, \(tag): \(gate.rawValue) \(spelling.debugDescription) = \(answer); "
                      + "by its own name \(ownName.debugDescription) = \(own)")
                if refused.contains(spelling) {
                    XCTAssertFalse(answer, "\(gate.rawValue) accepts \(spelling.debugDescription), which is refused "
                                   + "whatever the object's own name \(ownName.debugDescription) answers (\(own))")
                    continue
                }
                let entry = PathCanonical.readingForRemoval(spelling)
                XCTAssertEqual(entry.standing, .object,
                               "\(spelling.debugDescription) is not read as the object, so its answer is not "
                               + "held to the own name's")
                XCTAssertEqual(answer, own,
                               "\(gate.rawValue) answers \(spelling.debugDescription) \(answer) and the object's "
                               + "own name \(ownName.debugDescription) \(own)")
            }
        }
    }

    /// The spellings of a scratch folder: its name as typed, with the
    /// `/private` the volume hides, in upper case, behind the Data volume's
    /// firmlink, through `.`, `..`, doubled and trailing separators, through a
    /// link to its parent and through the mount. Each is proved to name the
    /// folder by the kernel before it is asked.
    func testEverySpellingOfAFolderGetsThePlainNamesAnswerOrIsRefused() throws {
        let home = scratchHome()
        let caches = home.appendingPathComponent("Library/Caches")
        let object = caches.appendingPathComponent("Cx/obj")
        try FileManager.default.createDirectory(at: object, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches.appendingPathComponent("Cx/sub"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(symlink(caches.path + "/Cx", caches.path + "/toCx"), 0)
        let ownName = try XCTUnwrap(KernelsOwnName.name(of: object.path), "the kernel gave the folder no name")
        let plain = object.path
        var spellings = [
            plain, ownName, plain.uppercased(), "/System/Volumes/Data" + ownName,
            "/PRIVATE" + (plain.hasPrefix("/var/") ? plain.uppercased() : plain),
            caches.path + "/./Cx/obj", caches.path + "/Cx/sub/../obj", caches.path + "/Cx//obj",
            plain + "/", plain + "//", caches.path + "/toCx/obj", caches.path + "/toCx/../Cx/obj",
        ]
        if let mount = try? volfsSpelling(of: plain) { spellings.append(mount) }
        let named = identity(of: plain)
        XCTAssertNotNil(named.object)
        for spelling in spellings {
            let through = identity(of: spelling, followingLinks: true)
            XCTAssertEqual(through.object, named.object,
                           "\(spelling.debugDescription) does not name the folder; the subject did not occur")
        }
        for gate in [Gate.user, Gate.app] {
            XCTAssertTrue(asks(gate, ownName, home: home.path),
                          "CONTROL: \(gate.rawValue) refuses the folder by its own name")
        }
        assertTheOwnAnswerOrRefused(spellings, ownName: ownName, home: home, "a folder",
                                    refused: Set(spellings.filter { $0.hasPrefix("/.vol/") }))
    }

    /// `/PRIVATE/VAR`, `/PRIVATE/ETC` and `/PRIVATE/TMP` are the
    /// objects `/private/var`, `/private/etc` and `/private/tmp`. Only asked,
    /// never created.
    func testPrivateVarEtcAndTmpInUpperCaseAreAnsweredAsTheirOwnNames() throws {
        let home = scratchHome()
        for name in ["VAR", "ETC", "TMP"] {
            let spelling = "/PRIVATE/" + name
            let ownName = try XCTUnwrap(KernelsOwnName.name(of: spelling), "the kernel gave \(spelling) no name")
            let same = identity(of: spelling, followingLinks: true).object
            XCTAssertNotNil(same)
            XCTAssertEqual(same, identity(of: ownName, followingLinks: true).object)
            assertTheOwnAnswerOrRefused([spelling], ownName: ownName, home: home, name)
        }
    }

    /// `..` after a link in the middle. The kernel walks the real
    /// parent of the link's target; the letters fold it away. A link to `/usr/bin`
    /// puts `local/bin/<name>` under `/usr`, which `UserFileScope` refuses by its
    /// name; a link to another folder puts `Library/Caches/app/x` outside the
    /// folder `RemovableScope` accepts it in.
    func testDotDotAfterALinkIsAnsweredWhereTheKernelWalks() throws {
        let home = scratchHome()
        XCTAssertEqual(symlink("/usr/bin", home.path + "/linkToUsr"), 0)
        let dangling = home.appendingPathComponent("local/bin")
        try FileManager.default.createDirectory(at: dangling, withIntermediateDirectories: true)
        XCTAssertEqual(symlink("no-such-target", dangling.path + "/X"), 0)
        let throughUsr = home.path + "/linkToUsr/../local/bin/X"
        let byLetters = home.path + "/local/bin/X"
        XCTAssertNil(identity(of: throughUsr).object, "the kernel reads \(throughUsr) as an object")
        XCTAssertNotNil(identity(of: byLetters).object, "the folded spelling is not there; the subject did not occur")
        let usrName = try XCTUnwrap(KernelsOwnName.name(of: "/usr/local/bin/X"), "/usr/local/bin is not there")
        assertTheOwnAnswerOrRefused([throughUsr], ownName: usrName, home: home, "a link to /usr/bin",
                                    refused: [throughUsr])

        let elsewhere = home.appendingPathComponent("Elsewhere")
        let landing = elsewhere.appendingPathComponent("Target")
        let object = elsewhere.appendingPathComponent("Library/Caches/app/x")
        try FileManager.default.createDirectory(at: landing, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: object.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: object.path, contents: Data("x".utf8)))
        XCTAssertEqual(symlink(landing.path, home.path + "/linkToTarget"), 0)
        let throughTarget = home.path + "/linkToTarget/../Library/Caches/app/x"
        XCTAssertEqual(identity(of: throughTarget).object, identity(of: object.path).object,
                       "the kernel does not walk \(throughTarget) to the file; the subject did not occur")
        let ownName = try XCTUnwrap(KernelsOwnName.name(of: object.path))
        assertTheOwnAnswerOrRefused([throughTarget], ownName: ownName, home: home, "a link to another folder")
    }

    /// a string that does not start with `/` as typed is not a
    /// path either gate can place. `UserFileScope` expanded `~` first and judged
    /// what it became.
    func testAStringThatDoesNotStartWithASlashAsTypedIsRefused() {
        let home = scratchHome()
        for string in ["~/Documents/x", "~/Library/Caches/com.example.app/x", "~", "Documents/x",
                       "./x/y", "~root/x"] {
            for gate in [Gate.user, Gate.app] {
                let answer = asks(gate, string, home: home.path)
                print("[gates] not absolute as typed: \(gate.rawValue) \(string.debugDescription) = \(answer)")
                XCTAssertFalse(answer, "\(gate.rawValue) accepts \(string.debugDescription), which does not start at /")
            }
        }
    }
}
