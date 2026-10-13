import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// What the kernel calls an object and what it names it, asked the way the
/// gates' reading asks: `getattrlist` with the device, the object type, the
/// file id and the full path, not following a final link.
///
/// This is the test's own oracle. It shares no line with `PathCanonical`, so a
/// row that compares a gate's answer with "the object's own name" does not
/// compare the gate with itself.
enum KernelsOwnName {
    struct Answer {
        let type: UInt32
        let device: UInt32
        let fileID: UInt64
        let path: String
    }

    /// The object type the kernel answers for a directory (`VDIR`).
    static let directory: UInt32 = 2
    /// The object type the kernel answers for no object at all (`VNON`).
    static let none: UInt32 = 0

    static func ask(_ path: String, following: Bool) -> (answer: Answer?, error: Int32) {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_DEVID)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
            | attrgroup_t(ATTR_CMN_FULLPATH)
        var buffer = [UInt8](repeating: 0, count: 4096)
        let status = buffer.withUnsafeMutableBytes {
            getattrlist(path, &request, $0.baseAddress, $0.count,
                        following ? 0 : UInt32(FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return (nil, errno) }
        let answer = buffer.withUnsafeBytes { raw -> Answer in
            // Length (4), the returned attribute set (20), then the values in
            // the order the kernel packs them.
            var cursor = 4 + 20
            let device = raw.loadUnaligned(fromByteOffset: cursor, as: UInt32.self); cursor += 4
            let type = raw.loadUnaligned(fromByteOffset: cursor, as: UInt32.self); cursor += 4
            let fileID = raw.loadUnaligned(fromByteOffset: cursor, as: UInt64.self); cursor += 8
            let offset = Int(raw.loadUnaligned(fromByteOffset: cursor, as: Int32.self))
            let length = Int(raw.loadUnaligned(fromByteOffset: cursor + 4, as: UInt32.self))
            let start = cursor + offset
            let name = length > 1
                ? String(decoding: raw[start..<(start + length - 1)], as: UTF8.self) : ""
            return Answer(type: type, device: device, fileID: fileID, path: name)
        }
        return (answer, 0)
    }

    /// The name the kernel gives the object `path` names: a directory by its
    /// own returned path, anything else as the returned path of the string less
    /// its leaf, followed, plus the typed leaf. The cut is at the last `/`
    /// byte. `nil` when the kernel does not answer or the object is not one.
    static func name(of path: String) -> String? {
        if let direct = ask(path, following: false).answer, direct.type == directory {
            return direct.path
        }
        let bytes = Array(path.utf8)
        guard let cut = bytes.lastIndex(of: UInt8(ascii: "/")), cut > 0 else { return nil }
        let parent = String(decoding: bytes[..<cut], as: UTF8.self)
        let leaf = String(decoding: bytes[(cut + 1)...], as: UTF8.self)
        guard let above = ask(parent, following: true).answer, above.type == directory else {
            return nil
        }
        return above.path + "/" + leaf
    }

    /// The bytes of a name, in hex, for a failure message that has to show
    /// what `String` equality would not tell apart.
    static func hex(_ name: String) -> String {
        name.utf8.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

/// One reading of the object a string names, and one judgement of the name the
/// kernel gives it: the rows that showed where a gate judged the letters of a
/// path instead.
///
/// The gates used to cut, fold and compare the typed string, so a string the
/// kernel reads as one object and the letters read as another got the letters'
/// answer, and a string no component of which the letters can read (a file
/// reference path, a combining mark after a separator) either hung the
/// resolver or merged two names. The rows here ask the reading itself
/// (`PathCanonical.reading(of:)`), what is read from it (`resolvingAncestors`,
/// `ancestryIdentity`) and the gates' entry (`readingForRemoval`) where each
/// is the subject, and the gates' Bool answers, in a scratch folder; a real
/// place is only ever asked about, as a string.
///
/// **A string the resolver once never returned for is asked in a child
/// process first.** `/.file/id=<device>.<inode>` is asked in a child process,
/// the test bundle started again by `xctest` for the one entry method below,
/// under a kill timer, and in this process only after every child returned
/// (`testAFileReferencePathHasNoNameInTheReading`). The parent asserts on the
/// child's exit and on the file the child wrote, never on a thread of its own:
/// a hung call on a thread of the test process cannot be taken back, and it
/// was the way the first reading of this defect stopped a run. A child that
/// never wrote its marker is a mechanism that did not start, not a hang, and
/// is reported as that.
final class TheGatesTakeOneReadingOfTheObjectTests: XCTestCase {

    // MARK: - The child process

    private static let callKey = "HELM_GATE_CHILD_CALL"
    private static let stringKey = "HELM_GATE_CHILD_STRING"
    private static let homeKey = "HELM_GATE_CHILD_HOME"
    private static let markerKey = "HELM_GATE_CHILD_MARKER"
    private static let answerKey = "HELM_GATE_CHILD_ANSWER"

    /// How long a child that has started may take to answer one string. The
    /// start itself is this bundle's load; a call that has not returned in
    /// eight seconds is not slow.
    private static let seconds: TimeInterval = 8

    /// The entry the parent rows start as a child. Asked on its own, without
    /// the environment they give it, it has nothing to ask and skips.
    func testTheChildEntryAsksTheStringInTheEnvironment() throws {
        let env = ProcessInfo.processInfo.environment
        guard let call = env[Self.callKey], let string = env[Self.stringKey],
              let marker = env[Self.markerKey], let answerPath = env[Self.answerKey] else {
            throw XCTSkip("the entry of the child process the other rows start; it has no string to ask")
        }
        FileManager.default.createFile(atPath: marker, contents: Data())
        let home = env[Self.homeKey] ?? NSHomeDirectory()
        let answer: String
        switch call {
        case "resolve": answer = PathCanonical.resolvingAncestors(string)
        case "ancestry":
            answer = PathCanonical.ancestryIdentity(of: string)
                .map { "\($0.device).\($0.inode)" } ?? "nil"
        case "user": answer = String(UserFileScope.isRemovable(string))
        case "app": answer = String(RemovableScope.isRemovable(string, home: home))
        default:
            XCTFail("the parent asked the child for \(call), which it does not know")
            return
        }
        try? Data(answer.utf8).write(to: URL(fileURLWithPath: answerPath))
    }

    private struct ChildOutcome: CustomStringConvertible {
        let call: String
        let string: String
        let started: Bool
        let status: Int32
        let answer: String?

        var hung: Bool { started && status == HelmProcess.timedOutStatus }
        var returned: Bool { status == 0 && answer != nil }

        var description: String {
            let what: String
            if hung {
                what = "HUNG: started, did not return in \(Int(TheGatesTakeOneReadingOfTheObjectTests.seconds)) s, killed"
            } else if status == HelmProcess.timedOutStatus {
                what = "NEVER STARTED: no marker in \(Int(TheGatesTakeOneReadingOfTheObjectTests.seconds)) s, killed"
            } else {
                what = "exit \(status), answer \(answer?.debugDescription ?? "none")"
            }
            return "\(call)(\(string.debugDescription)) -> \(what)"
        }
    }

    /// The tool that runs a test bundle: the one this process is, when it is
    /// `xctest`, else the one `xcrun` finds.
    private func xctest() -> (path: String, leading: [String]) {
        let first = CommandLine.arguments[0]
        if first.hasSuffix("/xctest") { return (first, []) }
        return ("/usr/bin/xcrun", ["xctest"])
    }

    /// Each ask in a child process of its own, all at once, each under the
    /// timer. Order of the results is the order of the asks.
    private func inChildren(_ asks: [(call: String, string: String)], home: String,
                            folder: URL) -> [ChildOutcome] {
        let tool = xctest()
        let bundle = Bundle(for: TheGatesTakeOneReadingOfTheObjectTests.self).bundlePath
        let entry = "TheGatesTakeOneReadingOfTheObjectTests/testTheChildEntryAsksTheStringInTheEnvironment"
        let lock = NSLock()
        var outcomes = [ChildOutcome?](repeating: nil, count: asks.count)
        DispatchQueue.concurrentPerform(iterations: asks.count) { index in
            let marker = folder.appendingPathComponent("child-\(index).started").path
            let answer = folder.appendingPathComponent("child-\(index).answer").path
            let result = HelmProcess.run(
                tool.path, tool.leading + ["-XCTest", entry, bundle],
                env: [Self.callKey: asks[index].call, Self.stringKey: asks[index].string,
                      Self.homeKey: home, Self.markerKey: marker, Self.answerKey: answer],
                timeout: Self.seconds)
            let outcome = ChildOutcome(
                call: asks[index].call, string: asks[index].string,
                started: FileManager.default.fileExists(atPath: marker), status: result.status,
                answer: (try? String(contentsOfFile: answer, encoding: .utf8)))
            lock.lock(); outcomes[index] = outcome; lock.unlock()
        }
        return outcomes.compactMap { $0 }
    }

    /// `/.file/id=<device>.<inode>` of what is at `path`.
    private func fileReference(of path: String) throws -> String {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw XCTSkip("\(path) could not be read: \(String(cString: strerror(errno)))")
        }
        return "/.file/id=\(UInt32(bitPattern: info.st_dev)).\(info.st_ino)"
    }

    /// A scratch folder with a folder and a file in it, the references to both,
    /// and the proof that the kernel itself takes none of them for a path.
    private func fileReferences() throws -> (home: URL, strings: [String]) {
        let home = scratchDirectory("one-reading")
        let folder = home.appendingPathComponent("Library/Caches/Folder")
        let file = folder.appendingPathComponent("file.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8)))
        // The reference of a folder with a separator and with a child after it
        // is how Foundation hands such a path out and how it reaches the object.
        let reference = try fileReference(of: folder.path)
        let strings = ["/.file/id=1.2", reference, try fileReference(of: file.path),
                       reference + "/", reference + "/file.txt"]
        for string in strings {
            var info = stat()
            XCTAssertEqual(lstat(string, &info), -1, "\(string) is a path the kernel takes")
            print("[reading] the kernel on \(string): \(String(cString: strerror(errno)))")
        }
        return (home, strings)
    }

    // MARK: - The hang

    /// The two readings of a path that return an answer for a file reference
    /// path. The resolver used to read the URL made of it, which has an empty
    /// path, and neither exit of its loop was reachable from there.
    func testAResolverAskedForAFileReferenceReturns() throws {
        let (home, strings) = try fileReferences()
        let control = inChildren([("resolve", home.path)], home: home.path, folder: home)
        print("[reading] \(control[0])")
        XCTAssertTrue(control[0].returned && control[0].answer.map { Array($0.utf8) } == Array(home.path.utf8),
                      "CONTROL, the mechanism itself: \(control[0])")
        let asks = ["resolve", "ancestry"].flatMap { call in strings.map { (call: call, string: $0) } }
        let outcomes = inChildren(asks, home: home.path, folder: home)
        for outcome in outcomes {
            print("[reading] \(outcome)")
            XCTAssertTrue(outcome.returned, "\(outcome)")
        }
    }

    /// Both gates answer `false` for a file reference path, whether it names a
    /// folder, a file or nothing. The answer of a bound on the old loop was
    /// the same `false`, reached because the string it handed back was empty,
    /// which is why the next test compares the string itself.
    func testBothGatesRefuseAFileReferenceOfAScratchFolder() throws {
        let (home, strings) = try fileReferences()
        let control = inChildren([("app", home.path + "/Library/Caches/Folder/file.txt")],
                                 home: home.path, folder: home)
        print("[reading] \(control[0])")
        XCTAssertTrue(control[0].returned && control[0].answer == "true",
                      "CONTROL, the mechanism and the gate: \(control[0])")
        let asks = ["app", "user"].flatMap { call in strings.map { (call: call, string: $0) } }
        for outcome in inChildren(asks, home: home.path, folder: home) {
            print("[reading] \(outcome)")
            XCTAssertTrue(outcome.returned && outcome.answer == "false", "\(outcome)")
        }
    }

    /// The value of the projection for a file reference path: the deepest level
    /// the kernel answered as a directory is `/`, and the rest of the typed
    /// string follows it by its letters, so the typed string comes back, by
    /// bytes. A bound on the old loop let the call return an empty string, and
    /// this is the row that failed for it.
    func testTheResolverGivesAFileReferencePathBackAsTyped() throws {
        let (home, strings) = try fileReferences()
        let typed = strings.filter { !$0.hasSuffix("/") }
        let outcomes = inChildren(typed.map { (call: "resolve", string: $0) }, home: home.path, folder: home)
        XCTAssertEqual(outcomes.count, typed.count)
        for outcome in outcomes {
            print("[reading] \(outcome); the typed string's bytes \(KernelsOwnName.hex(outcome.string))")
            XCTAssertTrue(outcome.returned && outcome.answer.map { Array($0.utf8) } == Array(outcome.string.utf8),
                          "\(outcome); expected the typed string back, bytes \(KernelsOwnName.hex(outcome.string))")
        }
    }

    /// The reading itself, in this process, once the children have shown that
    /// it returns: a file reference path names no object and no place.
    func testAFileReferencePathHasNoNameInTheReading() throws {
        let (home, strings) = try fileReferences()
        let control = inChildren([("resolve", home.path)], home: home.path, folder: home)
        try XCTSkipUnless(control[0].returned, "the child mechanism did not start: \(control[0])")
        let hung = inChildren(strings.map { (call: "resolve", string: $0) }, home: home.path, folder: home)
            .filter { !$0.returned }
        XCTAssertTrue(hung.isEmpty, "the reading does not return for \(hung); not asked in this process")
        guard hung.isEmpty else { return }
        for string in strings { read(string, .noName, "is a file reference path; the kernel takes it for no path") }
    }

    // MARK: - Helpers for the rows that stay in this process

    private enum Gate: String, CaseIterable {
        case user = "UserFileScope", app = "RemovableScope"
    }

    private func answer(_ gate: Gate, _ path: String, home: URL) -> Bool {
        switch gate {
        case .user: return UserFileScope.isRemovable(path)
        case .app: return RemovableScope.isRemovable(path, home: home.path)
        }
    }

    /// Asks both gates, prints the line, and returns the pair.
    @discardableResult
    private func asked(_ path: String, home: URL, _ tag: String) -> [Gate: Bool] {
        var answers: [Gate: Bool] = [:]
        for gate in Gate.allCases { answers[gate] = answer(gate, path, home: home) }
        print("[reading] \(tag): \(path.debugDescription) -> "
              + Gate.allCases.map { "\($0.rawValue) \(answers[$0]!)" }.joined(separator: ", "))
        return answers
    }

    /// The reading of `path`, printed, with its standing asserted. A standing
    /// that is no name and no access also leaves a gate's entry with nothing
    /// to judge; an object and a path to nothing leave it the reading's own name.
    @discardableResult
    private func read(_ path: String, _ standing: PathCanonical.Reading.Standing, _ why: String,
                      file: StaticString = #filePath, line: UInt = #line) -> PathCanonical.Reading {
        let reading = PathCanonical.reading(of: path)
        print("[reading] \(path.debugDescription) -> \(reading.standing), name \(reading.name.debugDescription), "
              + "object \(reading.object.map { "\($0)" } ?? "none")")
        XCTAssertEqual(reading.standing, standing, "\(path.debugDescription) \(why)", file: file, line: line)
        let entry = PathCanonical.readingForRemoval(path)
        switch standing {
        case .noName, .noAccess:
            XCTAssertNil(entry.judgedName, "the gates' entry gives \(path.debugDescription) a name to judge: "
                         + "\(entry.judgedName.debugDescription)", file: file, line: line)
        case .object, .nothingThere:
            XCTAssertEqual(entry.judgedName.map { Array($0.utf8) }, Array(reading.name.utf8),
                           "the gates' entry judges another name than the reading's for \(path.debugDescription)",
                           file: file, line: line)
        }
        return reading
    }

    /// `lstat` of a path, without any of `PathCanonical`'s lines.
    private func ownIdentity(_ path: String, followingLinks: Bool = false) -> PathCanonical.FileIdentity? {
        var info = stat()
        let status = followingLinks ? stat(path, &info) : lstat(path, &info)
        guard status == 0 else { return nil }
        return PathCanonical.FileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: info.st_ino)
    }

    private func errnoOf(_ path: String) -> Int32 {
        var info = stat()
        return lstat(path, &info) == 0 ? 0 : errno
    }

    private func sameBytes(_ one: String, _ other: String) -> Bool {
        one.utf8.elementsEqual(other.utf8)
    }

    /// A scratch home with `Library/Caches` in it, which is a place `RemovableScope`
    /// accepts a child of when `home:` is this folder.
    private func scratchHomeWithCaches() throws -> (home: URL, caches: URL) {
        let home = scratchDirectory("one-reading")
        let caches = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        return (home, caches)
    }

    private func makeFile(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8)),
                      "could not make \(url.path)")
    }

    // MARK: - A level without the search bit

    /// A folder with mode 000 in an accepted place. The kernel answers EACCES
    /// for a child that exists and for one that does not alike, so the reading
    /// cannot tell the two apart and says "no access" for both, never "nothing
    /// there". The folder itself, and a file with no mode bits in a folder that
    /// can be searched, are there: the kernel answers for them.
    func testWhatIsBelowAFolderWithoutTheSearchBitIsNoAccess() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let locked = caches.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked.appendingPathComponent("kid"),
                                                withIntermediateDirectories: true)
        try makeFile(locked.appendingPathComponent("file.txt"))
        let open = caches.appendingPathComponent("Open/kid")
        try FileManager.default.createDirectory(at: open, withIntermediateDirectories: true)
        let secret = caches.appendingPathComponent("Open/secret.txt")
        try makeFile(secret)
        XCTAssertEqual(chmod(secret.path, 0o000), 0)
        XCTAssertEqual(chmod(locked.path, 0o000), 0)
        addTeardownBlock {
            _ = chmod(locked.path, 0o755)
            _ = chmod(secret.path, 0o644)
        }

        let beneath = ["kid", "file.txt", "missing", "kid/deeper", "missing/deeper/still"]
        for child in beneath {
            XCTAssertEqual(errnoOf(locked.path + "/" + child), EACCES,
                           "\(child) below mode 000 did not answer EACCES, the subject did not occur")
        }
        XCTAssertEqual(errnoOf(locked.path), 0, "the folder with no mode bits is not there")
        XCTAssertEqual(errnoOf(secret.path), 0, "the file with no mode bits is not there")

        let control = asked(open.path, home: home, "control: a child of a searchable folder")
        XCTAssertEqual(control[.app], true, "CONTROL: RemovableScope refuses an ordinary child of its own place")
        XCTAssertEqual(control[.user], true, "CONTROL: UserFileScope refuses an ordinary child of scratch")
        read(open.path, .object, "is there and its way can be read")
        read(caches.path + "/Open/missing", .nothingThere, "is not there and its way can be read")
        read(secret.path, .object, "is there; the kernel answers for a file whatever its mode")
        read(locked.path, .object, "is there; the kernel answers for a folder whatever its mode")

        for child in beneath {
            let path = locked.path + "/" + child
            read(path, .noAccess, "is below a folder whose search bit is off: not \"nothing there\", "
                 + "the kernel answers alike for what is there and what is not")
            let answers = asked(path, home: home, "below mode 000, \(child)")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false,
                               "\(gate.rawValue) accepts \(path), below a folder whose search bit is off")
            }
        }
    }

    // MARK: - A link to nothing, a loop, a file in the middle

    /// `<link to nothing>/x` names a place under the link's target, not under
    /// the folder the link is in: no name. The link itself is an object.
    func testAPathBelowALinkToNothingIsRefused() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("PL")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertEqual(symlink("no-such-target", folder.path + "/dangling"), 0)
        XCTAssertEqual(symlink(home.path + "/absent-too", folder.path + "/dangling-absolute"), 0)
        var info = stat()
        let status = stat(folder.path + "/dangling", &info)
        let code = errno
        XCTAssertEqual(status, -1)
        XCTAssertEqual(code, ENOENT, "the link has a target; the subject did not occur")
        let link = asked(folder.path + "/dangling", home: home, "control: the link itself")
        XCTAssertEqual(link[.app], true, "CONTROL: the link to nothing is an object RemovableScope accepts")
        XCTAssertEqual(link[.user], true, "CONTROL: the link to nothing is an object UserFileScope accepts")
        read(folder.path + "/dangling", .object, "is a link, an object whatever it points at")
        for string in [folder.path + "/dangling/x", folder.path + "/dangling-absolute/x/y"] {
            read(string, .noName, "is a place under a link to nothing")
            let answers = asked(string, home: home, "below a link to nothing")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(string), below a link to nothing")
            }
        }
    }

    /// A way the kernel cannot walk to its end is no name: a loop of links, a
    /// file where a folder should be, and the dots after either.
    func testAWayThatCannotBeWalkedHasNoName() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Way")
        try makeFile(folder.appendingPathComponent("file.txt"))
        XCTAssertEqual(symlink("loopB", folder.path + "/loopA"), 0)
        XCTAssertEqual(symlink("loopA", folder.path + "/loopB"), 0)
        XCTAssertEqual(errnoOf(folder.path + "/loopA/x"), ELOOP, "the loop is not one; the subject did not occur")
        XCTAssertEqual(errnoOf(folder.path + "/file.txt/x"), ENOTDIR, "the file is a folder; the subject did not occur")
        read(folder.path + "/loopA", .object, "is a link, an object, whatever it loops to")
        read(folder.path + "/file.txt", .object, "control: the file by its own name")
        for string in [folder.path + "/loopA/x", folder.path + "/loopA/x/y", folder.path + "/file.txt/x",
                       folder.path + "/file.txt/x/y", folder.path + "/file.txt/..",
                       folder.path + "/file.txt/../file.txt"] {
            read(string, .noName, "cannot be walked by the kernel")
            let answers = asked(string, home: home, "a way that cannot be walked")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(string)")
            }
        }
    }

    // MARK: - A missing level before ..

    /// `D/<missing>/../<existing>`: the letters fold it to an existing object,
    /// the kernel stops at the missing level. No name. Where every level the
    /// `..` climbs through is there, the kernel walks it and the object is
    /// named by its own name.
    func testAMissingLevelBeforeDotDotIsNotFoldedAway() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let existing = caches.appendingPathComponent("D/existing.txt")
        try makeFile(existing)
        try FileManager.default.createDirectory(at: caches.appendingPathComponent("D/sub"),
                                                withIntermediateDirectories: true)
        let spelling = caches.path + "/D/missing/../existing.txt"
        XCTAssertEqual(errnoOf(spelling), ENOENT, "the kernel reads \(spelling) as an object; the subject did not occur")
        let control = asked(existing.path, home: home, "control: the object by its own name")
        XCTAssertEqual(control[.app], true, "CONTROL: RemovableScope refuses the existing object")
        XCTAssertEqual(control[.user], true, "CONTROL: UserFileScope refuses the existing object")
        let own = try XCTUnwrap(KernelsOwnName.name(of: existing.path))
        XCTAssertTrue(sameBytes(read(existing.path, .object, "is there").name, own))

        read(spelling, .noName, "folds a missing level away by its letters")
        let answers = asked(spelling, home: home, "missing level, then ..")
        for gate in Gate.allCases {
            XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(spelling), which the kernel does not walk")
        }
        // A tail that holds a dot is no name, whatever the kernel says of the part before it.
        read(caches.path + "/D/missing/./existing.txt", .noName, "has a `.` in a tail that is not there")
        read(caches.path + "/D/missing/..", .noName, "ends in `..` below a level that is not there")
        // The same dots through levels that are there are walked by the kernel.
        for walked in [caches.path + "/D/./existing.txt", caches.path + "/D/sub/../existing.txt",
                       caches.path + "/D/../D/existing.txt"] {
            XCTAssertEqual(ownIdentity(walked), ownIdentity(existing.path), "\(walked) is not the object; the subject did not occur")
            let reading = read(walked, .object, "is walked by the kernel through levels that are there")
            XCTAssertTrue(sameBytes(reading.name, own), "\(walked) is not named by the kernel's name: \(KernelsOwnName.hex(reading.name))")
        }
        // A tail without a dot, below a level that is there, is a place.
        let nothing = read(caches.path + "/D/missing/x", .nothingThere, "is a place below a folder that is there")
        let ownFolder = try XCTUnwrap(KernelsOwnName.name(of: caches.path + "/D"))
        XCTAssertTrue(sameBytes(nothing.name, ownFolder + "/missing/x"))
    }

    // MARK: - The last component is a dot, and the root

    /// A string that ends in `.` or `..` is asked like any other, so its name is
    /// the kernel's for the folder it reaches, and it is no name for a rule. The
    /// root and its spellings are objects.
    func testALastComponentThatIsADotHasNoNameAndTheRootHasOne() throws {
        let (_, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Dots")
        try makeFile(folder.appendingPathComponent("x"))
        let own = try XCTUnwrap(KernelsOwnName.name(of: folder.path))
        let up = try XCTUnwrap(KernelsOwnName.name(of: caches.path))
        let dot = read(folder.path + "/.", .noName, "ends in `.`")
        XCTAssertTrue(sameBytes(dot.name, own), "the name of the string ending in `.` is \(KernelsOwnName.hex(dot.name))")
        let dotDot = read(folder.path + "/..", .noName, "ends in `..`")
        XCTAssertTrue(sameBytes(dotDot.name, up), "the name of the string ending in `..` is \(KernelsOwnName.hex(dotDot.name))")
        read(folder.path + "/./x", .object, "has a `.` in front of a leaf that is there")
        for root in ["/", "//", "///"] {
            let reading = read(root, .object, "is the root")
            XCTAssertTrue(sameBytes(reading.name, "/"), "the root is named \(reading.name.debugDescription)")
        }
        read("/.", .noName, "ends in `.`")
        read("/..", .noName, "ends in `..`")
        let gone = read("/helm-no-such-top-level-x", .nothingThere, "is a place below the root")
        XCTAssertTrue(sameBytes(gone.name, "/helm-no-such-top-level-x"))
    }

    // MARK: - /dev/fd/<n>

    /// A descriptor's name under `/dev/fd` is no name of any object: the kernel
    /// answers type none for it whatever the descriptor holds. First the premise,
    /// printed for a regular file, a directory and a pipe; then the reading gives
    /// each of them, and each with a component after it, no name, and both gates
    /// refuse.
    func testNoDescriptorSpellingIsJudgedAsAnObject() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Fd")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("file.txt")
        try makeFile(file)
        let directoryFD = open(folder.path, O_RDONLY)
        let fileFD = open(file.path, O_RDONLY)
        var pipeFDs: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&pipeFDs), 0)
        let held = [directoryFD, fileFD, pipeFDs[0], pipeFDs[1]]
        addTeardownBlock { for descriptor in held { close(descriptor) } }
        XCTAssertGreaterThan(directoryFD, 2)
        XCTAssertGreaterThan(fileFD, 2)

        let subjects = [("regular file", fileFD), ("directory", directoryFD), ("pipe", pipeFDs[0])]
        for (label, descriptor) in subjects {
            let path = "/dev/fd/\(descriptor)"
            let reading = KernelsOwnName.ask(path, following: false)
            print("[reading] the kernel on \(path), a \(label): type "
                  + (reading.answer.map { "\($0.type) (none is 0), returned \($0.path)" } ?? "no answer, errno \(reading.error)"))
            XCTAssertEqual(reading.answer?.type, KernelsOwnName.none,
                           "the kernel does not answer type none for \(path), a \(label)'s descriptor")
        }
        for (label, descriptor) in subjects {
            for string in ["/dev/fd/\(descriptor)", "/dev/fd/\(descriptor)/sub"] {
                read(string, .noName, "is a descriptor of a \(label), the object has no type")
                let answers = asked(string, home: home, "descriptor of a \(label)")
                for gate in Gate.allCases {
                    XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(string), a descriptor of a \(label)")
                }
            }
        }
        // `/dev/fd` itself, a folder, and `/dev/null` stay objects.
        read("/dev/fd", .object, "is a folder")
        read("/dev/null", .object, "is a device and it has a type")
    }

    // MARK: - A trailing separator on a link

    /// `<link>/`: told not to follow a last link the kernel follows it all the
    /// same when a separator comes after it, so a string handed over before the
    /// strip names the target. The reading of `link/`, `link//`, `link///` is the
    /// link's: its identity is `lstat` of the string without the separator, the
    /// name ends in the link and equals the name for the bare string by bytes.
    /// For a link to a folder, to `/usr` and to nothing.
    func testATrailingSeparatorOnALinkIsTheLinksOwnReading() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let target = home.appendingPathComponent("Elsewhere/Target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        XCTAssertEqual(symlink(target.path, caches.path + "/toFolder"), 0)
        XCTAssertEqual(symlink("/usr", caches.path + "/toUsr"), 0)
        XCTAssertEqual(symlink("no-such-target", caches.path + "/toNothing"), 0)
        for link in ["toFolder", "toUsr", "toNothing"] {
            let bare = caches.path + "/" + link
            let itself = try XCTUnwrap(ownIdentity(bare), "\(bare) is not there")
            let followed = ownIdentity(bare, followingLinks: true)
            if link != "toNothing" {
                XCTAssertNotNil(followed, "\(bare) leads nowhere")
                XCTAssertNotEqual(followed, itself, "the link and its target are one object; the subject did not occur")
            }
            let ownName = try XCTUnwrap(KernelsOwnName.name(of: bare))
            let bareReading = read(bare, .object, "is a link, an object")
            XCTAssertEqual(bareReading.object, itself, "the object of \(bare) is not the link's")
            XCTAssertTrue(sameBytes(bareReading.name, ownName), "\(bare) is named \(KernelsOwnName.hex(bareReading.name))")
            for separators in ["/", "//", "///"] {
                let string = bare + separators
                let reading = read(string, .object, "is the link with \(separators.count) trailing separator(s)")
                XCTAssertEqual(reading.object, itself, "\(string) names the target's identity, not the link's")
                XCTAssertTrue(reading.name.utf8.suffix(link.utf8.count + 1).elementsEqual(("/" + link).utf8),
                              "\(string) is named \(reading.name.debugDescription), which does not end in the link")
                XCTAssertTrue(sameBytes(reading.name, bareReading.name),
                              "\(string) is named \(KernelsOwnName.hex(reading.name)), the link without it \(KernelsOwnName.hex(bareReading.name))")
                XCTAssertEqual(reading.parent, bareReading.parent)
                let with = asked(string, home: home, "the link and \(separators.count) separator(s)")
                let without = asked(bare, home: home, "the link")
                for gate in Gate.allCases {
                    XCTAssertEqual(with[gate], without[gate],
                                   "\(gate.rawValue) answers \(string) otherwise than \(bare)")
                }
                XCTAssertEqual(PathCanonical.ancestryIdentity(of: string), PathCanonical.ancestryIdentity(of: bare))
                XCTAssertEqual(PathCanonical.resolvingAncestors(string), PathCanonical.resolvingAncestors(bare))
            }
        }
    }

    // MARK: - The prefixes the kernel keeps

    /// `/.nofollow<dir>` and `/.resolve/1<dir>` name the folder, and the path the
    /// kernel returns for them keeps the prefix. The gates' entry gives them no
    /// name and the kernel is not asked: its reading holds no object. The Bool is
    /// false through the test on the name as well, so it cannot tell the entry
    /// that asked from the entry that did not; the object can. The same for
    /// `/.resolve/1/<dir>` with a doubled separator after the number, which the
    /// kernel takes for the prefix, and for the mount. The other spellings of a
    /// prefix the predicate reads (another case, a doubled separator, a `.` or a
    /// `..` in front) the kernel takes for no prefix, so of them the row holds
    /// only that the entry gives them no name.
    func testTheGatesEntryGivesNoNameWhereTheKernelKeepsAPrefix() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Prefixed/App.app")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let control = asked(folder.path, home: home, "control: the folder by its own name")
        XCTAssertEqual(control[.app], true, "CONTROL: RemovableScope refuses the folder")
        XCTAssertEqual(control[.user], true, "CONTROL: UserFileScope refuses the folder")
        let plain = PathCanonical.readingForRemoval(folder.path)
        XCTAssertEqual(plain.standing, .object, "CONTROL: the entry reads the folder by its own name")
        XCTAssertNotNil(plain.object, "CONTROL: the entry asked the kernel about the folder")

        // The kernel's own name: the prefix with a path through a link in it
        // (`/var`) answers ELOOP, and then the bare reading holds no object.
        let own = try XCTUnwrap(KernelsOwnName.name(of: folder.path))
        for prefix in ["/.nofollow", "/.resolve/1"] {
            let string = prefix + own
            let bare = PathCanonical.reading(of: string)
            XCTAssertNotNil(bare.object, "the reading does not ask the kernel about \(string), so the entry's "
                            + "empty object says nothing about it")
            XCTAssertTrue(bare.name.hasPrefix(prefix), "the kernel does not keep \(prefix) in the name: "
                          + "\(bare.name.debugDescription)")
            let entry = PathCanonical.readingForRemoval(string)
            print("[reading] entry on \(string.debugDescription): \(entry.standing), name \(entry.name.debugDescription), "
                  + "object \(entry.object.map { "\($0)" } ?? "none"); the bare reading: \(bare.standing), "
                  + "object \(bare.object.map { "\($0)" } ?? "none")")
            XCTAssertEqual(entry.standing, .noName)
            XCTAssertNil(entry.judgedName)
            XCTAssertNil(entry.object, "the entry asked the kernel about \(string)")
            XCTAssertNil(entry.parent, "the entry asked the kernel about \(string)")
            let answers = asked(string, home: home, "behind \(prefix)")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(string)")
            }
        }
        // Built on the kernel's own name, with the premise per string. The
        // kernel takes `/.resolve/1//…` for the prefix, so the bare reading of
        // it holds an object and the entry's empty object is the entry not
        // asking. It takes none of the other four for a prefix (its answer for
        // each is that nothing is there, printed): the bare reading holds no
        // object either, so nothing is asserted about the entry's object for
        // them, only that it gives them no name.
        for (string, kernelTakesIt) in [("/.NOFOLLOW" + own, false), ("//.nofollow" + own, false),
                                        ("/./.resolve/1" + own, false), ("/usr/../.nofollow" + own, false),
                                        ("/.resolve/1/" + own, true)] {
            let bare = PathCanonical.reading(of: string)
            print("[reading] the bare reading of \(string.debugDescription): \(bare.standing), "
                  + "object \(bare.object.map { "\($0)" } ?? "none")")
            let entry = PathCanonical.readingForRemoval(string)
            XCTAssertEqual(entry.standing, .noName, "\(string.debugDescription)")
            XCTAssertNil(entry.judgedName, "\(string.debugDescription)")
            guard kernelTakesIt else { continue }
            XCTAssertNotNil(bare.object, "the bare reading of \(string.debugDescription) holds no object, so the "
                            + "entry's empty object says nothing about it")
            XCTAssertNil(entry.object, "the entry asked the kernel about \(string.debugDescription)")
        }

        // The mount: `/.vol/<device>/<inode>` of the folder, proved to answer for it.
        let identity = try XCTUnwrap(ownIdentity(folder.path))
        let mount = "/.vol/\(UInt32(truncatingIfNeeded: identity.device))/\(identity.inode)"
        try XCTSkipUnless(ownIdentity(mount, followingLinks: true) == identity, "\(mount) does not name the folder here")
        let mounted = PathCanonical.readingForRemoval(mount)
        XCTAssertEqual(mounted.standing, .noName)
        XCTAssertNil(mounted.object, "the entry asked the kernel about \(mount)")
    }

    /// The test on the name, after the ask: a link to `/` in front of the mount
    /// leaves the typed string without a prefix, and the name composed below
    /// the link begins in one. The bare reading calls that a path to nothing;
    /// the entry tests the name after the ask and gives it no name.
    func testTheGatesEntryTestsTheNameAfterTheAskToo() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("After")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("App.app"), withIntermediateDirectories: true)
        let identity = try XCTUnwrap(ownIdentity(folder.path))
        let mount = "/.vol/\(UInt32(truncatingIfNeeded: identity.device))/\(identity.inode)"
        try XCTSkipUnless(ownIdentity(mount, followingLinks: true) == identity, "\(mount) does not name the folder here")
        let link = caches.path + "/rootlink"
        XCTAssertEqual(symlink("/", link), 0)
        let typed = link + mount + "/App.app"
        XCTAssertFalse(PathCanonical.beginsWithAKernelPrefix(typed, resolved: typed),
                       "the typed string begins in a prefix, so this row does not hold the test after the ask")
        let bare = PathCanonical.reading(of: typed)
        print("[reading] \(typed.debugDescription): bare reading \(bare.standing), name \(bare.name.debugDescription), "
              + "object \(bare.object.map { "\($0)" } ?? "none")")
        // The kernel does not take the mount behind a link to `/` (`lstat` of
        // it answers that nothing is there), so the reading climbs through the
        // link to the root and composes the name below it: a path to nothing
        // that, but for the test on the name, a rule would judge.
        XCTAssertNil(ownIdentity(typed), "the kernel takes \(typed) for the bundle; the subject did not occur")
        XCTAssertEqual(bare.standing, .nothingThere, "the bare reading of \(typed) is \(bare.standing)")
        XCTAssertTrue(PathCanonical.beginsWithAKernelPrefix(typed, resolved: bare.name),
                      "the kernel's name \(bare.name.debugDescription) does not begin in a prefix; the subject did not occur")
        let entry = PathCanonical.readingForRemoval(typed)
        XCTAssertEqual(entry.standing, .noName, "the entry did not test the name after the ask")
        XCTAssertNil(entry.judgedName)
        XCTAssertTrue(sameBytes(entry.name, bare.name), "the entry named the string otherwise than the reading")
        let answers = asked(typed, home: home, "a link to / in front of the mount")
        for gate in Gate.allCases {
            XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(typed)")
        }
    }

    // MARK: - The name by bytes

    /// A name that begins with U+0301, in a folder asked in another case and
    /// through a link: the reading's name is the kernel's name for the folder,
    /// `/`, and the typed leaf, by `Array(name.utf8)`; a cut on characters would
    /// merge the leaf with the folder.
    func testANameBeginningWithACombiningMarkKeepsItsBytes() throws {
        let (_, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Folder10")
        let leaf = "\u{301}name.txt"
        let file = folder.path + "/" + leaf
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let handle = open(file, O_CREAT | O_WRONLY, 0o644)
        XCTAssertGreaterThan(handle, 2, "could not make the file; \(String(cString: strerror(errno)))")
        close(handle)
        XCTAssertEqual(symlink(folder.path, caches.path + "/toFolder10"), 0)
        let ownFolder = try XCTUnwrap(KernelsOwnName.name(of: folder.path))
        let expected = ownFolder + "/" + leaf
        let spellings = [file,
                         caches.path + "/FOLDER10/" + leaf,
                         caches.path + "/toFolder10/" + leaf,
                         caches.path + "/TOFOLDER10/" + leaf]
        for spelling in spellings {
            XCTAssertEqual(errnoOf(spelling), 0, "\(spelling) is not the file; the subject did not occur")
            let reading = read(spelling, .object, "is the file")
            XCTAssertTrue(sameBytes(reading.name, expected),
                          "the reading's name for \(spelling) is not the kernel's folder plus the leaf by bytes: "
                          + "got \(KernelsOwnName.hex(reading.name)); expected \(KernelsOwnName.hex(expected))")
            XCTAssertEqual(Array(reading.name.utf8.suffix(leaf.utf8.count + 1)), Array(("/" + leaf).utf8))
            XCTAssertTrue(sameBytes(PathCanonical.withoutPrivate(PathCanonical.resolvingAncestors(spelling)), PathCanonical.withoutPrivate(expected)),
                          "resolvingAncestors(\(spelling)) is not the kernel's folder plus the leaf by bytes")
        }
        let parts = PathCanonical.components(of: "/usr/\u{301}x")
        XCTAssertEqual(parts.map { Array($0.utf8) }, [Array("usr".utf8), [0xcc, 0x81, 0x78]],
                       "the cut at `/` merged the mark with the folder in front of it")
    }

    /// A folder created in NFC and asked in its NFD spelling, and the other way
    /// round: the reading's name is the name the volume gives the folder, by
    /// bytes, as created, and the gates answer as for the created spelling.
    func testAFolderAskedInTheOtherNormalisationIsNamedAsCreated() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let cases: [(created: String, asked: String)] = [
            ("Caf\u{e9}", "Cafe\u{301}"), ("Nfd-e\u{301}", "Nfd-\u{e9}"),
        ]
        for (created, askedAs) in cases {
            // By the system calls, with the bytes as spelled: a `URL` or a
            // `FileManager` call would hand the volume its own normalisation.
            let folder = caches.appendingPathComponent(created)
            XCTAssertEqual(mkdir(caches.path + "/" + created, 0o755), 0)
            let handle = open(caches.path + "/" + created + "/child.txt", O_CREAT | O_WRONLY, 0o644)
            XCTAssertGreaterThan(handle, 2)
            close(handle)
            let createdChild = caches.path + "/" + created + "/child.txt"
            let askedChild = caches.path + "/" + askedAs + "/child.txt"
            XCTAssertEqual(errnoOf(askedChild), 0, "the volume does not read \(askedAs) as \(created)")
            XCTAssertFalse(created.utf8.elementsEqual(askedAs.utf8), "the two spellings are one in bytes")
            let ownFolder = try XCTUnwrap(KernelsOwnName.name(of: folder.path))
            XCTAssertTrue(Array(ownFolder.utf8).suffix(created.utf8.count).elementsEqual(created.utf8),
                          "the kernel names the folder otherwise than created: \(KernelsOwnName.hex(ownFolder))")
            let expected = ownFolder + "/child.txt"
            let reading = read(askedChild, .object, "is the file in the folder created as \(created.debugDescription)")
            print("[reading] \(askedChild.debugDescription) -> \(reading.name.debugDescription); the kernel's name "
                  + "\(expected.debugDescription)")
            XCTAssertTrue(sameBytes(reading.name, expected),
                          "the reading's name for \(askedAs)/child.txt is not the created spelling by bytes: got "
                          + "\(KernelsOwnName.hex(reading.name)); the kernel's \(KernelsOwnName.hex(expected))")
            XCTAssertTrue(sameBytes(PathCanonical.withoutPrivate(PathCanonical.resolvingAncestors(askedChild)), PathCanonical.withoutPrivate(expected)),
                          "resolvingAncestors(\(askedAs)/child.txt) is not the created spelling by bytes")
            let byName = asked(createdChild, home: home, "created spelling")
            let byOther = asked(askedChild, home: home, "other spelling")
            for gate in Gate.allCases {
                XCTAssertEqual(byOther[gate], byName[gate],
                               "\(gate.rawValue) answers the other normalisation otherwise than the folder's own")
            }
        }
    }

    // MARK: - A name that begins with a combining mark under a refused place

    /// The gates cut the judged name at the `/` byte, so `/` followed by U+0301
    /// is a separator and a component of its own, and the component after a
    /// refused place does not merge with it. Asked as strings of real refused
    /// places; nothing is created. Each is refused, and the same name without
    /// the mark is the control that the place is refused.
    func testANameBeginningWithACombiningMarkUnderARefusedPlaceIsRefused() {
        let home = FileManager.default.temporaryDirectory
        let mark = "\u{301}"
        let cases: [(gate: Gate, place: String, name: String)] = [
            (.app, "/Applications/Utilities", "x.app"),
            (.app, "/System/Applications", "Mail.app"),
            (.user, "/usr", "x"),
            (.user, "/System", "x"),
            (.user, "/opt/homebrew/Cellar", "x"),
            (.user, "/private/var/db", "x"),
        ]
        for (gate, place, name) in cases {
            let plain = place + "/" + name
            let marked = place + "/" + mark + name
            XCTAssertFalse(answer(gate, plain, home: home), "CONTROL: \(gate.rawValue) accepts \(plain)")
            let accepted = answer(gate, marked, home: home)
            print("[reading] \(gate.rawValue): \(marked.debugDescription) [\(KernelsOwnName.hex(marked))] -> \(accepted)")
            XCTAssertFalse(accepted, "\(gate.rawValue) accepts \(marked.debugDescription), a name under \(place), bytes "
                           + KernelsOwnName.hex(marked))
        }
    }
}

