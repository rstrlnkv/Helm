import XCTest
import HelmTestSupport

/// What the real `FileManager.trashItem(at:resultingItemURL:)` does with a leaf
/// that is not an ordinary file, called directly on scratch objects. It takes a
/// symbolic-link leaf itself and leaves what the link points at, whether that is
/// a file, a directory or a bundle; it takes the one name of a hard-linked inode
/// it was given and leaves the other; it takes the file a file reference names,
/// whether CoreFoundation made the reference or it was typed with Foundation's
/// own volume number; it follows a link among the ancestors; and it refuses a
/// `/dev/fd/<n>` path of an open directory with `NSCocoaErrorDomain` 512,
/// moving nothing. The `/.file/id=` spelling typed from `st_dev` resolves to no
/// path at all, and the row that holds that never calls `trashItem`.
///
/// **The rows that call it trash for real.** Each works in its own scratch
/// folder, every object it makes carries one UUID, and it removes its own Trash
/// entry by the `resultingItemURL` the call hands back — after asserting that
/// the URL lies in the user's Trash directory and that its last component
/// carries the row's UUID. A row whose URL fails either check removes nothing
/// and fails with the path it left. `reclaimFromTrash` is registered for the
/// leaf's name as the fallback. A row that calls it on a URL it did not spell
/// from a path reads where the URL leads first, and does not call it when that
/// is anywhere but the scratch object.
///
/// Every call prints one line, `[real trash] <row>: moved=… stayed=…
/// resulting=…`, so the measurement can be read off a run.
final class RealTrashLeafTests: XCTestCase {

    // MARK: - The call, and the cleanup that goes with it

    /// What `lstat` says about a name, without following it.
    private struct Seen: Equatable, CustomStringConvertible {
        enum Kind: Equatable { case absent, file, directory, symlink(to: String), other }
        let kind: Kind
        let inode: UInt64
        let links: Int

        var description: String {
            switch kind {
            case .absent: return "absent"
            case .file: return "file(ino \(inode), nlink \(links))"
            case .directory: return "directory(ino \(inode))"
            case let .symlink(to): return "symlink(ino \(inode)) -> \(to)"
            case .other: return "other(ino \(inode))"
            }
        }
    }

    private func seen(_ url: URL) -> Seen {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return Seen(kind: .absent, inode: 0, links: 0) }
        let kind: Seen.Kind
        switch st.st_mode & S_IFMT {
        case S_IFREG: kind = .file
        case S_IFDIR: kind = .directory
        case S_IFLNK:
            kind = .symlink(to: (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "?")
        default: kind = .other
        }
        return Seen(kind: kind, inode: UInt64(st.st_ino), links: Int(st.st_nlink))
    }

    private struct Outcome {
        /// The URL the call handed back, nil when it threw or handed back nothing.
        var resulting: URL?
        var error: NSError?
        /// What the row read from the Trash entry before removing it.
        var entry: Seen = Seen(kind: .absent, inode: 0, links: 0)
    }

    private func userTrash() -> URL {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return (try? fm.url(for: .trashDirectory, in: .userDomainMask,
                            appropriateFor: home, create: false))
            ?? home.appendingPathComponent(".Trash")
    }

    /// Calls the real `trashItem` and removes from the Trash the entry it hands
    /// back; `reclaimFromTrash`, registered here for the leaf's name, is the
    /// fallback when the row ends.
    ///
    /// `whileInTrash` runs after the call and before the removal, for what a row
    /// has to read while the Trash entry still exists.
    private func trashForReal(_ input: URL, uuid: String, row: String,
                              leafName: String,
                              whileInTrash: () -> Void = {}) -> Outcome {
        reclaimFromTrash(leafName)
        var outcome = Outcome()
        var handedBack: NSURL?
        do {
            try FileManager.default.trashItem(at: input, resultingItemURL: &handedBack)
        } catch {
            outcome.error = error as NSError
        }
        guard let resulting = handedBack as URL? else { return outcome }
        outcome.resulting = resulting

        let trash = userTrash().resolvingSymlinksInPath().path
        let parent = resulting.deletingLastPathComponent().resolvingSymlinksInPath().path
        let insideTrash = parent == trash || parent.hasPrefix(trash + "/")
        let carriesUUID = resulting.lastPathComponent.contains(uuid)
        guard insideTrash, carriesUUID else {
            XCTFail("\(row): the resulting URL \(resulting.path) is "
                    + (insideTrash ? "" : "not inside \(trash)") + (carriesUUID ? "" : " not named with \(uuid)")
                    + " — nothing was removed and it is left where it is")
            return outcome
        }
        outcome.entry = seen(resulting)
        whileInTrash()
        do {
            try FileManager.default.removeItem(at: resulting)
        } catch {
            XCTFail("\(row): removing \(resulting.path) threw \(error) — the entry is left in the Trash")
        }
        return outcome
    }

