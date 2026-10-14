import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A removal gate approves one thing and the Trash must move that same thing:
/// the object the gate read, under the name the gate judged, reported under the
/// string the caller asked.
///
/// Most rows move nothing: `trashing` is a seam that records what it was
/// handed — the path, whether the URL is a file URL, and the `lstat` identity of
/// whatever that path names at the moment of the call — so a row that fails has
/// shown what the real `trashItem` would have been given. `gateThenTrash` is the
/// gate, then whatever a row does between the gate and the move, then the Trash
/// with the seam; a row that needs a gate's answer of its own, or hands
/// `remove(allowed:)` a string, calls them itself.
///
/// `testTheRealTrashMovesTheJudgedFileAndAnswersWithTheStringAsked` trashes for
/// real, with the default move, a scratch file asked for through `link/..`; it
/// finds its entry in the Trash by the leaf (which carries a UUID) and removes
/// that entry only, when its identity or its size is the file's. Because the
/// kernel resolves a spelling to the same file whichever string the move is
/// handed, that row shows the default move works on a judged name and that the
/// answer carries the asked string; what name the move is handed is held by the
/// seam rows, and a mutant that hands the move the asked string stays green
/// under that row.
///
/// The recheck is held row by row for what it compares: the object (a leaf
/// replaced), the parent alone (a hard link whose folder is swapped for a link
/// to the folder of the other name), and nothing at the path (still nothing, or
/// a file that appeared).
final class ARemovalMovesWhatTheGateJudgedTests: XCTestCase {

    /// What `trashing` was handed, and what its path named just then.
    private struct Call {
        let path: String
        let isFileURL: Bool
        let identity: PathCanonical.FileIdentity?
    }

    /// The recording seam: moves nothing.
    private final class Seam {
        var calls: [Call] = []
        func record(_ url: URL) {
            calls.append(Call(path: url.path, isFileURL: url.isFileURL,
                              identity: PathCanonical.identity(of: url.path)))
        }
    }

    private func bytes(_ string: String) -> [UInt8] { Array(string.utf8) }

