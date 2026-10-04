import CoreGraphics
import Darwin
import Foundation
import HelmRuntime
import HelmTestSupport
import ImageIO
import XCTest
@testable import Module_Screenshots_Engine

/// **«Done» on an edit replaces one file, the one the shot wrote, and no other: the test that names the path.**
/// On REAL files in a scratch folder, `<scratch>/Screenshot 2026-10-02 at 18.00.00.png` is written by the module's own
/// writer and then edited through `CaptureSession.deliver(…replacing:)`; the Trash is a folder of the test's own that
/// the file is really moved into, so that what is on the disk afterwards is read, byte for byte, and not reported.
///
/// What each case asserts: the whole folder (every name and its bytes, a link by its target), the Trash's own
/// folder, the order of what moved (`ShotMoves`: written, written, trashed, claimed), and what the person is told
/// (`Delivery.refusals` / `replaced`). Two properties are asserted after every case: **an edit is never lost** (some
/// file in the folder holds exactly its bytes), and **every refused path is either replaced or reported, never
/// neither**.
///
/// The two re-asks are separate cases on purpose. The file is asked about at opening («Edit»: `openEdit`) before a
/// pixel of it is read, and again inside the move to the Trash. Each is the only thing that stops one case below,
/// and a mutation removing either goes red there.
///
/// Total failure of the subject prints: the changed file in the Trash, a stranger's file overwritten, an edit that is
/// nowhere, or a replacement reported over a file that was never moved.
final class TheEditReplacesOnlyTheFileItWroteTests: XCTestCase {

    // MARK: The ports of the test: a real folder that keeps a journal, and a Trash that is a folder

    /// The real writer, with every move journalled and a moment after each write for a test to change the disk in.
    final class JournalledFolder: ShotWriting, @unchecked Sendable {
        let moves: ShotMoves
        private let lock = NSLock()
        private var _afterWrite: ((URL) -> Void)?
        private var _written: [WrittenShot] = []
        init(moves: ShotMoves) { self.moves = moves }