    private func describe(_ outcome: Outcome) -> String {
        if let resulting = outcome.resulting { return resulting.path }
        if let error = outcome.error { return "nil (threw \(error.domain) \(error.code))" }
        return "nil (no error, no URL)"
    }

    private func report(_ row: String, moved: String, stayed: String, outcome: Outcome) {
        let underlying = (outcome.error?.userInfo[NSUnderlyingErrorKey] as? NSError)
            .map { " underlying=\($0.domain) \($0.code)" } ?? ""
        print("[real trash] \(row): moved=\(moved) stayed=\(stayed) resulting=\(describe(outcome))"
              + (outcome.error.map { " error=\($0.domain) \($0.code)" } ?? "") + underlying
              + " entry=\(outcome.entry)")
    }

    private func gone(_ url: URL) -> Bool { seen(url).kind == .absent }

    // MARK: - A symbolic-link leaf

    /// The leaf is a link to a file beside it: the link moves, the target stays.
    func testALinkToAFileMovesTheLinkAndTheTargetStays() throws {
        let scratch = trashScratchDirectory("real-trash-link-file")
        let uuid = UUID().uuidString
        let target = try write("target-\(uuid).txt", in: scratch, bytes: 64)
        let link = scratch.appendingPathComponent("link-\(uuid).txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let targetBefore = seen(target)
        XCTAssertEqual(targetBefore.kind, .file)
        XCTAssertEqual(seen(link).kind, .symlink(to: target.path), "the subject did not occur")
        reclaimFromTrash(target.lastPathComponent)

        let outcome = trashForReal(link, uuid: uuid, row: "link to a file",
                                   leafName: link.lastPathComponent)

        report("link to a file", moved: "link=\(gone(link) ? "yes" : "no") target=\(gone(target) ? "yes" : "no")",
               stayed: "link=\(seen(link)) target=\(seen(target))", outcome: outcome)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.entry.kind, .symlink(to: target.path),
                       "what arrived in the Trash is the link, still pointing at the target")
        XCTAssertTrue(gone(link), "the link is still where it was")
        XCTAssertEqual(seen(target), targetBefore, "the target is another object now, or gone")
        XCTAssertEqual(try Data(contentsOf: target).count, 64)
    }

    /// The leaf is a link to a directory with a file in it.
    func testALinkToADirectoryMovesTheLinkAndTheDirectoryStays() throws {
        let scratch = trashScratchDirectory("real-trash-link-dir")
        let uuid = UUID().uuidString
        let inside = try write("dirtarget-\(uuid)/inside-\(uuid).txt", in: scratch, bytes: 64)
        let target = inside.deletingLastPathComponent()
        let link = scratch.appendingPathComponent("dirlink-\(uuid)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let targetBefore = seen(target), insideBefore = seen(inside)
        XCTAssertEqual(targetBefore.kind, .directory)
        reclaimFromTrash(target.lastPathComponent)

        let outcome = trashForReal(link, uuid: uuid, row: "link to a directory",
                                   leafName: link.lastPathComponent)

        report("link to a directory", moved: "link=\(gone(link) ? "yes" : "no") target=\(gone(target) ? "yes" : "no")",
               stayed: "link=\(seen(link)) target=\(seen(target)) inside=\(seen(inside))", outcome: outcome)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.entry.kind, .symlink(to: target.path))
        XCTAssertTrue(gone(link))
        XCTAssertEqual(seen(target), targetBefore)
        XCTAssertEqual(seen(inside), insideBefore)
    }