    /// The folder as `realpath` spells it (`/private/var/…`, not `/var/…`), so a row
    /// about one respelling carries no other.
    private func kernelsSpelling(of folder: URL) throws -> URL {
        let resolved = try XCTUnwrap(realpath(folder.path, nil))
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    // MARK: - The helper the rows go through

    /// The gate, then `act` (whatever happens between the gate and the move),
    /// then the Trash with the seam for the move.
    private func gateThenTrash(_ paths: [String],
                               between act: () throws -> Void = {}) throws
        -> (result: HelmTrash.Result, calls: [Call]) {
        let seam = Seam()
        let (allowed, refused) = UserFileScope.gate(paths)
        try act()
        let result = HelmTrash.remove(gated: allowed, refused: refused, module: "test",
                                      trashing: seam.record)
        return (result, seam.calls)
    }

    /// The same name in either list of the answer: nothing is reported as neither.
    private func isAccountedFor(_ path: String, in result: HelmTrash.Result) -> Bool {
        let wanted = bytes(PathCanonical.withoutTrailingSeparators(path))
        return (result.removed + result.failed).contains { bytes($0) == wanted }
    }

    private func describe(_ calls: [Call]) -> String {
        calls.map { "\($0.path.debugDescription) names \(String(describing: $0.identity))" }
            .joined(separator: "; ")
    }

    // MARK: - 1. approved in one spelling, moved in another

    /// A string that does not start at `/` leads somewhere only from a working
    /// directory, and the move was handed `<working directory>/<string>`.
    func testARelativeStringIsNotMovedFromTheWorkingDirectory() {
        let relative = "helm-relative-\(UUID().uuidString)/leaf.txt"
        let cwd = FileManager.default.currentDirectoryPath
        let seam = Seam()

        let result = HelmTrash.remove(allowed: [relative], module: "test", trashing: seam.record)

        XCTAssertTrue(isAccountedFor(relative, in: result),
                      "the string is in neither list: removed \(result.removed), refused \(result.failed)")
        XCTAssertEqual(seam.calls.filter { bytes($0.path) == bytes(cwd + "/" + relative) }.count, 0,
                       "trashing was handed \(describe(seam.calls)) for the string \(relative.debugDescription), "
                       + "which the working directory \(cwd.debugDescription) turned into a place")
    }

    /// `<scratch>/link/../x` leads, for the kernel, to the parent of the link's
    /// target; the move was handed the letters.
    func testADotDotThroughALinkIsMovedUnderTheNameTheGateJudged() throws {
        let fm = FileManager.default
        let scratch = scratchDirectory("judged-dotdot")
        // The kernel's own spelling of the scratch folder, so the one difference
        // between the string and the name is the `..` through the link.
        let base = try kernelsSpelling(of: scratch)
        let target = base.appendingPathComponent("real/sub")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let leaf = try write("real/x.txt", in: base)
        try fm.createSymbolicLink(at: base.appendingPathComponent("link"), withDestinationURL: target)
        let spelling = base.path + "/link/../" + leaf.lastPathComponent

        let reading = PathCanonical.readingForRemoval(spelling)
        XCTAssertEqual(reading.standing, .object, "the subject did not occur: the string names no object")
        let judged = try XCTUnwrap(reading.judgedName)
        XCTAssertNotEqual(bytes(judged), bytes(spelling),
                          "the subject did not occur: the judged name is the string")
        XCTAssertTrue(UserFileScope.isRemovable(spelling), "the subject did not occur: the gate refuses it")

        let round = try gateThenTrash([spelling])

        XCTAssertEqual(round.calls.count, 1, "trashing ran \(round.calls.count) times, not once")
        XCTAssertTrue(round.calls.map { bytes($0.path) } == [bytes(judged)],
                       "the gate judged \(judged.debugDescription), trashing was handed "
                       + "\(round.calls.map(\.path)) for \(spelling.debugDescription)")
    }

    /// A level written in another case is the same place for the volume and
    /// another string for everything that compares letters.
    func testALevelInAnotherCaseIsMovedUnderTheNameTheGateJudged() throws {
        let scratch = scratchDirectory("judged-case")
        let base = try kernelsSpelling(of: scratch)
        let folder = "Box-\(UUID().uuidString)"
        let leaf = try write("\(folder)/x.txt", in: base)
        let spelling = base.path + "/" + folder.lowercased() + "/" + leaf.lastPathComponent
        try XCTSkipUnless(PathCanonical.identity(of: spelling) != nil,
                          "this volume tells the two cases apart: the spelling names nothing")

        let reading = PathCanonical.readingForRemoval(spelling)
        XCTAssertEqual(reading.standing, .object, "the subject did not occur: the string names no object")
        let judged = try XCTUnwrap(reading.judgedName)
        XCTAssertNotEqual(bytes(judged), bytes(spelling),
                          "the subject did not occur: the judged name is the string")
        XCTAssertTrue(UserFileScope.isRemovable(spelling), "the subject did not occur: the gate refuses it")

        let round = try gateThenTrash([spelling])

        XCTAssertEqual(round.calls.count, 1, "trashing ran \(round.calls.count) times, not once")
        XCTAssertTrue(round.calls.map { bytes($0.path) } == [bytes(judged)],
                       "the gate judged \(judged.debugDescription), trashing was handed "
                       + "\(round.calls.map(\.path)) for \(spelling.debugDescription)")
    }

    // MARK: - 2. an ancestor swapped between the gate and the batch

    /// The swap lands after the gate and before `HelmTrash.remove` starts, so a
    /// reference the batch takes for itself is taken after it.
    func testAnAncestorSwappedAfterTheGateReachesTheMoveAsNothingElse() throws {
        let fm = FileManager.default
        let scratch = scratchDirectory("swap-after-gate")
        let appdata = scratch.appendingPathComponent("appdata")
        let approved = try write("appdata/file.bin", in: scratch)
        let evil = scratch.appendingPathComponent("evil")
        let victim = try write("evil/file.bin", in: scratch)
        let approvedIdentity = try XCTUnwrap(PathCanonical.identity(of: approved.path))
        let victimIdentity = try XCTUnwrap(PathCanonical.identity(of: victim.path))
        XCTAssertNotEqual(approvedIdentity, victimIdentity)

        var swapped = false
        let round = try gateThenTrash([approved.path]) {
            try fm.moveItem(at: appdata, to: scratch.appendingPathComponent("appdata-real"))
            try fm.createSymbolicLink(at: appdata, withDestinationURL: evil)
            swapped = true
        }

        XCTAssertTrue(swapped, "the subject did not occur: the swap never ran")
        XCTAssertEqual(PathCanonical.identity(of: approved.path), victimIdentity,
                       "the subject did not occur: the approved path does not lead to the victim now")
        XCTAssertEqual(round.calls.filter { $0.identity != approvedIdentity }.count, 0,
                       "trashing was handed a path that names another object than the gate approved "
                       + "(approved \(approvedIdentity), victim \(victimIdentity)): \(describe(round.calls))")
        XCTAssertEqual(round.result.refused.filter { bytes($0.path) == bytes(approved.path) }.map(\.reason),
                       [.changedSinceScan], "removed \(round.result.removed)")
    }

    // MARK: - 3. a leaf replaced between the gate and the move

    func testALeafReplacedAfterTheGateIsNotMoved() throws {
        let fm = FileManager.default
        let scratch = scratchDirectory("leaf-replaced")
        let leaf = try write("leaf.bin", in: scratch, bytes: 64, filler: 0x41)
        let atTheGate = try XCTUnwrap(PathCanonical.identity(of: leaf.path))

        var replaced = false
        let round = try gateThenTrash([leaf.path]) {
            try fm.removeItem(at: leaf)
            try Data(repeating: 0x42, count: 64).write(to: leaf)
            replaced = true
        }

        let afterwards = try XCTUnwrap(PathCanonical.identity(of: leaf.path))
        XCTAssertTrue(replaced, "the subject did not occur: the leaf was never replaced")
        XCTAssertNotEqual(afterwards, atTheGate, "the subject did not occur: the leaf kept its identity")
        XCTAssertEqual(round.calls.filter { $0.identity != atTheGate }.count, 0,
                       "trashing was handed a leaf that is not the one the gate read "
                       + "(at the gate \(atTheGate)): \(describe(round.calls))")
        XCTAssertEqual(round.result.refused.filter { bytes($0.path) == bytes(leaf.path) }.map(\.reason),
                       [.changedSinceScan], "removed \(round.result.removed)")
    }

    // MARK: - 4. a path with nothing at it

    func testAPathWithNothingAtItNeverReachesTheMove() throws {
        let scratch = scratchDirectory("nothing-there")
        let gone = scratch.appendingPathComponent("gone-\(UUID().uuidString).txt").path
        let reading = PathCanonical.readingForRemoval(gone)
        XCTAssertEqual(reading.standing, .nothingThere, "the subject did not occur")
        XCTAssertTrue(UserFileScope.isRemovable(gone), "the subject did not occur: the gate refuses it")

        let round = try gateThenTrash([gone])

        XCTAssertEqual(round.calls.count, 0,
                       "trashing was handed a path with nothing at it: \(describe(round.calls))")
        XCTAssertTrue(isAccountedFor(gone, in: round.result),
                      "the path is in neither list: removed \(round.result.removed), "
                      + "refused \(round.result.failed)")
    }

    /// The other half of the same sentence: nothing at the gate and a file by
    /// the move is a file the gate never saw.
    func testAFileThatAppearedWhereTheGateSawNothingIsNotMoved() throws {
        let scratch = scratchDirectory("nothing-then-something")
        let late = scratch.appendingPathComponent("late-\(UUID().uuidString).txt")
        XCTAssertEqual(PathCanonical.readingForRemoval(late.path).standing, .nothingThere,
                       "the subject did not occur")

        var planted = false
        let round = try gateThenTrash([late.path]) {
            try Data(repeating: 0x43, count: 16).write(to: late)
            planted = true
        }

        XCTAssertTrue(planted, "the subject did not occur: nothing was planted")
        XCTAssertEqual(round.calls.count, 0,
                       "trashing was handed a file the gate never saw: \(describe(round.calls))")
        XCTAssertEqual(round.result.refused.filter { bytes($0.path) == bytes(late.path) }.map(\.reason),
                       [.changedSinceScan], "removed \(round.result.removed)")
    }

    // MARK: - 5. a typed file reference

    /// `/.file/id=<st_dev>.<inode>` names nothing to Foundation: the URL made
    /// from it has an empty path, and the real `trashItem` is never called with
    /// one (an empty path may mean the working directory).
    func testATypedFileReferenceNeverReachesTheMoveWithAnEmptyPath() throws {
        let scratch = scratchDirectory("typed-file-id")
        let file = try write("ref.bin", in: scratch)
        var info = stat()
        XCTAssertEqual(lstat(file.path, &info), 0)
        let typed = "/.file/id=\(UInt64(bitPattern: Int64(info.st_dev))).\(info.st_ino)"
        XCTAssertEqual(URL(fileURLWithPath: typed).path, "",
                       "the subject did not occur: Foundation gives this string a path")
        let seam = Seam()

        let result = HelmTrash.remove(allowed: [typed], module: "test", trashing: seam.record)

        XCTAssertEqual(seam.calls.filter { $0.path.isEmpty || !$0.isFileURL }.count, 0,
                       "trashing was handed a URL with no path for \(typed.debugDescription): "
                       + "\(seam.calls.map { "path \($0.path.debugDescription), file URL \($0.isFileURL)" })")
        XCTAssertTrue(isAccountedFor(typed, in: result),
                      "the string is in neither list: removed \(result.removed), refused \(result.failed)")
    }

    // MARK: - 6. a path below a folder that cannot be searched

    func testAPathBelowAFolderThatCannotBeSearchedIsRefusedAsUnreadable() throws {
        let fm = FileManager.default
        let scratch = scratchDirectory("no-search-bit")
        let locked = scratch.appendingPathComponent("locked")
        let inside = try write("locked/child.txt", in: scratch)
        // Registered after the scratch folder's own block, so it runs before it.
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        XCTAssertEqual(PathCanonical.readingForRemoval(inside.path).standing, .noAccess,
                       "the subject did not occur: the folder can be searched")

        let round = try gateThenTrash([inside.path])

        XCTAssertEqual(round.calls.count, 0, "trashing was handed \(describe(round.calls))")
        XCTAssertEqual(round.result.refused.filter { bytes($0.path) == bytes(inside.path) }.map(\.reason),
                       [.unreadable], "removed \(round.result.removed)")
    }

    // MARK: - Controls: what must stay as it is

    /// A refusal for a place is still a refusal for a place.
    func testAPlaceTheGateTurnsAwayIsStillOutOfScope() throws {
        let place = "/usr/bin/true"
        XCTAssertNotNil(PathCanonical.identity(of: place), "the subject did not occur: nothing at \(place)")

        let round = try gateThenTrash([place])

        XCTAssertEqual(round.calls.count, 0, "trashing was handed \(describe(round.calls))")
        XCTAssertEqual(round.result.refused.map(\.reason), [.outOfScope])
    }

    /// Nothing between the gate and the move: the object the gate read is moved.
    func testAnUntouchedFileIsHandedOverOnce() throws {
        let scratch = scratchDirectory("untouched")
        let leaf = try write("leaf.bin", in: scratch)
        let atTheGate = try XCTUnwrap(PathCanonical.identity(of: leaf.path))

        let round = try gateThenTrash([leaf.path])

        XCTAssertEqual(round.calls.map(\.identity), [atTheGate], "\(describe(round.calls))")
        XCTAssertEqual(round.result.removed.map { bytes($0) }, [bytes(leaf.path)])
        XCTAssertEqual(round.result.refused, [])
    }

    /// A file written in place keeps its identity, and is still what the gate
    /// read: the check is on who it is, not on when it was last written.
    func testAFileRewrittenInPlaceIsStillMoved() throws {
        let scratch = scratchDirectory("rewritten-in-place")
        let leaf = try write("leaf.bin", in: scratch)
        let atTheGate = try XCTUnwrap(PathCanonical.identity(of: leaf.path))

        let round = try gateThenTrash([leaf.path]) {
            let handle = try FileHandle(forWritingTo: leaf)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(repeating: 0x44, count: 32))
            try handle.close()
        }

        XCTAssertEqual(PathCanonical.identity(of: leaf.path), atTheGate,
                       "the subject did not occur: the identity changed")
        XCTAssertEqual(round.calls.map(\.identity), [atTheGate], "\(describe(round.calls))")
        XCTAssertEqual(round.result.refused, [])
    }