// MARK: - What the reading did not have before: the rest of its input

extension TheGatesTakeOneReadingOfTheObjectTests {

    /// A NUL byte ends a C string, so a call handed the typed string would ask
    /// about a shorter one than the one judged. The reading gives a string that
    /// holds one no name; the control is the string a C call would see, which
    /// is an object the gates accept.
    func testAStringHoldingANulByteHasNoName() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Nul/Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let asCSeesIt = folder.path
        read(asCSeesIt, .object, "control: the string a C call would see")
        let control = asked(asCSeesIt, home: home, "control: what a C call would see")
        XCTAssertEqual(control[.app], true)
        XCTAssertEqual(control[.user], true)
        for string in [asCSeesIt + "\u{0}", asCSeesIt + "\u{0}/x", "\u{0}" + asCSeesIt, caches.path + "/Nul\u{0}/Folder"] {
            let reading = read(string, .noName, "holds a NUL byte")
            XCTAssertNil(reading.object)
            XCTAssertNil(reading.parent)
            XCTAssertTrue(sameBytes(reading.name, string), "the name of a string with a NUL byte is not the string")
            XCTAssertTrue(sameBytes(PathCanonical.resolvingAncestors(string), string),
                          "the projection of a string with a NUL byte is not the string")
            XCTAssertNil(PathCanonical.ancestryIdentity(of: string))
            let answers = asked(string, home: home, "a NUL byte")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(string.debugDescription)")
            }
        }
    }

    /// Strings the kernel cannot take for their length: a component over 255
    /// bytes, a string over 1024. Each is asked in a child process first, so a
    /// climb that does not end is a hung child and not a hung run; then in this
    /// one. A component of 255 bytes is a place, and the gates accept it.
    func testAStringThatIsTooLongReturnsAndHasNoName() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let base = caches.path
        let tooLong: [(label: String, string: String)] = [
            ("a component of 256 bytes", base + "/" + String(repeating: "c", count: 256)),
            ("a component of 300 bytes and a child", base + "/" + String(repeating: "c", count: 300) + "/x"),
            ("one component that takes the string over 1024 bytes", base + "/" + String(repeating: "d", count: 1100)),
            ("600 short components", base + String(repeating: "/a", count: 600)),
            ("700 short components from the root", String(repeating: "/a", count: 700)),
        ]
        let fits = base + "/" + String(repeating: "c", count: 255)
        XCTAssertEqual(errnoOf(fits), ENOENT, "255 bytes is not a name the volume takes; the subject did not occur")
        for (label, string) in tooLong {
            XCTAssertEqual(errnoOf(string), ENAMETOOLONG, "\(label): the kernel does not say too long; the subject did not occur")
        }

        let control = inChildren([("app", fits)], home: home.path, folder: home)
        XCTAssertTrue(control[0].returned && control[0].answer == "true", "CONTROL, the mechanism and the gate: \(control[0])")
        var asks: [(call: String, string: String)] = []
        for (_, string) in tooLong {
            asks.append(("app", string)); asks.append(("user", string)); asks.append(("resolve", string))
        }
        for outcome in inChildren(asks, home: home.path, folder: home) {
            print("[reading] \(outcome)")
            XCTAssertTrue(outcome.returned, "\(outcome)")
            if outcome.call != "resolve" { XCTAssertEqual(outcome.answer, "false", "\(outcome)") }
        }

        let place = read(fits, .nothingThere, "is the longest name the volume takes, and it is not there")
        let ownBase = try XCTUnwrap(KernelsOwnName.name(of: base))
        XCTAssertTrue(sameBytes(place.name, ownBase + "/" + String(repeating: "c", count: 255)))
        let answers = asked(fits, home: home, "a component of 255 bytes")
        XCTAssertEqual(answers[.app], true)
        XCTAssertEqual(answers[.user], true)
        for (label, string) in tooLong {
            read(string, .noName, "is \(label)")
        }
    }

    /// A string that does not start with the `/` byte is no name, whatever the
    /// working directory holds: `ancestryIdentity` gives nothing for it and
    /// `resolvingAncestors` hands it back untouched. A relative spelling of a
    /// real folder is proved to reach it first.
    func testARelativeStringIsNoNameAndIsHandedBackUntouched() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Rel/Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let depth = FileManager.default.currentDirectoryPath.split(separator: "/").count
        let relative = String(repeating: "../", count: depth) + String(folder.path.dropFirst())
        XCTAssertEqual(ownIdentity(relative), ownIdentity(folder.path),
                       "\(relative) does not reach the folder from the working directory; the subject did not occur")
        XCTAssertNotNil(PathCanonical.ancestryIdentity(of: folder.path), "CONTROL: the absolute spelling has a parent")
        for string in [relative, "", "relative/path", "./x", "../x", "~/x", "x", " " + folder.path, "\u{301}" + folder.path] {
            let reading = read(string, .noName, "does not start with `/`")
            XCTAssertNil(reading.object)
            XCTAssertNil(PathCanonical.ancestryIdentity(of: string), "\(string.debugDescription) has a parent")
            XCTAssertTrue(sameBytes(PathCanonical.resolvingAncestors(string), string),
                          "resolvingAncestors changed \(string.debugDescription) into \(PathCanonical.resolvingAncestors(string).debugDescription)")
            let answers = asked(string, home: home, "not absolute as typed")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(string.debugDescription)")
            }
        }
    }

    /// The projection and the reading do not spell one name alike: the kernel
    /// names what is under `/var`, `/tmp` and `/etc` with `/private` in front,
    /// and `resolvingAncestors` leaves it out, as Foundation does, which is what
    /// its callers compare it with. Both by bytes, for a scratch folder, for a
    /// string typed with the `/private`, and for places that are not made here.
    func testTheProjectionKeepsTheSpellingFoundationUsesWhileTheReadingKeepsTheKernels() throws {
        let scratch = scratchDirectory("one-reading")
        let kernel = try XCTUnwrap(KernelsOwnName.name(of: scratch.path))
        try XCTSkipUnless(kernel.hasPrefix("/private/var/"), "the scratch folder is not under /private/var here: \(kernel)")
        let foundation = String(kernel.dropFirst("/private".count))
        for suffix in ["", "/missing", "/missing/deeper"] {
            for typed in [scratch.path + suffix, kernel + suffix] {
                let reading = PathCanonical.reading(of: typed)
                XCTAssertTrue(sameBytes(reading.name, kernel + suffix),
                              "the reading's name for \(typed) is \(KernelsOwnName.hex(reading.name)), not the kernel's")
                let projected = PathCanonical.resolvingAncestors(typed)
                XCTAssertTrue(sameBytes(projected, foundation + suffix),
                              "the projection of \(typed) is \(KernelsOwnName.hex(projected)), not the Foundation spelling "
                              + KernelsOwnName.hex(foundation + suffix))
            }
        }
        for (typed, name, projection) in [
            ("/tmp/helm-no-such-x/y", "/private/tmp/helm-no-such-x/y", "/tmp/helm-no-such-x/y"),
            ("/etc/helm-no-such-x", "/private/etc/helm-no-such-x", "/etc/helm-no-such-x"),
            ("/private/etc/helm-no-such-x", "/private/etc/helm-no-such-x", "/etc/helm-no-such-x"),
            ("/private/tmpx/y", "/private/tmpx/y", "/private/tmpx/y"),
            ("/private/varx", "/private/varx", "/private/varx"),
            ("/private/var", "/private/var", "/var"),
        ] {
            let reading = PathCanonical.reading(of: typed)
            XCTAssertTrue(sameBytes(reading.name, name), "the reading's name for \(typed) is \(reading.name.debugDescription)")
            XCTAssertTrue(sameBytes(PathCanonical.resolvingAncestors(typed), projection),
                          "the projection of \(typed) is \(PathCanonical.resolvingAncestors(typed).debugDescription)")
        }
    }

    /// `/private/x`-shaped strings. The depth guard of `UserFileScope` counts
    /// the name without its `/private`, so a name directly under `/private`,
    /// and `/var`, `/tmp` and `/etc` themselves, are top-level folders of the
    /// volume and refused, in any case. A folder deeper than that, here a
    /// scratch folder under `/private/var`, is accepted.
    func testANameDirectlyUnderPrivateIsRefusedByTheDepthGuard() throws {
        let scratch = scratchDirectory("one-reading")
        XCTAssertTrue(UserFileScope.isRemovable(scratch.path + "/x"), "CONTROL: UserFileScope refuses a scratch folder's child")
        for string in ["/private", "/private/x", "/private/tftpboot", "/PRIVATE/x", "/private//x", "/private/x/",
                       "/var", "/var/", "/tmp", "/etc", "/VAR", "/private/var", "/private/tmp", "/private/etc"] {
            XCTAssertFalse(UserFileScope.isRemovable(string), "UserFileScope accepts \(string)")
        }
        let gone = PathCanonical.reading(of: "/private/x")
        XCTAssertEqual(gone.standing, .nothingThere, "CONTROL: /private/x is a place, so the refusal is the depth guard's")
        XCTAssertTrue(sameBytes(gone.name, "/private/x"))
    }

    /// `<scratch>/FOO.APP` for a folder `Foo.app`: the kernel's name for it ends
    /// in `Foo.app`, so a rule about the end of a name takes it, as it takes the
    /// kernel's own name. Both gates answer for the string as they do for the
    /// name, and `RemovableScope` accepts both.
    func testAFolderAskedInUpperCaseIsJudgedAsTheKernelNamesIt() throws {
        let home = scratchDirectory("one-reading")
        let bundle = home.appendingPathComponent("Foo.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let typed = home.path + "/FOO.APP"
        try XCTSkipUnless(ownIdentity(typed, followingLinks: true) == ownIdentity(bundle.path),
                          "the volume reads \(typed) as another object: it is case-sensitive")
        let own = try XCTUnwrap(KernelsOwnName.name(of: bundle.path))
        let reading = read(typed, .object, "is the bundle in another case")
        XCTAssertTrue(sameBytes(reading.name, own), "the reading's name is \(KernelsOwnName.hex(reading.name)), the kernel's \(KernelsOwnName.hex(own))")
        XCTAssertTrue(own.hasSuffix("/Foo.app"))
        XCTAssertTrue(answer(.app, own, home: home), "CONTROL: RemovableScope refuses the bundle by the kernel's own name")
        for gate in Gate.allCases {
            XCTAssertEqual(answer(gate, typed, home: home), answer(gate, own, home: home),
                           "\(gate.rawValue) answers \(typed) otherwise than the kernel's name for it")
        }
        XCTAssertTrue(answer(.app, typed, home: home), "RemovableScope refuses the bundle in upper case")
    }

    /// The identity of the folder above a leaf, as `ancestryIdentity` gives it:
    /// the folder with links followed, nothing where the level above is not
    /// there or is no folder.
    func testTheFolderAboveALeafIsReadWithLinksFollowed() throws {
        let (_, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Above")
        try makeFile(folder.appendingPathComponent("file.txt"))
        XCTAssertEqual(symlink(folder.path, caches.path + "/toAbove"), 0)
        let expected = try XCTUnwrap(ownIdentity(folder.path))
        func identity(_ string: String) -> PathCanonical.AncestryIdentity? { PathCanonical.ancestryIdentity(of: string) }
        let folderOnly = PathCanonical.AncestryIdentity(device: expected.device, inode: expected.inode)
        XCTAssertEqual(identity(folder.path + "/file.txt"), folderOnly)
        XCTAssertEqual(identity(folder.path + "/missing"), folderOnly)
        XCTAssertEqual(identity(caches.path + "/toAbove/file.txt"), folderOnly, "the link in the middle is followed")
        XCTAssertEqual(identity(caches.path + "/toAbove/missing"), folderOnly)
        XCTAssertNil(identity(folder.path + "/missing/deeper"), "the level above is not there")
        XCTAssertNil(identity(folder.path + "/file.txt/deeper"), "the level above is a file")
    }
}

// MARK: - The prefix behind /private, the projection's fold, what was asked

extension TheGatesTakeOneReadingOfTheObjectTests {

    private func makeFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// `/private/.vol/…`, `/private/.nofollow…` and `/private/.resolve/1…`, in
    /// both cases of the front. The kernel answers each with `ENOENT`, so the
    /// reading's name is `/private`, in the case the disk holds, and the rest
    /// of the string as typed, and a name that begins with `/private` is not
    /// read as a prefix by the letters; the gates' entry tests the name
    /// without it. Asked only: the folders the strings would reach are a
    /// scratch folder and, as strings, real places.
    func testAKernelPrefixBehindPrivateIsNoNameAndBothGatesRefuseIt() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Behind/App.app")
        try makeFolder(folder)
        let control = asked(folder.path, home: home, "control: the folder by its own name")
        XCTAssertEqual(control[.app], true, "CONTROL: RemovableScope refuses the folder")
        XCTAssertEqual(control[.user], true, "CONTROL: UserFileScope refuses the folder")
        let own = try XCTUnwrap(KernelsOwnName.name(of: folder.path))
        let pair = try XCTUnwrap(ownIdentity(folder.path))
        let mount = "/.vol/\(UInt32(truncatingIfNeeded: pair.device))/\(pair.inode)"
        var homeInfo = stat()
        XCTAssertEqual(lstat(NSHomeDirectory(), &homeInfo), 0, "the home directory could not be read")
        let homeMount = "/.vol/\(UInt32(bitPattern: homeInfo.st_dev))/\(homeInfo.st_ino)"

        var strings: [String] = []
        for front in ["/private", "/PRIVATE"] {
            strings += [front + mount, front + mount + "/Sub/x.app", front + "/.nofollow" + own,
                        front + "/.resolve/1" + own,
                        front + homeMount, front + "/.nofollow/System/Applications/Mail.app",
                        front + "/.nofollow" + NSHomeDirectory(), front + "/.resolve/1" + NSHomeDirectory()]
        }
        for string in strings {
            XCTAssertEqual(errnoOf(string), ENOENT, "the kernel takes \(string.debugDescription) for a path; "
                           + "the subject did not occur")
            let bare = PathCanonical.reading(of: string)
            let expectedName = "/private" + String(string.dropFirst("/private".count))
            print("[reading] behind /private: \(string.debugDescription) -> bare \(bare.standing), "
                  + "name \(bare.name.debugDescription)")
            XCTAssertEqual(bare.standing, .nothingThere, "\(string.debugDescription) is a path to nothing")
            XCTAssertNil(bare.object)
            XCTAssertTrue(sameBytes(bare.name, expectedName),
                          "the bare reading names \(string.debugDescription) \(bare.name.debugDescription), "
                          + "not \(expectedName.debugDescription)")
            let entry = PathCanonical.readingForRemoval(string)
            XCTAssertEqual(entry.standing, .noName, "the gates' entry reads \(string.debugDescription) as \(entry.standing)")
            XCTAssertNil(entry.judgedName, "the gates' entry gives \(string.debugDescription) a name to judge")
            XCTAssertNil(entry.object)
            let answers = asked(string, home: home, "behind /private")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(string.debugDescription)")
            }
        }
    }

    /// In the part of a string the kernel did not answer for, `resolvingAncestors`
    /// folds `.` and `..` by their letters, under the path the kernel gave the
    /// deepest folder that answered; the reading keeps that part as typed and
    /// gives it no name. Where the kernel answers for a link to a folder before a
    /// `..`, the path stands as the kernel climbs it and the letters fold nothing.
    func testTheProjectionFoldsOnlyWhatTheKernelDidNotAnswerFor() throws {
        let home = scratchDirectory("after-repair")
        struct Case {
            let label: String, root: URL, typed: String, top: String, rest: String, folded: String
            let premise: Int32
        }
        var cases: [Case] = []
        for kind in ["absent", "file", "link"] {
            let root = home.appendingPathComponent(kind)
            try makeFolder(root.appendingPathComponent(".ssh"))
            try makeFile(root.appendingPathComponent("outside.txt"))
            try makeFile(root.appendingPathComponent("target.txt"))
            let place = root.appendingPathComponent(".ssh/missing")
            if kind == "file" { try makeFile(place) }
            if kind == "link" { XCTAssertEqual(symlink(root.path + "/target.txt", place.path), 0) }
            cases.append(Case(label: "\(kind) before ..", root: root,
                              typed: root.path + "/.ssh/missing/../../outside.txt",
                              top: root.path + "/.ssh", rest: "missing/../../outside.txt",
                              folded: "/outside.txt", premise: kind == "absent" ? ENOENT : ENOTDIR))
        }
        let bundleRoot = home.appendingPathComponent("bundle")
        try makeFolder(bundleRoot.appendingPathComponent("Foo.app"))
        cases.append(Case(label: "missing before ..", root: bundleRoot,
                          typed: bundleRoot.path + "/missing/../Foo.app", top: bundleRoot.path,
                          rest: "missing/../Foo.app", folded: "/Foo.app", premise: ENOENT))

        for item in cases {
            XCTAssertEqual(errnoOf(item.typed), item.premise, "\(item.label): the kernel does not answer "
                           + "\(item.premise) for \(item.typed); the subject did not occur")
            XCTAssertNotNil(ownIdentity(item.root.path + item.folded), "\(item.label): the letters' fold is not there")
            let ownRoot = try XCTUnwrap(KernelsOwnName.name(of: item.root.path))
            let ownTop = try XCTUnwrap(KernelsOwnName.name(of: item.top))
            let expectedProjection = PathCanonical.withoutPrivate(ownRoot + item.folded)
            let projection = PathCanonical.resolvingAncestors(item.typed)
            print("[reading] \(item.label): \(item.typed.debugDescription) -> projection \(projection.debugDescription)")
            XCTAssertTrue(sameBytes(projection, expectedProjection),
                          "\(item.label): the projection is \(projection.debugDescription), not the rest folded under "
                          + "the kernel's folder: \(expectedProjection.debugDescription)")
            let reading = read(item.typed, .noName, "holds a `..` in the part the kernel did not answer for")
            XCTAssertTrue(sameBytes(reading.name, ownTop + "/" + item.rest),
                          "\(item.label): the reading's name is \(reading.name.debugDescription); the rest is not as typed")
            let control = asked(item.root.path + item.folded, home: home, "control: the fold, by letters")
            XCTAssertEqual(control[.user], true, "CONTROL: UserFileScope refuses the folded object")
            if item.folded.hasSuffix(".app") { XCTAssertEqual(control[.app], true, "CONTROL: RemovableScope refuses it") }
            let answers = asked(item.typed, home: home, item.label)
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(item.typed)")
            }
        }

        // The other half: a link to a folder before the `..` is answered by the
        // kernel, so the projection is where the kernel climbs.
        let elsewhere = home.appendingPathComponent("Elsewhere")
        try makeFolder(elsewhere.appendingPathComponent("Target"))
        XCTAssertEqual(symlink(elsewhere.path + "/Target", home.path + "/linkToTarget"), 0)
        let typed = home.path + "/linkToTarget/../new.txt"
        XCTAssertEqual(errnoOf(typed), ENOENT, "new.txt is there; the subject did not occur")
        XCTAssertNotNil(ownIdentity(home.path + "/linkToTarget/.."), "the kernel does not climb out of the link")
        XCTAssertEqual(ownIdentity(home.path + "/linkToTarget/.."), ownIdentity(elsewhere.path),
                       "the kernel climbs to another folder than the link's target's parent; the subject did not occur")
        let ownElsewhere = try XCTUnwrap(KernelsOwnName.name(of: elsewhere.path))
        let ownHome = try XCTUnwrap(KernelsOwnName.name(of: home.path))
        let projection = PathCanonical.resolvingAncestors(typed)
        print("[reading] link before ..: \(typed.debugDescription) -> projection \(projection.debugDescription)")
        XCTAssertTrue(sameBytes(projection, PathCanonical.withoutPrivate(ownElsewhere + "/new.txt")),
                      "the projection is \(projection.debugDescription), not where the kernel climbs")
        XCTAssertFalse(sameBytes(projection, PathCanonical.withoutPrivate(ownHome + "/new.txt")),
                       "the projection is the letters' fold")
        let climbed = read(typed, .nothingThere, "is a place below the folder the kernel climbs to")
        XCTAssertTrue(sameBytes(climbed.name, ownElsewhere + "/new.txt"), "the name is \(climbed.name.debugDescription)")

        // Printed, not pinned: a doubled separator in a rest with a dot and
        // in one without.
        for string in [home.path + "/missing//x", home.path + "/missing//../x", home.path + "/missing/x"] {
            let bare = PathCanonical.reading(of: string)
            print("[reading] doubled separator: \(string.debugDescription) -> projection "
                  + "\(PathCanonical.resolvingAncestors(string).debugDescription); the reading: \(bare.standing), "
                  + "name \(bare.name.debugDescription)")
        }
    }

    /// `Reading.asked` is the string as it came in, by bytes, trailing
    /// separators and all, whatever the standing.
    func testTheReadingKeepsTheStringItWasAskedByBytes() throws {
        let (_, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Asked")
        try makeFile(folder.appendingPathComponent("file.txt"))
        let strings: [(why: String, string: String, standing: PathCanonical.Reading.Standing)] = [
            ("an object", folder.path + "///", .object),
            ("an object, a file", folder.path + "/file.txt", .object),
            ("nothing there", folder.path + "/missing///", .nothingThere),
            ("no name, relative", "relative/path//", .noName),
            ("no name, a last dot", folder.path + "/..//", .noName),
            ("no name, below a file", folder.path + "/file.txt/x/", .noName),
        ]
        for (why, string, standing) in strings {
            let reading = read(string, standing, why)
            XCTAssertTrue(sameBytes(reading.asked, string),
                          "\(why): asked is \(reading.asked.debugDescription), not \(string.debugDescription)")
            let entry = PathCanonical.readingForRemoval(string)
            XCTAssertTrue(sameBytes(entry.asked, string),
                          "\(why): the entry's asked is \(entry.asked.debugDescription), not \(string.debugDescription)")
        }
        let prefixed = "/.nofollow" + folder.path + "//"
        XCTAssertTrue(sameBytes(PathCanonical.readingForRemoval(prefixed).asked, prefixed),
                      "a string with a kernel prefix is not handed back as asked")
    }

    /// A last component that is `.` or `..` is no name, so neither gate takes
    /// it, in a folder and in a bundle; the same folders without the dot are
    /// accepted.
    func testAStringEndingInADotIsRefusedWhereTheFolderWithoutItIsAccepted() throws {
        let (home, caches) = try scratchHomeWithCaches()
        let folder = caches.appendingPathComponent("Plain")
        let bundle = caches.appendingPathComponent("Foo.app")
        try makeFolder(folder)
        try makeFolder(bundle.appendingPathComponent("sub"))
        for control in [folder.path, bundle.path] {
            let answers = asked(control, home: home, "control: no dot")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], true, "CONTROL: \(gate.rawValue) refuses \(control)")
            }
        }
        XCTAssertEqual(asked(home.path, home: home, "control: the scratch home")[.user], true,
                       "CONTROL: UserFileScope refuses the scratch home")
        for string in [folder.path + "/.", folder.path + "/..", bundle.path + "/.", bundle.path + "/sub/..",
                       home.path + "/Library/.."] {
            XCTAssertNotNil(ownIdentity(string), "\(string) is not there; the subject did not occur")
            let answers = asked(string, home: home, "a last dot")
            for gate in Gate.allCases {
                XCTAssertEqual(answers[gate], false, "\(gate.rawValue) accepts \(string)")
            }
        }
    }

    /// `RemovableScope`'s `home:` is read through the reading, so a spelling of
    /// the home that differs in separators, dots, case, `/private` or the Data
    /// volume's firmlink is the same home. Each is printed beside the answer
    /// for the folder's own spelling. A link to the home is another name in
    /// the reading, which follows no last link; its answer is printed and not
    /// pinned.
    func testRemovableScopeReadsItsHomeThroughTheReading() throws {
        let home = scratchDirectory("home-reading")
        let path = home.path + "/Library/Caches/com.acme.cache"
        try makeFolder(URL(fileURLWithPath: path))
        try makeFolder(home.appendingPathComponent("Documents"))
        let outside = "/Users/someone-else/Library/Caches/com.acme.cache"
        let base = RemovableScope.isRemovable(path, home: home.path)
        XCTAssertTrue(base, "CONTROL: a folder in the home's Caches is refused with the home spelled as made")
        XCTAssertFalse(RemovableScope.isRemovable(outside, home: home.path), "CONTROL: another home's folder is accepted")
        let ownHome = try XCTUnwrap(KernelsOwnName.name(of: home.path))
        var spellings: [(String, String)] = [
            ("H/", home.path + "/"), ("H//", home.path + "//"), ("H/.", home.path + "/."),
            ("H/Documents/..", home.path + "/Documents/.."), ("H in upper case", home.path.uppercased()),
            ("/System/Volumes/Data + H", "/System/Volumes/Data" + ownHome),
        ]
        if !home.path.hasPrefix("/private/") { spellings.insert(("/private + H", "/private" + home.path), at: 4) }
        XCTAssertEqual(spellings.count, 7, "the seven spellings were not all built")
        for (label, spelling) in spellings {
            XCTAssertEqual(ownIdentity(spelling, followingLinks: true), ownIdentity(home.path),
                           "\(label) is not the home folder; the subject did not occur")
            let answer = RemovableScope.isRemovable(path, home: spelling)
            let other = RemovableScope.isRemovable(outside, home: spelling)
            print("[reading] home: \(label) \(spelling.debugDescription) -> \(answer); H itself \(base); "
                  + "another home's folder \(other)")
            XCTAssertEqual(answer, base, "home: \(label) is not the home it names")
            XCTAssertFalse(other, "home: \(label) accepts a folder of another home")
        }
        let linkFolder = scratchDirectory("home-link")
        XCTAssertEqual(symlink(home.path, linkFolder.path + "/toHome"), 0)
        let linkHome = linkFolder.path + "/toHome"
        print("[reading] home: a link to H \(linkHome.debugDescription) -> "
              + "\(RemovableScope.isRemovable(path, home: linkHome)); H itself \(base)")
    }
}