    /// The leaf is a link named like an application, to a directory named like
    /// one — the shape the uninstaller's list withdraws an offer for.
    func testALinkNamedLikeAnAppToABundleMovesTheLinkAndTheBundleStays() throws {
        let scratch = trashScratchDirectory("real-trash-link-app")
        let uuid = UUID().uuidString
        let inside = try write("Real-\(uuid).app/Contents/Info-\(uuid).plist", in: scratch, bytes: 64)
        let bundle = scratch.appendingPathComponent("Real-\(uuid).app")
        let link = scratch.appendingPathComponent("Linked-\(uuid).app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)
        let bundleBefore = seen(bundle), insideBefore = seen(inside)
        XCTAssertEqual(bundleBefore.kind, .directory)
        reclaimFromTrash(bundle.lastPathComponent)

        let outcome = trashForReal(link, uuid: uuid, row: "link named .app to a bundle",
                                   leafName: link.lastPathComponent)

        report("link named .app to a bundle",
               moved: "link=\(gone(link) ? "yes" : "no") bundle=\(gone(bundle) ? "yes" : "no")",
               stayed: "link=\(seen(link)) bundle=\(seen(bundle)) inside=\(seen(inside))", outcome: outcome)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.entry.kind, .symlink(to: bundle.path))
        XCTAssertTrue(gone(link))
        XCTAssertEqual(seen(bundle), bundleBefore)
        XCTAssertEqual(seen(inside), insideBefore)
    }

    // MARK: - A link among the ancestors