    // MARK: - 7. the parent alone

    /// One name of a hard-linked file stands in `a`, another in `b`. After the
    /// gate, `a` is moved away and a link to `b` is put where it stood: the
    /// judged name now leads to the very inode the gate read (through the
    /// other name), and only the folder it stands in is another.
    func testAParentThatChangedAloneIsNotMoved() throws {
        let fm = FileManager.default
        let scratch = scratchDirectory("parent-alone")
        let base = try kernelsSpelling(of: scratch)
        let first = try write("a/file.bin", in: base)
        let second = base.appendingPathComponent("b/file.bin")
        try fm.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.linkItem(at: first, to: second)
        let atTheGate = try XCTUnwrap(PathCanonical.identity(of: first.path))
        let parentAtTheGate = try XCTUnwrap(PathCanonical.ancestryIdentity(of: first.path))
        XCTAssertEqual(PathCanonical.identity(of: second.path), atTheGate,
                       "the subject did not occur: the two names are two files")

        var swapped = false
        let round = try gateThenTrash([first.path]) {
            try fm.moveItem(at: base.appendingPathComponent("a"), to: base.appendingPathComponent("a-away"))
            try fm.createSymbolicLink(at: base.appendingPathComponent("a"),
                                      withDestinationURL: base.appendingPathComponent("b"))
            swapped = true
        }

        XCTAssertTrue(swapped, "the subject did not occur: the swap never ran")
        XCTAssertEqual(PathCanonical.identity(of: first.path), atTheGate,
                       "the subject did not occur: the judged name leads to another object now")
        XCTAssertNotEqual(PathCanonical.ancestryIdentity(of: first.path), parentAtTheGate,
                          "the subject did not occur: the parent is the same folder")
        XCTAssertEqual(round.calls.count, 0,
                       "trashing was handed a name whose folder is not the one the gate read: \(describe(round.calls))")
        XCTAssertEqual(round.result.refused.filter { bytes($0.path) == bytes(first.path) }.map(\.reason),
                       [.changedSinceScan], "removed \(round.result.removed)")
    }