        var afterWrite: ((URL) -> Void)? {
            get { lock.withLock { _afterWrite } }
            set { lock.withLock { _afterWrite = newValue } }
        }
        var written: [WrittenShot] { lock.withLock { _written } }

        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            let outcome = FileShotWriter().write(data, into: folder, base: base, pathExtension: pathExtension)
            if case .written(let shot) = outcome {
                lock.withLock { _written.append(shot) }
                moves.note(.wrote(shot.url))
                afterWrite?(shot.url)
            }
            return outcome
        }
        func reading(of url: URL) -> ShotReading? { FileShotWriter().reading(of: url) }
        func claim(_ written: URL, as name: URL) -> Bool {
            let claimed = FileShotWriter().claim(written, as: name)
            if claimed { moves.note(.claimed(written, as: name)); afterClaim?(name) }
            return claimed
        }
        /// Run with the name right after a successful claim, before the session goes on.
        var afterClaim: ((URL) -> Void)? {
            get { lock.withLock { _afterClaim } }
            set { lock.withLock { _afterClaim = newValue } }
        }
        private var _afterClaim: ((URL) -> Void)?
    }

    /// The Trash as a folder: the file is really moved into it under a name of its own, or the move throws.
    final class AsideTrash: ShotTrashing, @unchecked Sendable {
        let folder: URL
        let moves: ShotMoves
        private let lock = NSLock()
        private var _failure: NSError?
        private var _asked: [URL] = []
        private var _before: ((URL) -> Void)?
        private var _after: ((URL) -> Void)?
        init(folder: URL, moves: ShotMoves) { self.folder = folder; self.moves = moves }

        var failure: NSError? {
            get { lock.withLock { _failure } }
            set { lock.withLock { _failure = newValue } }
        }
        var before: ((URL) -> Void)? {
            get { lock.withLock { _before } }
            set { lock.withLock { _before = newValue } }
        }
        var after: ((URL) -> Void)? {
            get { lock.withLock { _after } }
            set { lock.withLock { _after = newValue } }
        }
        var asked: [URL] { lock.withLock { _asked } }

        func trash(_ url: URL) throws {
            lock.withLock { _asked.append(url) }
            before?(url)
            if let failure { throw failure }
            try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(UUID().uuidString))
            moves.note(.trashed(url))
            after?(url)
        }
    }

    // MARK: The scene

    static let name = "Screenshot 2026-10-02 at 18.00.00"
    let red = makeImage(width: 40, height: 30, red: 255)
    let blue = makeImage(width: 40, height: 30, blue: 255)
    var redBytes: Data { CaptureSession.encode(red, as: .png)! }
    var blueBytes: Data { CaptureSession.encode(blue, as: .png)! }

    struct Scene {
        let session: CaptureSession
        let disk: JournalledFolder
        let trash: AsideTrash
        let capture: FakeCapture
        let pasteboard: FakePasteboard
        let folder: URL
        let aside: URL
        let original: WrittenShot
        let originalBytes: Data
        var path: URL { original.url }
        func sibling(_ name: String) -> URL { folder.appendingPathComponent(name) }
    }

    /// A session over the real folder, and the original already written into it by the module's own writer.
    func scene(_ label: String, base: String = TheEditReplacesOnlyTheFileItWroteTests.name, pathExtension: String = "png",
               originalBytes: Data? = nil, settings: ScreenshotsSettings = ScreenshotsSettings(saveTarget: .desktop),
               desktop: URL? = nil, trashItems: ShotTrashing? = nil, file: StaticString = #filePath, line: UInt = #line) throws -> Scene {
        let folder = scratchDirectory(label)
        let aside = scratchDirectory(label + "-trash")
        let moves = ShotMoves()
        let disk = JournalledFolder(moves: moves)
        let trash = AsideTrash(folder: aside, moves: moves)
        let capture = FakeCapture()
        capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))
        let pasteboard = FakePasteboard()
        let fixed = Date(timeIntervalSince1970: 1_790_000_000)
        let session = CaptureSession(capture: capture, writer: disk, trash: trashItems ?? trash, pasteboard: pasteboard,
                                     preferences: FakePreferences(), shutter: FakeShutter(), textReader: FakeTextReader(),
                                     settings: { settings }, naming: { .english }, now: { fixed },
                                     locations: ScreenshotsLocations(home: folder, desktop: desktop ?? folder))
        let bytes = originalBytes ?? redBytes
        guard case .written(let shot) = disk.write(bytes, into: folder, base: base, pathExtension: pathExtension) else {
            throw XCTSkip("the original could not be written", file: file, line: line)
        }
        return Scene(session: session, disk: disk, trash: trash, capture: capture, pasteboard: pasteboard, folder: folder,
                     aside: aside, original: shot, originalBytes: bytes)
    }

    /// What is in a folder: every name with its bytes, a link by the path it holds, a folder by a mark.
    func contents(_ folder: URL) -> [String: Data] {
        var found: [String: Data] = [:]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { continue }
            switch info.st_mode & S_IFMT {
            case S_IFLNK: found[name] = Data("link -> \((try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "?")".utf8)
            case S_IFDIR: found[name] = Data("<folder>".utf8)
            default: found[name] = (try? Data(contentsOf: url)) ?? Data("<unreadable>".utf8)
            }
        }
        return found
    }

    func edit(_ s: Scene, replacing shot: WrittenShot? = nil, image: CGImage? = nil, copies: Bool = false) async -> Delivery {
        await s.session.deliver(image ?? blue, saves: true, copies: copies, replacing: shot ?? s.original)
    }

    private var beside: String { Self.name + " (1).png" }
    private var original: String { Self.name + ".png" }

    /// The two things that hold after every case. «Neither replaced nor refused» is accepted for ONE branch only, and
    /// only when the case says so with `nameTaken: true`: the name was taken by a stranger between the Trash and the
    /// claim, the original is in the Trash and the edit keeps its own "(1)" name. That is not a refusal (nothing was
    /// refused, the person's file is where the person can find it) and not a replacement (the name was not claimed):
    /// the delivery is told as a plain save, and the UI says «Saved». Any other branch still has to be one or the other.
    func assertTold(_ delivery: Delivery, _ refusals: [CaptureRefusal], replaced: Bool, nameTaken: Bool = false,
                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(delivery.refusals, refusals, "what the person is told", file: file, line: line)
        XCTAssertEqual(delivery.replaced, replaced, file: file, line: line)
        if nameTaken {
            XCTAssertFalse(replaced, "a taken name is not a replacement", file: file, line: line)
            XCTAssertTrue(refusals.isEmpty, "a taken name is not a refusal", file: file, line: line)
        } else {
            XCTAssertTrue(delivery.replaced || !delivery.refusals.isEmpty,
                          "a path that was not replaced was not reported either", file: file, line: line)
        }
    }

    func assertTheEditSurvives(in folders: [URL], file: StaticString = #filePath, line: UInt = #line) {
        let found = folders.flatMap { contents($0).values }
        XCTAssertTrue(found.contains(blueBytes), "the edit is in no file of the folder", file: file, line: line)
    }

    /// Appends one byte to the file, in place: the same inode.
    func appendInPlace(_ url: URL, restoringTime reading: ShotReading? = nil) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([1]))
        try handle.close()
        if let reading { try setTime(url, seconds: reading.modifiedSeconds, nanoseconds: reading.modifiedNanoseconds) }
    }

    func setTime(_ url: URL, seconds: Int64, nanoseconds: Int64) throws {
        var times = [timespec(tv_sec: Int(seconds), tv_nsec: Int(nanoseconds)), timespec(tv_sec: Int(seconds), tv_nsec: Int(nanoseconds))]
        XCTAssertEqual(utimensat(AT_FDCWD, url.path, &times, 0), 0, "the time could not be set: \(errno)")
    }

    // MARK: 1. The file is untouched: the original goes to the Trash, the edit takes its name

    func testAnUntouchedFileIsReplacedInTheThreeStepsAndNothingElseMoves() async throws {
        let s = try scene("edit-untouched")
        XCTAssertEqual(s.path.path, s.folder.path + "/" + original, "the path this test names")
        let delivery = await edit(s)
        assertTold(delivery, [], replaced: true)
        XCTAssertEqual(contents(s.folder), [original: blueBytes], "one file, the edited one, under the original's name")
        XCTAssertEqual(Array(contents(s.aside).values), [redBytes], "the original, byte for byte, in the Trash")
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path), .wrote(s.sibling(beside)), .trashed(s.path),
                                         .claimed(s.sibling(beside), as: s.path)], "the three steps, in this order")
        XCTAssertEqual(delivery.files, [s.path])
        // The file under the name is the one that was written beside, moved and not copied.
        let edit = try XCTUnwrap(s.disk.written.last)
        XCTAssertEqual(delivery.written.first?.reading.identity, edit.reading.identity)
        XCTAssertNotEqual(delivery.written.first?.reading.identity, s.original.reading.identity)
        XCTAssertEqual(delivery.written.first?.reading, FileShotWriter().reading(of: s.path), "the reading is of the file as it is now")
        assertTheEditSurvives(in: [s.folder])
    }

    // MARK: 2. The file was renamed

    func testARenamedOriginalIsLeftAloneAndTheEditTakesTheFreeName() async throws {
        let s = try scene("edit-renamed")
        try FileManager.default.moveItem(at: s.path, to: s.sibling("mine.png"))
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), ["mine.png": redBytes, original: blueBytes],
                       "the renamed original is intact and the edit is under the free name")
        XCTAssertEqual(contents(s.aside), [:], "nothing went to the Trash")
        XCTAssertEqual(s.trash.asked, [])
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path), .wrote(s.path)])
        assertTheEditSurvives(in: [s.folder])
    }

    func testAnOriginalMovedAwayAndNothingInItsPlaceIsTheSame() async throws {
        let s = try scene("edit-gone")
        try FileManager.default.removeItem(at: s.path)
        let delivery = await edit(s)
        // The edit takes the free name, which is what is at the path now: not the shot that was written.
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: blueBytes])
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: 3. Written into in place, field by field

    func testAFileWrittenIntoInPlaceIsRefused() async throws {
        let s = try scene("edit-appended")
        try appendInPlace(s.path)
        XCTAssertEqual(FileShotWriter().reading(of: s.path)?.identity, s.original.reading.identity, "the control: the same inode")
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: redBytes + Data([1]), beside: blueBytes])
        XCTAssertEqual(contents(s.aside), [:])
        XCTAssertEqual(s.trash.asked, [])
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path), .wrote(s.sibling(beside))])
        assertTheEditSurvives(in: [s.folder])
    }

    /// Only the modification time moves, by one nanosecond: the inode and the size are the same. The test that goes
    /// red when the time is not compared.
    func testOnlyTheTimeMovedByOneNanosecondIsRefused() async throws {
        let s = try scene("edit-nanosecond")
        let stored = s.original.reading
        let nanoseconds = stored.modifiedNanoseconds == 999_999_999 ? stored.modifiedNanoseconds - 1 : stored.modifiedNanoseconds + 1
        try setTime(s.path, seconds: stored.modifiedSeconds, nanoseconds: nanoseconds)
        let now = try XCTUnwrap(FileShotWriter().reading(of: s.path))
        XCTAssertEqual(now.identity, stored.identity)
        XCTAssertEqual(now.size, stored.size)
        XCTAssertEqual(now.modifiedSeconds, stored.modifiedSeconds, "the control: only the nanoseconds differ")
        XCTAssertNotEqual(now.modifiedNanoseconds, stored.modifiedNanoseconds)
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: redBytes, beside: blueBytes])
        XCTAssertEqual(s.trash.asked, [])
    }

    /// Only the size moves: a byte was appended and the time put back where it was. The test that goes red when the
    /// size is not compared: a comparison of the identity and the time alone passes this file, so only the size sees it.
    func testOnlyTheSizeMovedIsRefused() async throws {
        let s = try scene("edit-size-only")
        try appendInPlace(s.path, restoringTime: s.original.reading)
        let now = try XCTUnwrap(FileShotWriter().reading(of: s.path))
        XCTAssertEqual(now.identity, s.original.reading.identity)
        XCTAssertEqual(now.modifiedSeconds, s.original.reading.modifiedSeconds)
        XCTAssertEqual(now.modifiedNanoseconds, s.original.reading.modifiedNanoseconds, "the control: the time is where it was")
        XCTAssertNotEqual(now.size, s.original.reading.size)
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: redBytes + Data([1]), beside: blueBytes])
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: 4. Another file under the same name

    /// The same bytes, the same size and the time put back: only the inode tells it from the original.
    func testACopyOfTheSameBytesAndTimeUnderTheNameIsAnotherFile() async throws {
        let s = try scene("edit-copy")
        let other = s.sibling("other.tmp")
        try s.originalBytes.write(to: other)
        let stored = s.original.reading
        try setTime(other, seconds: stored.modifiedSeconds, nanoseconds: stored.modifiedNanoseconds)
        XCTAssertEqual(rename(other.path, s.path.path), 0)
        let now = try XCTUnwrap(FileShotWriter().reading(of: s.path))
        XCTAssertEqual(now.size, stored.size)
        XCTAssertEqual(now.modifiedNanoseconds, stored.modifiedNanoseconds, "the control: size and time are the original's")
        XCTAssertNotEqual(now.identity, stored.identity)
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: redBytes, beside: blueBytes])
        XCTAssertEqual(contents(s.aside), [:])
        XCTAssertEqual(s.trash.asked, [])
    }

    func testAnotherPictureUnderTheNameIsLeftAlone() async throws {
        let s = try scene("edit-other-picture")
        let stranger = Data("somebody else's work".utf8)
        let other = s.sibling("other.tmp")
        try stranger.write(to: other)
        XCTAssertEqual(rename(other.path, s.path.path), 0)
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: stranger, beside: blueBytes])
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: 5. A link or a folder in its place

    func testALinkInItsPlaceIsLeftAloneAndItsTargetToo() async throws {
        let s = try scene("edit-link")
        try FileManager.default.moveItem(at: s.path, to: s.sibling("elsewhere.png"))
        try FileManager.default.createSymbolicLink(at: s.path, withDestinationURL: s.sibling("elsewhere.png"))
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: Data("link -> \(s.sibling("elsewhere.png").path)".utf8),
                                            "elsewhere.png": redBytes, beside: blueBytes])
        XCTAssertEqual(s.trash.asked, [])
    }

    func testALinkToSomewhereOutsideTheFolderIsLeftAlone() async throws {
        let s = try scene("edit-link-out")
        let elsewhere = scratchDirectory("edit-link-out-target").appendingPathComponent("theirs.png")
        try Data("not a screenshot".utf8).write(to: elsewhere)
        try FileManager.default.removeItem(at: s.path)
        try FileManager.default.createSymbolicLink(at: s.path, withDestinationURL: elsewhere)
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(try Data(contentsOf: elsewhere), Data("not a screenshot".utf8))
        XCTAssertEqual(contents(s.folder)[beside], blueBytes)
        XCTAssertEqual(s.trash.asked, [])
    }

    func testAFolderInItsPlaceIsLeftAlone() async throws {
        let s = try scene("edit-folder")
        try FileManager.default.removeItem(at: s.path)
        try FileManager.default.createDirectory(at: s.path, withIntermediateDirectories: false)
        try Data("inside".utf8).write(to: s.path.appendingPathComponent("a.txt"))
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: Data("<folder>".utf8), beside: blueBytes])
        XCTAssertEqual(try Data(contentsOf: s.path.appendingPathComponent("a.txt")), Data("inside".utf8))
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: 6. Changed after the edit was written, before the move: the second re-ask, alone

    /// Everything is as stored when the edit is written; the original is written into while the edit is being named.
    /// Nothing in `deliver` asks the file but the second re-ask, so this is the case it alone stops.
    func testAFileChangedAfterTheEditWasWrittenIsRefusedAtTheMove() async throws {
        let s = try scene("edit-at-the-move")
        let url = s.path
        s.disk.afterWrite = { written in
            guard written != url else { return }
            try? self.appendInPlace(url)
        }
        s.trash.before = { _ in XCTFail("the original was moved after it had changed") }
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: redBytes + Data([1]), beside: blueBytes])
        XCTAssertEqual(contents(s.aside), [:])
        XCTAssertEqual(s.trash.asked, [])
    }

    func testAFileRenamedAfterTheEditWasWrittenIsRefusedAtTheMove() async throws {
        let s = try scene("edit-renamed-at-the-move")
        let url = s.path, moved = s.sibling("mine.png")
        s.disk.afterWrite = { written in
            guard written != url else { return }
            try? FileManager.default.moveItem(at: url, to: moved)
        }
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.missing)], replaced: false)
        XCTAssertEqual(contents(s.folder), ["mine.png": redBytes, beside: blueBytes])
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: 7. Out of the gate's scope

    /// A writer that will write where the module's own never would (`/usr/bin` is no folder of the person's), so that
    /// the gate, and nothing else, is what refuses. The Trash is asked nothing.
    func testAShotOutsideTheUsersFilesIsNotMovedAndTheTrashIsNeverAsked() async throws {
        let rig = Rig(home: scratchDirectory("edit-scope"))
        let first = rig.writer.write(Data([1]), into: URL(fileURLWithPath: "/usr/bin"), base: "Screenshot", pathExtension: "png")
        guard case .written(let stranger) = first else { return XCTFail("the fake would not write") }
        let delivery = await rig.session.deliver(blue, saves: true, copies: false, replacing: stranger)
        assertTold(delivery, [.notReplaced(.trash(.outOfScope))], replaced: false)
        XCTAssertEqual(rig.trash.asked, [], "the Trash was asked for a file the gate refused")
        XCTAssertEqual(rig.writer.moves.all, [.wrote(stranger.url), .wrote(URL(fileURLWithPath: "/usr/bin/Screenshot (1).png"))])
        XCTAssertEqual(delivery.files.map(\.path), ["/usr/bin/Screenshot (1).png"], "the edit is where it was written")
    }

    // MARK: 8. The Trash refuses

    func testTheTrashRefusingLeavesBothFilesAndTellsWhyForEveryReasonItHas() async throws {
        let cases: [(code: Int, reason: TrashFailure.Reason)] = [
            (513, .noPermission), (4, .missing), (642, .readOnlyVolume), (640, .diskFull), (256, .systemRefused),
        ]
        for (code, reason) in cases {
            let s = try scene("edit-trash-\(code)")
            s.trash.failure = NSError(domain: NSCocoaErrorDomain, code: code)
            let delivery = await edit(s)
            assertTold(delivery, [.notReplaced(.trash(reason))], replaced: false)
            XCTAssertEqual(contents(s.folder), [original: redBytes, beside: blueBytes], "code \(code)")
            XCTAssertEqual(contents(s.aside), [:], "code \(code)")
            XCTAssertEqual(s.trash.asked, [s.path], "code \(code): the Trash was asked once, about the original")
            XCTAssertEqual(s.disk.moves.all, [.wrote(s.path), .wrote(s.sibling(beside))], "code \(code): nothing was claimed")
            assertTheEditSurvives(in: [s.folder])
        }
    }

    // MARK: 9. The name is taken between the move to the Trash and the claim

    func testANameTakenBetweenTheTwoStepsIsNeverOverwrittenAndTheEditKeepsItsOwn() async throws {
        let s = try scene("edit-taken")
        let stranger = Data("squatter".utf8)
        let url = s.path
        s.trash.after = { _ in try? stranger.write(to: url) }
        let delivery = await edit(s)
        assertTold(delivery, [], replaced: false, nameTaken: true)
        XCTAssertEqual(contents(s.folder), [original: stranger, beside: blueBytes], "the squatter was written over")
        XCTAssertEqual(Array(contents(s.aside).values), [redBytes], "the original is in the Trash")
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path), .wrote(s.sibling(beside)), .trashed(s.path)], "no claim was made")
        XCTAssertEqual(delivery.files, [s.sibling(beside)], "the thumbnail's file is the edit, where it is")
        XCTAssertEqual(delivery.written.last?.reading, FileShotWriter().reading(of: s.sibling(beside)))
        assertTheEditSurvives(in: [s.folder])
    }

    func testAFolderOrALinkTakingTheNameBetweenTheStepsIsNeverReplacedEither() async throws {
        let s = try scene("edit-taken-folder")
        let url = s.path
        s.trash.after = { _ in try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        var delivery = await edit(s)
        assertTold(delivery, [], replaced: false, nameTaken: true)
        XCTAssertEqual(contents(s.folder), [original: Data("<folder>".utf8), beside: blueBytes])
        XCTAssertEqual(delivery.written.last?.url, s.sibling(beside))
        XCTAssertEqual(Array(contents(s.aside).values), [redBytes], "the original is in the Trash")

        let l = try scene("edit-taken-link")
        let target = l.sibling("target.txt")
        try Data("t".utf8).write(to: target)
        let linked = l.path
        l.trash.after = { _ in try? FileManager.default.createSymbolicLink(at: linked, withDestinationURL: target) }
        delivery = await edit(l)
        assertTold(delivery, [], replaced: false, nameTaken: true)
        XCTAssertEqual(delivery.written.last?.url, l.sibling(beside))
        XCTAssertEqual(try Data(contentsOf: target), Data("t".utf8))
        XCTAssertEqual(contents(l.folder)[original], Data("link -> \(target.path)".utf8))
        XCTAssertEqual(contents(l.folder)[beside], blueBytes)
    }

    // MARK: 10. The original's folder refuses the write

    func testAFolderThatRefusesTheWriteSavesTheEditAsANewShotAndLeavesTheOriginal() async throws {
        try XCTSkipIf(geteuid() == 0, "root may write into any folder")
        let desktop = scratchDirectory("edit-refused-desktop")
        let s = try scene("edit-refused-folder", desktop: desktop)
        chmod(s.folder.path, 0o555)
        addTeardownBlock { chmod(s.folder.path, 0o755) }
        let delivery = await edit(s)
        // The case is `.folderRefused`; the sentence a person reads is `.missing`'s, «moved or changed» (`ScStr.refusal`).
        assertTold(delivery, [.notReplaced(.folderRefused)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: redBytes], "the original is where it was")
        let saved = contents(desktop)
        XCTAssertEqual(saved.count, 1, "the edit is saved once, by the settings: \(saved.keys)")
        XCTAssertEqual(saved.values.first, blueBytes)
        XCTAssertEqual(s.trash.asked, [])
        XCTAssertEqual(delivery.files.map { $0.deletingLastPathComponent().path }, [desktop.path])
    }

    func testWhenBothFoldersRefuseNothingIsWrittenAndTheWriteIsTold() async throws {
        try XCTSkipIf(geteuid() == 0, "root may write into any folder")
        let desktop = scratchDirectory("edit-both-desktop")
        let s = try scene("edit-both-refuse", desktop: desktop)
        chmod(s.folder.path, 0o555)
        chmod(desktop.path, 0o555)
        addTeardownBlock { chmod(s.folder.path, 0o755); chmod(desktop.path, 0o755) }
        let delivery = await edit(s)
        XCTAssertFalse(delivery.refusals.isEmpty, "nothing was written and nothing was said")
        XCTAssertTrue(delivery.refusals.contains(.write(.noPermission)), "\(delivery.refusals)")
        XCTAssertFalse(delivery.replaced)
        XCTAssertEqual(contents(s.folder), [original: redBytes])
        XCTAssertEqual(contents(desktop), [:])
        XCTAssertTrue(delivery.written.isEmpty)
    }

    func testAFolderThatWasRenamedInTheFinderSavesTheEditAsANewShot() async throws {
        let desktop = scratchDirectory("edit-folder-gone-desktop")
        let s = try scene("edit-folder-gone", desktop: desktop)
        let moved = s.folder.deletingLastPathComponent().appendingPathComponent(s.folder.lastPathComponent + "-renamed")
        try FileManager.default.moveItem(at: s.folder, to: moved)
        addTeardownBlock { try? FileManager.default.removeItem(at: moved) }
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.folderRefused)], replaced: false)
        XCTAssertEqual(contents(moved), [original: redBytes])
        XCTAssertEqual(Array(contents(desktop).values), [blueBytes])
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: 11. The task is cancelled

    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _task: Task<Delivery, Never>?
        var task: Task<Delivery, Never>? {
            get { lock.withLock { _task } }
            set { lock.withLock { _task = newValue } }
        }
        func cancelWhenThere() {
            while task == nil { usleep(1000) }
            task?.cancel()
        }
    }

    /// Cancelled while the edit was being written: the edit is beside the original, the original is not moved, and
    /// the delivery says nothing, because whoever cancelled it is not there to be told (a module that was switched off).
    func testACancelAfterTheEditWasWrittenMovesNothingAndLeavesTheEditBeside() async throws {
        let s = try scene("edit-cancelled")
        let box = TaskBox()
        let url = s.path
        s.disk.afterWrite = { written in if written != url { box.cancelWhenThere() } }
        let session = s.session, shot = s.original, picture = blue
        box.task = Task { await session.deliver(picture, saves: true, copies: false, replacing: shot) }
        let running = try XCTUnwrap(box.task)
        let delivery = await running.value
        XCTAssertFalse(delivery.replaced)
        XCTAssertEqual(delivery.refusals, [], "a cancelled delivery is told to nobody")
        XCTAssertEqual(contents(s.folder), [original: redBytes, beside: blueBytes])
        XCTAssertEqual(contents(s.aside), [:])
        XCTAssertEqual(s.trash.asked, [])
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path), .wrote(s.sibling(beside))])
    }

    func testACancelBeforeAnythingIsWrittenWritesNothing() async throws {
        let s = try scene("edit-cancelled-early")
        let session = s.session, shot = s.original, picture = blue
        let task = Task { () -> Delivery in
            while !Task.isCancelled { await Task.yield() }
            return await session.deliver(picture, saves: true, copies: false, replacing: shot)
        }
        task.cancel()
        let delivery = await task.value
        XCTAssertEqual(contents(s.folder), [original: redBytes])
        XCTAssertFalse(delivery.replaced)
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path)])
    }

    // MARK: 12. A second edit, a stale reading

    func testTheEditOfAnEditReplacesAgainAndAStaleReadingDoesNot() async throws {
        let s = try scene("edit-twice")
        let green = makeImage(width: 40, height: 30, green: 255), yellow = makeImage(width: 40, height: 30, red: 255, green: 255)
        let first = await edit(s)
        assertTold(first, [], replaced: true)
        let second = await edit(s, replacing: try XCTUnwrap(first.written.first), image: green)
        assertTold(second, [], replaced: true)
        XCTAssertEqual(contents(s.folder), [original: CaptureSession.encode(green, as: .png)!])
        XCTAssertEqual(contents(s.aside).count, 2, "both earlier pictures are in the Trash")
        // The first reading is of a file that is no longer there: a thumbnail that did not take the new one is refused.
        let stale = await edit(s, replacing: s.original, image: yellow)
        assertTold(stale, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(contents(s.folder), [original: CaptureSession.encode(green, as: .png)!,
                                            beside: CaptureSession.encode(yellow, as: .png)!])
        XCTAssertEqual(contents(s.aside).count, 2)
    }

    // MARK: 13. Names: the ladder, spaces, unicode, a trailing (1)

    func testTheEditTakesTheFirstFreeNameAfterStrangersOnTheLadderAndTheStrangersAreIntact() async throws {
        let s = try scene("edit-ladder")
        var strangers: [String: Data] = [:]
        for n in 1...4 {
            let name = Self.name + " (\(n)).png"
            strangers[name] = Data("stranger \(n)".utf8)
            try strangers[name]!.write(to: s.sibling(name))
        }
        let delivery = await edit(s)
        assertTold(delivery, [], replaced: true)
        var expected = strangers
        expected[original] = blueBytes
        XCTAssertEqual(contents(s.folder), expected)
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path), .wrote(s.sibling(Self.name + " (5).png")), .trashed(s.path),
                                         .claimed(s.sibling(Self.name + " (5).png"), as: s.path)])
    }

    func testANameThatEndsInOneAlreadyAndIsTakenUpTheLadderIsReplacedLikeAnyOther() async throws {
        let base = Self.name + " (1)"
        let s = try scene("edit-trailing", base: base)
        var strangers: [String: Data] = [:]
        for n in 1...3 {
            let name = base + " (\(n)).png"
            strangers[name] = Data("stranger \(n)".utf8)
            try strangers[name]!.write(to: s.sibling(name))
        }
        let delivery = await edit(s)
        assertTold(delivery, [], replaced: true)
        var expected = strangers
        expected[base + ".png"] = blueBytes
        XCTAssertEqual(contents(s.folder), expected)
    }

    func testSpacesAndUnicodeInTheNameSurviveTheReplacement() async throws {
        let names = ["Снимок экрана 2026-10-02 в 18.00.00", "スクリーンショット 2026-10-02 18.00.00", "Cafe\u{301} ☕ 'quoted' \"double\" 2026",
                     "  leading and trailing  ", "dots...and..dots", "100% [done] {ok} #1 & more"]
        for base in names {
            let s = try scene("edit-names", base: base)
            let delivery = await edit(s)
            assertTold(delivery, [], replaced: true)
            let found = contents(s.folder)
            XCTAssertEqual(found.count, 1, "\(base): \(found.keys)")
            XCTAssertEqual(found.values.first, blueBytes, base)
            XCTAssertEqual(found.keys.first?.precomposedStringWithCanonicalMapping,
                           (base + ".png").precomposedStringWithCanonicalMapping, "the name changed")
            XCTAssertEqual(contents(s.aside).values.first, redBytes, base)
        }
    }

    /// The ladder has a ceiling: every name up to it taken, and the edit has no «beside». It is saved where the
    /// settings save, as a new shot, and the original is not touched.
    func testAFolderWithEveryNameOnTheLadderTakenSavesTheEditElsewhere() async throws {
        let desktop = scratchDirectory("edit-exhausted-desktop")
        let s = try scene("edit-exhausted", desktop: desktop)
        for n in 1..<ShotNames.limit {
            FileManager.default.createFile(atPath: s.sibling(Self.name + " (\(n)).png").path, contents: Data())
        }
        let delivery = await edit(s)
        assertTold(delivery, [.notReplaced(.folderRefused)], replaced: false)
        XCTAssertEqual(try Data(contentsOf: s.path), redBytes)
        XCTAssertEqual(Array(contents(desktop).values), [blueBytes])
        XCTAssertEqual(s.trash.asked, [])
    }

    // MARK: 14. Formats

    func testAJPEGIsReplacedByAJPEGAndNotByTheSettingsPNG() async throws {
        let jpeg = CaptureSession.encode(red, as: .jpeg)!
        let s = try scene("edit-jpeg", pathExtension: "jpg", originalBytes: jpeg)
        let delivery = await edit(s)
        assertTold(delivery, [], replaced: true)
        let found = contents(s.folder)
        XCTAssertEqual(Array(found.keys), [Self.name + ".jpg"])
        XCTAssertEqual(found.values.first?.prefix(3), Data([0xFF, 0xD8, 0xFF]), "the bytes under a .jpg are not a JPEG")
        XCTAssertEqual(Array(contents(s.aside).values), [jpeg])
    }

    /// A name in a format this module does not write is never replaced, and is told: the edit is beside it.
    func testAnExtensionTheModuleDoesNotWriteIsNeverReplaced() async throws {
        for ext in ["jpeg", "PNG", "heic", "tiff", ""] {
            let s = try scene("edit-ext", pathExtension: ext)
            let delivery = await edit(s)
            assertTold(delivery, [.notReplaced(.changed)], replaced: false)
            XCTAssertEqual(s.trash.asked, [], "'\(ext)'")
            XCTAssertEqual(contents(s.folder)[Self.name + (ext.isEmpty ? "" : "." + ext)], redBytes, "the original under '\(ext)'")
            assertTheEditSurvives(in: [s.folder])
        }
    }

    // MARK: 15. What an exit other than Done does

    func testACopyAloneReplacesNothingAndASaveReplacesButCopiesNothing() async throws {
        let s = try scene("edit-exits")
        let copied = await s.session.deliver(blue, saves: false, copies: true, replacing: s.original)
        XCTAssertFalse(copied.replaced)
        XCTAssertEqual(copied.refusals, [])
        XCTAssertTrue(copied.copied)
        XCTAssertEqual(contents(s.folder), [original: redBytes], "⌘C on an edit touched the file")
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path)])
        XCTAssertEqual(s.pasteboard.copies.count, 1)

        let saved = await s.session.deliver(blue, saves: true, copies: false, fileEvenFromClipboard: true, replacing: s.original)
        XCTAssertTrue(saved.replaced)
        XCTAssertFalse(saved.copied)
        XCTAssertEqual(s.pasteboard.copies.count, 1, "⌘S copied")
        XCTAssertEqual(contents(s.folder), [original: blueBytes])
    }

    /// An edit of a shot whose file exists replaces it whatever the setting says now: the save target is for new shots.
    func testTheClipboardTargetDoesNotStopTheReplacementOfAFileThatExists() async throws {
        let s = try scene("edit-clipboard-target", settings: ScreenshotsSettings(saveTarget: .clipboard))
        let delivery = await edit(s)
        assertTold(delivery, [], replaced: true)
        XCTAssertEqual(contents(s.folder), [original: blueBytes])
    }

    func testWithoutAnOriginalTheClipboardTargetSavesNothingAndADesktopTargetSavesANewShot() async throws {
        let s = try scene("edit-no-original-clipboard", settings: ScreenshotsSettings(saveTarget: .clipboard))
        let held = await s.session.deliver(blue, saves: true, copies: true)
        XCTAssertEqual(held.files, [])
        XCTAssertTrue(held.copied)
        XCTAssertFalse(held.replaced)
        XCTAssertEqual(contents(s.folder), [original: redBytes])
        XCTAssertEqual(s.trash.asked, [])

        let d = try scene("edit-no-original-desktop")
        let saved = await d.session.deliver(blue, saves: true, copies: true)
        XCTAssertFalse(saved.replaced)
        XCTAssertEqual(saved.files.count, 1)
        XCTAssertEqual(contents(d.folder).count, 2, "a new shot beside the old, which is not touched")
        XCTAssertEqual(contents(d.folder)[original], redBytes)
        XCTAssertEqual(d.trash.asked, [])
    }

    // MARK: 16. The file is asked about at opening, before a pixel of it is read

    private func opened(_ s: Scene, shot: WrittenShot? = nil) async -> EditOpening {
        await s.session.openEdit(of: shot ?? s.original, held: nil, on: nil)
    }

    private func assertRefusedAtOpening(_ s: Scene, _ what: String, file: StaticString = #filePath, line: UInt = #line) async {
        let calls = s.capture.freezeCalls
        let result = await opened(s)
        guard case .refused(.notEditable) = result else {
            return XCTFail("\(what): the editor was opened on a file that is not the shot's: \(result)", file: file, line: line)
        }
        XCTAssertEqual(s.capture.freezeCalls, calls, "\(what): the screen was frozen for a file that is not the shot's", file: file, line: line)
    }

    func testTheUntouchedFileOpensAndNothingIsChanged() async throws {
        let s = try scene("open-untouched")
        guard case .ready(let shown) = await opened(s) else { return XCTFail("the shot's own file did not open") }
        XCTAssertEqual(shown.picture.width, 40)
        XCTAssertEqual(shown.picture.height, 30)
        XCTAssertEqual(contents(s.folder), [original: redBytes], "opening wrote")
        XCTAssertEqual(s.disk.moves.all, [.wrote(s.path)])
    }

    func testEveryWayTheFileIsNotTheShotRefusesTheOpeningBeforeTheScreenIsFrozen() async throws {
        // Renamed.
        var s = try scene("open-renamed")
        try FileManager.default.moveItem(at: s.path, to: s.sibling("mine.png"))
        await assertRefusedAtOpening(s, "renamed")
        // Deleted.
        s = try scene("open-deleted")
        try FileManager.default.removeItem(at: s.path)
        await assertRefusedAtOpening(s, "deleted")
        // Written into: the picture still decodes, so only the reading refuses.
        s = try scene("open-appended")
        try appendInPlace(s.path)
        await assertRefusedAtOpening(s, "appended in place")
        // The time alone.
        s = try scene("open-time")
        try setTime(s.path, seconds: s.original.reading.modifiedSeconds + 1, nanoseconds: s.original.reading.modifiedNanoseconds)
        await assertRefusedAtOpening(s, "touched")
        // The size alone.
        s = try scene("open-size")
        try appendInPlace(s.path, restoringTime: s.original.reading)
        await assertRefusedAtOpening(s, "size only")
        // Another file with the same bytes and time: the identity alone.
        s = try scene("open-copy")
        let other = s.sibling("other.tmp")
        try s.originalBytes.write(to: other)
        try setTime(other, seconds: s.original.reading.modifiedSeconds, nanoseconds: s.original.reading.modifiedNanoseconds)
        XCTAssertEqual(rename(other.path, s.path.path), 0)
        await assertRefusedAtOpening(s, "another file of the same bytes")
        // A link to a real picture: it decodes through the link, and it is not the file.
        s = try scene("open-link")
        try FileManager.default.moveItem(at: s.path, to: s.sibling("elsewhere.png"))
        try FileManager.default.createSymbolicLink(at: s.path, withDestinationURL: s.sibling("elsewhere.png"))
        await assertRefusedAtOpening(s, "a link to the picture")
        // A folder.
        s = try scene("open-folder")
        try FileManager.default.removeItem(at: s.path)
        try FileManager.default.createDirectory(at: s.path, withIntermediateDirectories: false)
        await assertRefusedAtOpening(s, "a folder")
    }

    /// A folder that may not be searched answers `lstat` with nothing, which is the same refusal as a file that is gone.
    func testAFolderThatMayNotBeSearchedRefusesTheOpening() async throws {
        try XCTSkipIf(geteuid() == 0, "root searches any folder")
        let s = try scene("open-unsearchable")
        chmod(s.folder.path, 0o000)
        addTeardownBlock { chmod(s.folder.path, 0o755) }
        await assertRefusedAtOpening(s, "an unsearchable folder")
    }

    /// The reading says «the same file» and there is no picture in it: bytes the writer was handed, a zero-byte file,
    /// a half of a PNG. Nothing is opened and nothing is frozen.
    func testAFileThatIsTheShotsAndIsNoPictureRefusesTheOpening() async throws {
        let png = redBytes
        let bad: [(String, Data)] = [("zero bytes", Data()), ("text", Data("not an image at all".utf8)),
                                     ("a header only", png.prefix(8)), ("random bytes", Data((0..<512).map { UInt8(truncatingIfNeeded: $0 &* 37) }))]
        for (what, bytes) in bad {
            let s = try scene("open-bad", originalBytes: bytes)
            XCTAssertEqual(s.original.reading.size, Int64(bytes.count))
            await assertRefusedAtOpening(s, what)
        }
    }

    func testAnOpeningWithNeitherAFileNorAPictureHasNothingToOpen() async throws {
        let s = try scene("open-nothing")
        let result = await s.session.openEdit(of: nil, held: nil, on: nil)
        guard case .refused(.notEditable) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(s.capture.freezeCalls, 0)
    }

    /// The edit of a shot that has no file is asked nothing of the disk, even a disk whose folder is gone.
    func testAHeldPictureOpensWithoutAskingTheDisk() async throws {
        let s = try scene("open-held")
        try FileManager.default.removeItem(at: s.path)
        guard case .ready(let shown) = await s.session.openEdit(of: nil, held: blue, on: nil) else { return XCTFail("a held picture did not open") }
        XCTAssertEqual(shown.picture.width, 40)
    }

    // MARK: 17. The real Trash

    /// `SystemShotTrash` on a file of this test's own, whose leaf carries a UUID so that its cleanup can only remove
    /// what this test put in the Trash. The file is really moved to the owner's Trash, and is taken out again.
    func testTheRealTrashTakesTheOriginalAndTheEditTakesItsName() async throws {
        let unique = Self.name + " " + UUID().uuidString
        reclaimFromTrash(unique + ".png")
        let s = try scene("edit-real-trash", base: unique, trashItems: SystemShotTrash())
        let delivery = await s.session.deliver(blue, saves: true, copies: false, replacing: s.original)
        assertTold(delivery, [], replaced: true)
        XCTAssertEqual(contents(s.folder), [unique + ".png": blueBytes])
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/" + unique + ".png")
        XCTAssertEqual(try? Data(contentsOf: trash), redBytes, "the original is not in the Trash under its own name")
    }

    // MARK: 18. A shot in a folder that is not the person's, and someone else's encoding

    /// A file of the system's, in a folder the module cannot write to: its reading is the file's, so the editor opens;
    /// and no edit can be written beside it, so the edit goes where the settings save and nothing of the system's is moved.
    func testAShotInAFolderOfTheSystemOpensAndIsNeverMovedOrReplaced() async throws {
        let system = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Solid Colors/Teal.png")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: system.path), "this macOS has no \(system.lastPathComponent)")
        try XCTSkipIf(geteuid() == 0, "root may write into any folder")
        let desktop = scratchDirectory("edit-system-desktop")
        let s = try scene("edit-system", desktop: desktop)
        let shot = WrittenShot(url: system, reading: try XCTUnwrap(FileShotWriter().reading(of: system)))
        guard case .ready = await s.session.openEdit(of: shot, held: nil, on: nil) else { return XCTFail("the file of the shot did not open") }
        let delivery = await s.session.deliver(blue, saves: true, copies: false, replacing: shot)
        assertTold(delivery, [.notReplaced(.folderRefused)], replaced: false)
        XCTAssertEqual(s.trash.asked, [], "a file of the system was offered to the Trash")
        XCTAssertEqual(FileShotWriter().reading(of: system), shot.reading, "a file of the system was touched")
        XCTAssertEqual(Array(contents(desktop).values), [blueBytes])
    }

    /// A picture in a wide colour space is edited and saved in the space it was in, and the pixels away from the mark
    /// are the pixels it had: the replacement is made of the original's picture, not of a copy converted on the way.
    func testTheReplacementKeepsTheColourSpaceAndThePixelsOfAWideGamutOriginal() async throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: p3, components: [1, 0.2, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let wide = try XCTUnwrap(context.makeImage())
        let bytes = try XCTUnwrap(CaptureSession.encode(wide, as: .png))
        let s = try scene("edit-p3", originalBytes: bytes)
        // From the bytes, not the path: an image made from a file reads it when it is drawn, and this one is gone by then.
        func decoded(_ url: URL) throws -> CGImage {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(try Data(contentsOf: url) as CFData, nil))
            return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        let before = try decoded(s.path)
        guard case .ready(let shown) = await opened(s) else { return XCTFail("did not open") }
        let layer = Annotation(tool: .rectangle, start: CGPoint(x: shown.rect.minX + 2, y: shown.rect.minY + 2),
                               end: CGPoint(x: shown.rect.minX + 10, y: shown.rect.minY + 8), style: AnnotationStyle(thickness: .thin))
        let marked = await s.session.annotated(shown, local: shown.rect, layers: [layer])
        let out = try XCTUnwrap(marked)
        let delivery = await s.session.deliver(out, saves: true, copies: false, replacing: s.original)
        assertTold(delivery, [], replaced: true)
        let after = try decoded(s.path)
        XCTAssertEqual(after.colorSpace?.name as String?, before.colorSpace?.name as String?, "the replacement is in another colour space than the shot")
        XCTAssertEqual(after.width, before.width)
        XCTAssertEqual(after.height, before.height)
        func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
            let c = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: p3,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
            let d = c.data!.assumingMemoryBound(to: UInt8.self)
            return [d[0], d[1], d[2]]
        }
        for (x, y) in [(60, 40), (100, 70), (119, 79)] {
            let a = pixel(before, x, y), b = pixel(after, x, y)
            XCTAssertEqual(a.map(Int.init), b.map(Int.init), "pixel (\(x), \(y)) was changed away from the mark: \(a) became \(b)")
        }
    }

    // MARK: 19. The reading is of the object that was written, and not of what stands at its name a moment later

    /// A stranger replaces the file the instant its name appears, **deterministically**: `FileShotWriter.afterTheMove` runs
    /// with the new name right after the rename and before the answer is made. The reading handed back must be of the
    /// object the writer made (taken from the descriptor, before the name), so that a replacement asked later finds the
    /// stranger's file is not the shot's. A reading taken by the PATH after the rename (`lstat(destination)`) is, here,
    /// always of the stranger's file and lets it be moved to the Trash.
    func testAReadingTakenByTheDescriptorIsNotTheStrangersWhoSwapsTheNameAtOnce() throws {
        let folder = scratchDirectory("reading-swap")
        let strangerPath = folder.appendingPathComponent("stranger.tmp").path
        XCTAssertTrue(FileManager.default.createFile(atPath: strangerPath, contents: Data("somebody else's".utf8)))
        let seen = Seen()
        var writer = FileShotWriter()
        writer.afterTheMove = { destination in
            var info = stat()
            if lstat(destination.path, &info) == 0 { seen.written = ShotReading(info) }
            seen.swapped = rename(strangerPath, destination.path) == 0
        }
        guard case .written(let shot) = writer.write(redBytes, into: folder, base: "swap", pathExtension: "png") else {
            return XCTFail("not written")
        }
        XCTAssertTrue(seen.swapped, "the control: the stranger took the name")
        XCTAssertEqual(try Data(contentsOf: shot.url), Data("somebody else's".utf8), "the control: the name holds the stranger's file")
        let stranger = try XCTUnwrap(FileShotWriter().reading(of: shot.url))
        XCTAssertNotEqual(stranger.identity, seen.written?.identity, "the control: the two files are two objects")
        XCTAssertEqual(shot.reading, seen.written, "the reading is of the file the writer made, field for field")
        XCTAssertNotEqual(shot.reading.identity, stranger.identity, "the reading is of the stranger's file, which was at the name when it was taken")
        XCTAssertNotEqual(shot.reading, stranger)
    }

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var _written: ShotReading?, _swapped = false
        var written: ShotReading? { get { lock.withLock { _written } } set { lock.withLock { _written = newValue } } }
        var swapped: Bool { get { lock.withLock { _swapped } } set { lock.withLock { _swapped = newValue } } }
    }

    // MARK: 20. A stranger takes the original's name right after the claim

    /// The edit is claimed under the original's name and a stranger replaces the file under it the next instant. The
    /// shot the delivery hands on carries the EDIT's own reading (the descriptor's, through the rename), never the name's:
    /// a reading of the name would be the stranger's, and the next Edit or Done on that thumbnail would find it "the same"
    /// and move a stranger to the Trash. Asked again on the thumbnail the delivery gave, the answer is «changed», and
    /// nothing is trashed.
    func testAStrangerUnderTheOriginalsNameRightAfterTheClaimIsNeverTheNextEditsFileToTrash() async throws {
        let s = try scene("edit-stranger-after-claim")
        let url = s.path
        let strangerBytes = Data("somebody else's".utf8)
        let strangerPath = s.sibling("stranger.tmp")
        try strangerBytes.write(to: strangerPath)
        s.disk.afterClaim = { _ in rename(strangerPath.path, url.path) }
        let first = await edit(s)
        s.disk.afterClaim = nil
        assertTold(first, [], replaced: true)
        XCTAssertEqual(try Data(contentsOf: url), strangerBytes, "the control: the stranger stands under the name")
        let edited = try XCTUnwrap(first.written.first)
        XCTAssertEqual(edited.reading, try XCTUnwrap(s.disk.written.last).reading, "the reading is the edit's own")
        XCTAssertNotEqual(edited.reading.identity, FileShotWriter().reading(of: url)?.identity, "the reading is the name's")

        let trashedBefore = s.trash.asked
        let again = await edit(s, replacing: edited, image: makeImage(width: 40, height: 30, green: 255))
        assertTold(again, [.notReplaced(.changed)], replaced: false)
        XCTAssertEqual(s.trash.asked, trashedBefore, "the Trash was asked for the stranger's file")
        XCTAssertEqual(try Data(contentsOf: url), strangerBytes, "the stranger's file was moved or replaced")
        XCTAssertEqual(contents(s.aside).count, 1, "only the original is in the Trash")
    }
}