    /// A link in an *ancestor* of the leaf is followed: the leaf in the
    /// directory the link leads to moves, and the link and that directory stay.
    func testALinkAmongTheAncestorsIsFollowedAndTheLeafBehindItMoves() throws {
        let scratch = trashScratchDirectory("real-trash-link-ancestor")
        let uuid = UUID().uuidString
        let leaf = try write("realdir-\(uuid)/leaf-\(uuid).txt", in: scratch, bytes: 64)
        let realDirectory = leaf.deletingLastPathComponent()
        let linkDirectory = scratch.appendingPathComponent("linkdir-\(uuid)")
        try FileManager.default.createSymbolicLink(at: linkDirectory, withDestinationURL: realDirectory)
        let throughTheLink = linkDirectory.appendingPathComponent(leaf.lastPathComponent)
        let leafBefore = seen(leaf)
        XCTAssertEqual(seen(throughTheLink), leafBefore, "the subject did not occur: one object, two spellings")

        let outcome = trashForReal(throughTheLink, uuid: uuid, row: "link among the ancestors",
                                   leafName: leaf.lastPathComponent)

        report("link among the ancestors",
               moved: "leaf=\(gone(leaf) ? "yes" : "no") linkDirectory=\(gone(linkDirectory) ? "yes" : "no")",
               stayed: "leaf=\(seen(leaf)) linkDirectory=\(seen(linkDirectory)) realDirectory=\(seen(realDirectory))",
               outcome: outcome)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.entry, leafBefore)
        XCTAssertTrue(gone(leaf), "the object behind the link did not move")
        XCTAssertEqual(seen(linkDirectory).kind, .symlink(to: realDirectory.path))
        XCTAssertEqual(seen(realDirectory).kind, .directory)
    }

    // MARK: - A hard-linked leaf

    /// Two names, one inode: the name handed over moves, the other stays, and the
    /// inode's link count is read in the Trash while both still exist.
    func testAHardLinkedLeafMovesTheNameItWasGivenAndTheOtherNameStays() throws {
        let scratch = trashScratchDirectory("real-trash-hardlink")
        let uuid = UUID().uuidString
        let first = try write("first-\(uuid).bin", in: scratch, bytes: 64)
        let second = scratch.appendingPathComponent("second-\(uuid).bin")
        try FileManager.default.linkItem(at: first, to: second)
        let before = seen(first)
        XCTAssertEqual(before.links, 2, "the subject did not occur: two names for one inode")
        XCTAssertEqual(seen(second), before)

        var secondWhileInTrash = Seen(kind: .absent, inode: 0, links: 0)
        let outcome = trashForReal(first, uuid: uuid, row: "hard link",
                                   leafName: first.lastPathComponent) {
            secondWhileInTrash = self.seen(second)
        }

        report("hard link",
               moved: "first=\(gone(first) ? "yes" : "no") second=\(gone(second) ? "yes" : "no")",
               stayed: "first=\(seen(first)) secondWhileTheEntryWasInTheTrash=\(secondWhileInTrash) (before: \(before))",
               outcome: outcome)
        XCTAssertNil(outcome.error)
        XCTAssertTrue(gone(first), "the name it was given is still there")
        XCTAssertEqual(outcome.entry, before, "the Trash entry is the same inode with both names counted")
        XCTAssertEqual(secondWhileInTrash, before, "the other name stayed, on the same inode, with the count unchanged")
    }

    // MARK: - A file reference

    /// A URL made by `CFURLCreateFileReferenceURL`: the file it names moves.
    func testAFileReferenceURLOfAFileMovesTheFile() throws {
        let scratch = trashScratchDirectory("real-trash-fileref")
        let uuid = UUID().uuidString
        let file = try write("ref-\(uuid).bin", in: scratch, bytes: 64)
        let before = seen(file)
        let made = try XCTUnwrap(CFURLCreateFileReferenceURL(nil, file as CFURL, nil)?.takeRetainedValue(),
                                 "the subject did not occur: no file reference URL")
        let spelled = CFURLGetString(made) as String
        XCTAssertTrue(spelled.hasPrefix("file:///.file/id="), "the subject did not occur: \(spelled)")

        // Where the input leads, read before the call.
        let leads = (made as NSURL).filePathURL?.resolvingSymlinksInPath().path
        guard leads == file.resolvingSymlinksInPath().path else {
            XCTFail("the file reference leads to \(leads ?? "nowhere"), not to \(file.path): trashItem is not called")
            return
        }

        let outcome = trashForReal(made as URL, uuid: uuid, row: "file reference",
                                   leafName: file.lastPathComponent)

        report("file reference \(spelled)", moved: "file=\(gone(file) ? "yes" : "no")",
               stayed: "file=\(seen(file))", outcome: outcome)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.entry, before, "the object that arrived in the Trash is the file the reference names")
        XCTAssertTrue(gone(file))
        XCTAssertFalse(outcome.resulting?.path.contains(".file/id=") ?? true,
                       "the resulting URL is a path in the Trash, not a reference")
    }

    /// The spelling `/.file/id=<st_dev>.<inode>`, typed from `stat`, names
    /// nothing to Foundation. `trashItem` is not called on it: a URL that
    /// resolves to no path is not one this row can show leads nowhere else.
    func testAFileIdSpelledFromStDevLeadsNowhere() throws {
        let scratch = trashScratchDirectory("real-trash-fileid-stdev")
        let uuid = UUID().uuidString
        let file = try write("id-\(uuid).bin", in: scratch, bytes: 64)
        let before = seen(file)
        var st = stat()
        XCTAssertEqual(lstat(file.path, &st), 0)
        let typed = URL(fileURLWithPath: "/.file/id=\(st.st_dev).\(st.st_ino)")

        // Where the input leads, read before any call.
        let leads = (typed as NSURL).filePathURL?.resolvingSymlinksInPath().path
        print("[real trash] file id from st_dev: typed=/.file/id=\(st.st_dev).\(st.st_ino) "
              + "absoluteString=\(typed.absoluteString) path=[\(typed.path)] filePathURL=\(leads ?? "nil") "
              + "trashItem=not called")
        if let leads {
            XCTFail("the typed id leads to \(leads) (the file is \(file.path)): trashItem is not called")
            return
        }
        XCTAssertEqual(typed.absoluteString, "com-apple-unresolvable-file-reference-url:")
        XCTAssertEqual(typed.path, "", "the typed spelling has no path at all")
        XCTAssertEqual(seen(file), before, "nothing was called, so nothing moved")
    }

    /// The same spelling typed with the volume number Foundation itself writes
    /// into a reference: it resolves, and the file moves. The number is not
    /// `st_dev`.
    func testAFileIdTypedWithFoundationsVolumeNumberMovesTheFile() throws {
        let scratch = trashScratchDirectory("real-trash-fileid-foundation")
        let uuid = UUID().uuidString
        let file = try write("id-\(uuid).bin", in: scratch, bytes: 64)
        let before = seen(file)
        var st = stat()
        XCTAssertEqual(lstat(file.path, &st), 0)
        let made = try XCTUnwrap(CFURLCreateFileReferenceURL(nil, file as CFURL, nil)?.takeRetainedValue())
        let written = CFURLGetString(made) as String
        let range = try XCTUnwrap(written.range(of: "/.file/id="))
        let typedPath = String(written[range.lowerBound...])
        let typed = URL(fileURLWithPath: typedPath)
        let volume = typedPath.dropFirst("/.file/id=".count).split(separator: ".").first.map(String.init)
        XCTAssertNotEqual(volume, String(st.st_dev), "Foundation's volume number is st_dev after all")

        let leads = (typed as NSURL).filePathURL?.resolvingSymlinksInPath().path
        guard leads == file.resolvingSymlinksInPath().path else {
            XCTFail("the typed id leads to \(leads ?? "nowhere"), not to \(file.path): trashItem is not called")
            return
        }

        let outcome = trashForReal(typed, uuid: uuid, row: "file id (Foundation's volume number)",
                                   leafName: file.lastPathComponent)

        report("file id typed \(typedPath) (st_dev \(st.st_dev))", moved: "file=\(gone(file) ? "yes" : "no")",
               stayed: "file=\(seen(file))", outcome: outcome)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.entry, before)
        XCTAssertTrue(gone(file))
    }

    // MARK: - A descriptor path

    /// `/dev/fd/<n>` of an open descriptor of a scratch directory, spelled the
    /// way `URL(fileURLWithPath:)` writes it for a directory (with a trailing
    /// separator) and the way it is written without one.
    func testADescriptorPathOfADirectoryMovesNothing() throws {
        for (label, asDirectory) in [("with the trailing separator", true), ("without it", false)] {
            let scratch = trashScratchDirectory("real-trash-devfd")
            let uuid = UUID().uuidString
            let inside = try write("fddir-\(uuid)/inside-\(uuid).txt", in: scratch, bytes: 64)
            let directory = inside.deletingLastPathComponent()
            let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
            XCTAssertGreaterThanOrEqual(descriptor, 0, "the subject did not occur: no descriptor")
            guard descriptor >= 0 else { return }
            addTeardownBlock { close(descriptor) }

            // Where the input leads, read before the call.
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            XCTAssertEqual(fcntl(descriptor, F_GETPATH, &buffer), 0)
            let leads = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
            guard leads == directory.resolvingSymlinksInPath().path else {
                XCTFail("descriptor \(descriptor) leads to \(leads), not to \(directory.path): trashItem is not called")
                return
            }
            let input = URL(fileURLWithPath: "/dev/fd/\(descriptor)", isDirectory: asDirectory)
            let devfd = seen(input)
            let before = seen(directory), insideBefore = seen(inside)

            let outcome = trashForReal(input, uuid: uuid, row: "/dev/fd \(label)",
                                       leafName: directory.lastPathComponent)

            report("/dev/fd/<n> \(label) (input \(input.absoluteString), lstat of it \(devfd))",
                   moved: "directory=\(gone(directory) ? "yes" : "no")",
                   stayed: "directory=\(seen(directory)) inside=\(seen(inside))", outcome: outcome)
            XCTAssertNil(outcome.resulting, "\(label): a Trash entry came back")
            XCTAssertEqual(outcome.error?.domain, NSCocoaErrorDomain, label)
            XCTAssertEqual(outcome.error?.code, 512, label)
            XCTAssertEqual(seen(directory), before, "\(label): the directory is another object now, or gone")
            XCTAssertEqual(seen(inside), insideBefore, label)
        }
    }
}