    // MARK: - 8. the string that was asked is the string that is answered

    /// Strings of every standing a gate meets: some it takes, some it turns
    /// away for a place, one for a folder it cannot search, and some that name
    /// no place at all.
    private func assortment(in base: URL, lockedChild: URL) throws -> [String] {
        let id = UUID().uuidString
        try FileManager.default.createDirectory(at: base.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        let taken = try write("taken-\(id).txt", in: base)
        let notThere = base.appendingPathComponent("gone-\(id).txt")
        var info = stat()
        XCTAssertEqual(lstat(taken.path, &info), 0)
        return [
            base.path + "/sub/../" + taken.lastPathComponent,
            notThere.path,
            "/usr/bin/../bin/true",
            "/usr/bin/true",
            "helm-relative-\(id)/leaf.txt",
            "",
            "/.file/id=\(UInt64(bitPattern: Int64(info.st_dev))).\(info.st_ino)",
            "/tmp/helm-\(id)\u{0}/leaf",
            lockedChild.path,
            base.path + "/Library/Caches/helm-c-\(id)/f.bin",
        ]
    }

    private func counted(_ strings: [String]) -> [[UInt8]: Int] {
        Dictionary(strings.map { (bytes($0), 1) }, uniquingKeysWith: +)
    }

    /// Both gates answer every string once, either as a `GatedPath` carrying
    /// it or as a refusal carrying it.
    func testEveryStringAGateIsAskedComesBackOnceAsAllowedOrRefused() throws {
        let fm = FileManager.default
        let scratch = scratchDirectory("gate-accounts")
        let base = try kernelsSpelling(of: scratch)
        let locked = base.appendingPathComponent("locked")
        let inside = try write("locked/child.txt", in: base)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let asked = try assortment(in: base, lockedChild: inside)
        // A path under the home's `Library/Caches/<name>` that is there, so
        // the narrower gate takes something as well.
        let cached = try write("Library/Caches/helm-c-\(UUID().uuidString)/f.bin", in: base).path
        let batch = asked + [cached]

        let user = UserFileScope.gate(batch)
        let removable = RemovableScope.gate(batch, home: base.path)

        for (name, answer) in [("UserFileScope", user), ("RemovableScope", removable)] {
            XCTAssertGreaterThan(answer.allowed.count, 0, "the subject did not occur: \(name) took nothing")
            XCTAssertGreaterThan(answer.refused.count, 0, "the subject did not occur: \(name) refused nothing")
            XCTAssertEqual(counted(answer.allowed.map(\.asked) + answer.refused.map(\.path)), counted(batch),
                           "\(name): allowed \(answer.allowed.map(\.asked)), refused \(answer.refused.map(\.path))")
        }
        XCTAssertTrue(removable.allowed.map { bytes($0.asked) }.contains(bytes(cached)),
                      "the subject did not occur: RemovableScope turned away a path under the home's Library")
        XCTAssertEqual(user.refused.filter { bytes($0.path) == bytes(inside.path) }.map(\.reason), [.unreadable])
    }

    /// The Trash answers every string of a gated batch once, under the string
    /// that was asked, and is handed nothing but the names the gate judged.
    func testEveryGatedStringIsRemovedOrRefusedUnderTheStringThatWasAsked() throws {
        let fm = FileManager.default
        let scratch = scratchDirectory("answer-asked")
        let base = try kernelsSpelling(of: scratch)
        let locked = base.appendingPathComponent("locked")
        let inside = try write("locked/child.txt", in: base)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let batch = try assortment(in: base, lockedChild: inside)
        // Strings by a spelling other than their judged name, and one the
        // gate takes and the move finds changed.
        let changed = try write("changed-\(UUID().uuidString).txt", in: base)
        let changedSpelling = base.path + "/sub/../" + changed.lastPathComponent
        let all = batch + [changedSpelling]
        let judgedMoved = base.appendingPathComponent(URL(fileURLWithPath: batch[0]).lastPathComponent).path

        let round = try gateThenTrash(all) {
            try fm.removeItem(at: changed)
            try Data(repeating: 0x45, count: 8).write(to: changed)
        }

        XCTAssertEqual(counted(round.result.removed + round.result.failed), counted(all),
                       "removed \(round.result.removed), refused \(round.result.failed)")
        XCTAssertEqual(round.result.removed.map { bytes($0) }, [bytes(batch[0])],
                       "the moved file is reported under another string than the one asked")
        XCTAssertEqual(round.calls.map { bytes($0.path) }, [bytes(judgedMoved)],
                       "trashing was handed \(round.calls.map(\.path)), not only the judged name of the first")
        let reasons = Dictionary(round.result.refused.map { (bytes($0.path), $0.reason) },
                                 uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(reasons[bytes(batch[1])], .missing)
        XCTAssertEqual(reasons[bytes(batch[2])], .outOfScope)
        XCTAssertEqual(reasons[bytes(inside.path)], .unreadable)
        XCTAssertEqual(reasons[bytes(changedSpelling)], .changedSinceScan)
    }

    /// A folder with a file in it, and `p`, `p/` and `p//` for it. A row that
    /// hands them to a gate first asserts that the gate took all three, which is
    /// what makes it about the Trash and not about a gate that refused.
    private func aFolderInThreeSpellings(_ label: String) throws -> (folder: URL, spellings: [String]) {
        let scratch = scratchDirectory(label)
        let folder = try kernelsSpelling(of: scratch).appendingPathComponent("box-\(UUID().uuidString)")
        try write("inside.bin", in: folder)
        return (folder, [folder.path, folder.path + "/", folder.path + "//"])
    }

    /// `p`, `p/` and `p//` are three strings for one folder, and a string
    /// handed twice is one string: each distinct string is answered once,
    /// under its own spelling, and the folder is handed to the move once (the
    /// seam moves nothing, so a second hand-over would show).
    func testSpellingsOfOneFolderAreEachAnsweredOnceAndMovedOnce() throws {
        let (folder, spellings) = try aFolderInThreeSpellings("spellings-moved")
        let batch = spellings + [spellings[0]]
        let seam = Seam()
        let (allowed, refused) = UserFileScope.gate(batch)
        XCTAssertEqual(Set(allowed.map { bytes($0.asked) }), Set(spellings.map { bytes($0) }),
                       "the subject did not occur: the gate refused \(refused)")

        let result = HelmTrash.remove(gated: allowed, refused: refused, module: "test",
                                      trashing: seam.record)

        XCTAssertEqual(counted(result.removed + result.failed), counted(spellings),
                       "removed \(result.removed), refused \(result.failed)")
        XCTAssertEqual(seam.calls.count, 1,
                       "trashing ran \(seam.calls.count) times for \(folder.lastPathComponent): \(describe(seam.calls))")
    }

    /// The same three spellings with a move that refuses: each is still
    /// answered once, as refused, and the folder is not offered to the move
    /// more than once for it.
    func testSpellingsOfOneFolderThatCannotBeMovedAreEachRefusedOnceAndOfferedOnce() throws {
        let (folder, spellings) = try aFolderInThreeSpellings("spellings-refused")
        var offered = 0
        let (allowed, refused) = UserFileScope.gate(spellings)
        XCTAssertEqual(allowed.count, spellings.count, "the subject did not occur: the gate refused \(refused)")

        let result = HelmTrash.remove(gated: allowed, refused: refused, module: "test",
                                      trashing: { _ in
            offered += 1
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        })

        XCTAssertEqual(counted(result.removed + result.failed), counted(spellings),
                       "removed \(result.removed), refused \(result.failed)")
        XCTAssertEqual(offered, 1, "the move was offered \(folder.lastPathComponent) \(offered) times")
        // The first spelling's reason is what the other two carry: three
        // refusals, one reason among them.
        XCTAssertEqual(result.refused.count, spellings.count, "refused \(result.refused)")
        XCTAssertEqual(Set(result.refused.map(\.reason)).count, 1,
                       "the spellings of one folder were refused for different reasons: \(result.refused)")
    }

    /// The first spelling is turned back before the move: the folder was swapped
    /// for another after the gate. The spellings that follow are refused as it
    /// was, for the same reason, and the move is never offered anything.
    func testSpellingsOfOneFolderRefusedBeforeTheMoveAreEachRefusedAsChanged() throws {
        let fm = FileManager.default
        let (folder, spellings) = try aFolderInThreeSpellings("spellings-changed")
        let aside = folder.deletingLastPathComponent().appendingPathComponent("aside-\(UUID().uuidString)")
        let atTheGate = try XCTUnwrap(PathCanonical.identity(of: folder.path))
        let (allowed, refused) = UserFileScope.gate(spellings)
        XCTAssertEqual(allowed.count, spellings.count, "the subject did not occur: the gate refused \(refused)")
        // Moved aside, not removed, so the new folder cannot take the old inode.
        try fm.moveItem(at: folder, to: aside)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let afterwards = try XCTUnwrap(PathCanonical.identity(of: folder.path))
        XCTAssertNotEqual(afterwards, atTheGate, "the subject did not occur: the folder kept its identity")
        let seam = Seam()

        let result = HelmTrash.remove(gated: allowed, refused: refused, module: "test",
                                      trashing: seam.record)

        XCTAssertEqual(seam.calls.count, 0, "trashing was handed \(describe(seam.calls))")
        XCTAssertEqual(result.removed, [], "removed \(result.removed)")
        XCTAssertEqual(counted(result.failed), counted(spellings), "refused \(result.failed)")
        XCTAssertEqual(result.refused.map(\.reason), Array(repeating: .changedSinceScan, count: spellings.count),
                       "refused \(result.refused)")
    }

    /// The entry that takes strings makes one entry of `p`, `p/` and `p//`, and
    /// answers it under the stripped string.
    func testSpellingsOfOnePathAreOneEntryForTheEntryThatTakesStrings() throws {
        let (folder, spellings) = try aFolderInThreeSpellings("spellings-strings")
        let seam = Seam()

        let result = HelmTrash.remove(allowed: spellings, module: "test", trashing: seam.record)

        XCTAssertEqual(seam.calls.count, 1, "\(describe(seam.calls))")
        XCTAssertEqual(result.removed.map { bytes($0) }, [bytes(folder.path)])
        XCTAssertEqual(result.refused, [])
    }

    /// A level in another case is reported under the case that was typed.
    func testALevelInAnotherCaseIsReportedUnderTheCaseThatWasAsked() throws {
        let scratch = scratchDirectory("asked-case")
        let base = try kernelsSpelling(of: scratch)
        let folder = "Box-\(UUID().uuidString)"
        let leaf = try write("\(folder)/x.txt", in: base)
        let spelling = base.path + "/" + folder.lowercased() + "/" + leaf.lastPathComponent
        try XCTSkipUnless(PathCanonical.identity(of: spelling) != nil,
                          "this volume tells the two cases apart: the spelling names nothing")

        let round = try gateThenTrash([spelling])

        XCTAssertEqual(round.result.removed.map { bytes($0) }, [bytes(spelling)])
        XCTAssertEqual(round.calls.map { bytes($0.path) }, [bytes(leaf.path)])
    }

    // MARK: - 9. the app clause

    /// With the clause on, a bundle outside every root may go; with it off the
    /// roots decide for a bundle as for anything else.
    func testAnAppOutsideEveryRootIsRefusedOnlyWhenTheAppClauseIsOff() throws {
        let scratch = scratchDirectory("app-clause")
        let home = try kernelsSpelling(of: scratch)
        let outside = try write("Downloads/Some-\(UUID().uuidString).app/Contents/x", in: home)
            .deletingLastPathComponent().deletingLastPathComponent().path
        let inside = try write("Applications/Some-\(UUID().uuidString).app/Contents/x", in: home)
            .deletingLastPathComponent().deletingLastPathComponent().path
        let cached = try write("Library/Caches/helm-\(UUID().uuidString)/f.bin", in: home)
            .deletingLastPathComponent().path
        for path in [outside, inside, cached] {
            XCTAssertNotNil(PathCanonical.identity(of: path), "the subject did not occur: nothing at \(path)")
        }
        let batch = [outside, inside, cached]

        XCTAssertTrue(RemovableScope.isRemovable(outside, home: home.path))
        XCTAssertTrue(RemovableScope.isRemovable(outside, home: home.path, anyAppBundle: true))
        XCTAssertEqual(RemovableScope.partition(batch, home: home.path).refused, [])
        XCTAssertEqual(RemovableScope.gate(batch, home: home.path).refused, [])

        XCTAssertFalse(RemovableScope.isRemovable(outside, home: home.path, anyAppBundle: false))
        let split = RemovableScope.partition(batch, home: home.path, anyAppBundle: false)
        XCTAssertEqual(split.refused.map { bytes($0) }, [bytes(outside)])
        XCTAssertEqual(split.allowed.map { bytes($0) }, [bytes(inside), bytes(cached)])
        let gated = RemovableScope.gate(batch, home: home.path, anyAppBundle: false)
        XCTAssertEqual(gated.refused, [HelmTrash.Refusal(path: outside, reason: .outOfScope)])
        XCTAssertEqual(gated.allowed.map { bytes($0.asked) }, [bytes(inside), bytes(cached)])
    }

    // MARK: - 10. the real Trash

    /// The real `trashItem`, through a gate and `remove(gated:)` with the
    /// default move, for a string whose judged name is another string. The
    /// entry is found by the leaf (it carries a UUID) and read by identity;
    /// only that one entry is removed from the Trash.
    func testTheRealTrashMovesTheJudgedFileAndAnswersWithTheStringAsked() throws {
        let fm = FileManager.default
        let scratch = trashScratchDirectory("real-judged")
        let base = try kernelsSpelling(of: scratch)
        let leafName = unownableLeaf("judged.txt")
        reclaimFromTrash(leafName)
        // `link/..` leads, for the kernel, to `real` (the parent of the link's
        // target); read letter by letter it leads to `base`.
        let target = base.appendingPathComponent("real/sub")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: base.appendingPathComponent("link"), withDestinationURL: target)
        let file = try write("real/" + leafName, in: base, bytes: 37, filler: 0x46)
        let original = try XCTUnwrap(PathCanonical.identity(of: file.path))
        let spelling = base.path + "/link/../" + leafName
        let reading = PathCanonical.readingForRemoval(spelling)
        XCTAssertEqual(reading.standing, .object, "the subject did not occur")
        XCTAssertEqual(reading.judgedName.map { bytes($0) }, bytes(file.path))
        XCTAssertNotEqual(bytes(spelling), bytes(file.path), "the subject did not occur: one spelling")

        let (allowed, refused) = UserFileScope.gate([spelling])
        XCTAssertEqual(allowed.count, 1, "the subject did not occur: the gate refused \(refused)")
        let result = HelmTrash.remove(gated: allowed, refused: refused, module: "test")

        let entry = userTrashDirectory().appendingPathComponent(leafName)
        let inTrash = PathCanonical.identity(of: entry.path)
        var info = stat()
        let size = lstat(entry.path, &info) == 0 ? Int(info.st_size) : -1
        // Only our own entry, by the identity or the size of what we wrote.
        if inTrash == original || size == 37 { try? fm.removeItem(at: entry) }

        XCTAssertEqual(result.removed.map { bytes($0) }, [bytes(spelling)], "refused \(result.refused)")
        XCTAssertEqual(result.refused, [])
        XCTAssertNil(PathCanonical.identity(of: file.path), "the file is still where it was")
        XCTAssertNotNil(inTrash, "no entry named \(leafName) in the Trash")
        if let inTrash, inTrash.device == original.device {
            XCTAssertEqual(inTrash, original, "the Trash holds another object than the one the gate read")
        }
        XCTAssertEqual(size, 37, "the entry in the Trash is not the file written")
    }
}
