import XCTest
@testable import HelmRuntime

/// The failure describer meets the errors nobody writes on purpose.
///
/// `HelmFailure.describe` reads an NSError the way triage reads it — domain,
/// code, message, reason, path, and then the error underneath — and every one
/// of those fields is attacker-shaped: the values come from macOS, from other
/// people's frameworks, and from filenames a user chose. The line it produces
/// is written to a file the app offers to copy into a bug report, so "what
/// cannot end up in there" is part of the contract.
final class HelmFailureAdversarialTests: XCTestCase {

    private func line(_ message: String) -> String {
        LogLine.format(date: Date(), level: .error, category: "x", message: message)
    }

    // MARK: - Size

    /// BUG (pinned): nothing bounds the described string. The message field is
    /// whatever the failing framework put there — a rejected AppleScript's
    /// reply, a captured stderr — and it goes in whole. `helm.log` rotates at
    /// 2 MB and keeps exactly one previous file, so a single failure carrying a
    /// multi-megabyte message rotates the log twice and takes the entire
    /// diagnostic history with it: the one artefact the log exists to preserve.
    func testOneFailureCannotCostTheWholeLog() {
        // Was an expected failure when written: the message went through at
        // any length, and two 4 MB lines erase the log they are written to.
        let huge = String(repeating: "x", count: 4 * 1024 * 1024)
        let error = NSError(domain: "D", code: 1, userInfo: [NSLocalizedDescriptionKey: huge])
        let written = line(HelmFailure.describe(error))
        XCTAssertLessThanOrEqual(written.utf8.count, 64 * 1024,
                                 "one line took \(written.utf8.count) bytes of a 2 MB log")
    }

    /// BUG (pinned): the same absence seen from the depth side — `describe`
    /// recurses through `NSUnderlyingErrorKey` with no cap. A 2000-deep chain
    /// produces a 129 KB single line; the recursion is unguarded, so a chain
    /// long enough (or one made cyclic by an NSError subclass that vends
    /// itself) is a stack overflow rather than a long line.
    func testADeepUnderlyingChainIsNotFollowedForever() {
        // Was an expected failure when written: `describe` followed every
        // level there was. The chain is capped now, so this is a plain
        // regression test.
        var error = NSError(domain: "Leaf", code: 0)
        for i in 1...2_000 {
            error = NSError(domain: "L\(i)", code: i,
                            userInfo: [NSUnderlyingErrorKey: error])
        }
        let described = HelmFailure.describe(error)
        XCTAssertLessThanOrEqual(described.count, 4_096,
                                 "\(described.count) characters from one error")
    }

    /// Whatever the chain does to the length, it must not lose the outermost
    /// error — that is the one the call site actually saw.
    func testADeepChainStillNamesTheErrorThatWasThrown() {
        var error = NSError(domain: "Leaf", code: 0)
        for i in 1...500 {
            error = NSError(domain: "L\(i)", code: i,
                            userInfo: [NSUnderlyingErrorKey: error])
        }
        XCTAssertTrue(HelmFailure.describe(error).hasPrefix("L500 500"),
                      String(HelmFailure.describe(error).prefix(80)))
    }

    // MARK: - One event, one line

    /// BUG (pinned): `oneLine` replaces CRLF and LF and stops there. A lone CR
    /// — which is what a captured CLI progress line is made of — survives into
    /// the log, and every editor a bug report gets pasted into treats it as a
    /// line break. So does U+2028. And U+202E reverses everything after it, so
    /// a filename can rewrite how the rest of the line reads. The invariant the
    /// method exists to hold is "one event is one line"; it holds it for one
    /// character out of four.
    func testTheControlCharactersAReaderObeysAreNeutralised() {
        // Was an expected failure when written: only \n and \r\n were
        // replaced, so a lone \r, U+2028/9 and the bidi overrides survived.
        for (name, raw) in [("CR", "\r"), ("LS", "\u{2028}"),
                            ("PS", "\u{2029}"), ("RLO", "\u{202E}")] {
            let error = NSError(domain: "D", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "before\(raw)after"])
            let written = line(HelmFailure.describe(error))
            XCTAssertFalse(written.contains(raw), "\(name) survived into the log line")
        }
    }

    /// A newline in the middle is replaced, and the text on both sides of it
    /// survives — the existing guarantee, pinned so a fix for the above cannot
    /// quietly turn into "strip the message".
    func testANewlineIsReplacedNotDropped() {
        let error = NSError(domain: "D", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "before\nafter"])
        let described = HelmFailure.describe(error)
        XCTAssertFalse(described.contains("\n"), described)
        XCTAssertTrue(described.contains("before"), described)
        XCTAssertTrue(described.contains("after"), described)
    }

    /// Cyrillic, emoji, a tab and a right-to-left script all reach the log
    /// intact: the line is UTF-8 and the message is evidence, not a token.
    func testTextThatIsNotASCIISurvivesIntact() {
        for message in ["мой файл.pdf", "🙈 не открылся", "מסמך.pdf", "a\tb", "\u{1F1F7}\u{1F1FA}"] {
            let error = NSError(domain: "D", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: message])
            let written = line(HelmFailure.describe(error))
            XCTAssertTrue(written.contains(message), written)
            XCTAssertFalse(written.contains("\n"), written)
        }
    }

    // MARK: - Redaction

    /// BUG (pinned): `Redact.path` rewrites a path only when it starts with the
    /// literal home directory. Every user file on an APFS boot volume is also
    /// reachable through the Data volume's firmlink — `/System/Volumes/Data` +
    /// the same path — and the Disk module lets a user point a scan at any
    /// folder through an open panel, including that one. A failure on a path
    /// the scan produced from there is written to the log with the account name
    /// in it, which is the one thing the redaction rule forbids.
    func testTheAccountNameCannotArriveThroughTheDataVolumeTwin() throws {
        let home = NSHomeDirectory()
        try XCTSkipIf(home.isEmpty || !home.hasPrefix("/Users/"))
        let account = (home as NSString).lastPathComponent

        // Was an expected failure when written: Redact.path matched the home
        // prefix literally, so the Data-volume twin carried the account name.
        let twin = "/System/Volumes/Data" + home + "/Documents/tax.pdf"
        let error = NSError(domain: NSCocoaErrorDomain, code: 4,
                            userInfo: [NSFilePathErrorKey: twin])
        let described = HelmFailure.describe(error)
        XCTAssertFalse(described.contains(account),
                       "the account name reached the log: \(described)")
    }

    /// The same twin, in a message rather than a `path:` key.
    ///
    /// The account name does not leak here — `oneLine` replaces the home
    /// *anywhere* in the string, not only at the front, so the twin lost it by
    /// accident. What came out was `/System/Volumes/Data~/Desktop/secret.txt`:
    /// not a path anyone can paste, and it puts the file somewhere it is not.
    /// `Redact.path` and the `path:` extraction both answer `~/…` for the twin,
    /// and free text is where paths arrive from errors Helm has not written.
    func testTheDataVolumeTwinReadsAsTheHomeInFreeTextToo() throws {
        let home = NSHomeDirectory()
        try XCTSkipIf(home.isEmpty || !home.hasPrefix("/Users/"))
        let account = (home as NSString).lastPathComponent

        let twin = "/System/Volumes/Data" + home + "/Desktop/secret.txt"
        let error = NSError(domain: "D", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "could not read \(twin)",
            NSLocalizedFailureReasonErrorKey: "while scanning \(twin)",
        ])
        let described = HelmFailure.describe(error)
        XCTAssertFalse(described.contains(account),
                       "the account name reached the log: \(described)")
        XCTAssertFalse(described.contains("/System/Volumes/Data"), described)
        XCTAssertTrue(described.contains("read ~/Desktop/secret.txt"), described)
        XCTAssertTrue(described.contains("scanning ~/Desktop/secret.txt"), described)
    }

    /// A path that is genuinely somewhere else stays whole — redaction is not
    /// allowed to turn a system path into a guess.
    func testAPathOutsideTheHomeIsKeptAsItIs() {
        let described = HelmFailure.describe(
            NSError(domain: NSCocoaErrorDomain, code: 4,
                    userInfo: [NSFilePathErrorKey: "/Library/LaunchDaemons/x.plist"]))
        XCTAssertTrue(described.contains("/Library/LaunchDaemons/x.plist"), described)
    }

    /// The home directory itself, with nothing after it.
    func testTheHomeDirectoryAloneIsATilde() {
        let home = NSHomeDirectory()
        let described = HelmFailure.describe(
            NSError(domain: "D", code: 1, userInfo: [NSFilePathErrorKey: home]))
        XCTAssertTrue(described.contains("path: ~"), described)
        XCTAssertFalse(described.contains(home), described)
    }

    /// Every level of the chain is redacted, not only the outermost one: the
    /// path that actually failed is usually the one underneath.
    func testAPathUnderneathIsRedactedToo() {
        let home = NSHomeDirectory()
        let inner = NSError(domain: NSPOSIXErrorDomain, code: 13,
                            userInfo: [NSFilePathErrorKey: "\(home)/Documents/tax.pdf"])
        let outer = NSError(domain: NSCocoaErrorDomain, code: 513,
                            userInfo: [NSUnderlyingErrorKey: inner])
        let described = HelmFailure.describe(outer)
        XCTAssertTrue(described.contains("~/Documents/tax.pdf"), described)
        XCTAssertFalse(described.contains(home), "the real home path leaked: \(described)")
    }

    /// `NSFilePathErrorKey` is documented as a string, and is not always one:
    /// URLSession and several system frameworks put a URL under it. The wrong
    /// type must neither crash the describer nor slip past redaction.
    func testAPathKeyHoldingSomethingElseIsNotTrusted() {
        let home = NSHomeDirectory()
        let values: [Any] = [
            URL(fileURLWithPath: "\(home)/Documents/tax.pdf") as NSURL,
            URL(fileURLWithPath: "\(home)/Documents/tax.pdf"),
            42,
            ["\(home)/Documents/tax.pdf"],
            Data("\(home)/x".utf8),
            NSNull(),
        ]
        for value in values {
            let described = HelmFailure.describe(
                NSError(domain: "D", code: 1, userInfo: [NSFilePathErrorKey: value]))
            XCTAssertFalse(described.contains(home),
                           "a \(type(of: value)) under NSFilePathErrorKey leaked the home: "
                           + described)
            XCTAssertTrue(described.hasPrefix("D 1"), described)
        }
    }

    /// The URL fallback exists for exactly the errors that carry `NSURL` and no
    /// path, and it redacts the same way.
    func testTheURLFallbackIsRedactedAsWell() {
        let home = NSHomeDirectory()
        let described = HelmFailure.describe(
            NSError(domain: "D", code: 1,
                    userInfo: [NSURLErrorKey: URL(fileURLWithPath: "\(home)/Documents/a.pdf")]))
        XCTAssertTrue(described.contains("~/Documents/a.pdf"), described)
        XCTAssertFalse(described.contains(home), described)
    }

    // MARK: - OSStatus

    /// The extremes of the type. macOS knows no message for either, and the
    /// number is the whole of the answer — it must still be there, and it must
    /// not have been mangled by the unknown-code heuristic.
    func testOSStatusAtTheEndsOfItsRange() {
        XCTAssertEqual(HelmFailure.osStatus(Int32.min), "OSStatus -2147483648")
        XCTAssertEqual(HelmFailure.osStatus(Int32.max), "OSStatus 2147483647")
        XCTAssertNotNil(HelmFailure.osStatusIfFailed(Int32.min))
        XCTAssertNotNil(HelmFailure.osStatusIfFailed(Int32.max))
    }

    /// Whatever macOS answers, the line stays one line and keeps the number:
    /// the number is what a search engine and a header file are indexed by.
    func testEveryOSStatusKeepsItsNumberOnOneLine() {
        for status in [Int32.min, -50, -25_300, -25_291, -128, -1, 1, 999_999, Int32.max] {
            let described = HelmFailure.osStatus(status)
            XCTAssertTrue(described.contains("\(status)"), described)
            XCTAssertFalse(described.contains("\n"), described)
            XCTAssertTrue(described.hasPrefix("OSStatus "), described)
        }
    }

    // MARK: - errno

    /// Codes that are not errnos at all, including the ends of the type. The
    /// answer is allowed to be "unknown"; losing the number is not.
    func testEveryErrnoKeepsItsNumberOnOneLine() {
        for code in [Int32.min, -1, 0, 1, 34, 106, 107, 999_999, Int32.max] {
            let described = HelmFailure.posix(code)
            XCTAssertTrue(described.contains("\(code)"), described)
            XCTAssertFalse(described.contains("\n"), described)
            XCTAssertTrue(described.hasPrefix("errno "), described)
        }
    }

    /// `posix(0)` reads as a failure — "errno 0 “Undefined error: 0”" — and
    /// there is no `posixIfFailed` to stop a call site from logging it after a
    /// call that succeeded, the way `osStatusIfFailed` does for OSStatus.
    /// Pinned as a shape, not a bug: the asymmetry is the trap.
    func testSuccessHasNoPosixEquivalentOfOSStatusIfFailed() {
        XCTAssertNil(HelmFailure.osStatusIfFailed(0))
        XCTAssertTrue(HelmFailure.posix(0).hasPrefix("errno 0"),
                      "a successful call still describes as a failure")
    }

    // MARK: - The site

    /// `#fileID` is "Module/File.swift". The shapes it is not: no slash, more
    /// than one, empty. None of them may crash or produce a site that reads as
    /// a different file.
    func testTheFileIDIsReducedWhateverShapeItArrivesIn() {
        XCTAssertEqual(LogSite(fileID: "File.swift", line: 1, function: "f()").file,
                       "File.swift")
        XCTAssertEqual(LogSite(fileID: "A/B/C/File.swift", line: 1, function: "f()").file,
                       "File.swift")
        XCTAssertEqual(LogSite(fileID: "A//File.swift", line: 1, function: "f()").file,
                       "File.swift")
        XCTAssertEqual(LogSite(fileID: "", line: 1, function: "f()").file, "")
        XCTAssertEqual(LogSite(fileID: "/", line: 1, function: "f()").file, "/")
    }

    /// A site with no line number and no name still produces a parseable line
    /// rather than a dangling parenthesis.
    func testASiteAlwaysClosesItsParenthesis() {
        let written = LogLine.format(date: Date(), level: .warn, category: "x",
                                     message: "m",
                                     site: LogSite(fileID: "", line: 0, function: ""))
        XCTAssertTrue(written.hasSuffix(")"), written)
        XCTAssertTrue(written.contains("m  ("), written)
    }

    /// The site is appended after the message, so a message that ends in what
    /// looks like a site cannot be mistaken for one — the last parenthesis on
    /// the line is the real one.
    func testTheSiteIsTheLastThingOnTheLine() {
        let written = LogLine.format(date: Date(), level: .error, category: "x",
                                     message: "failed (Other.swift:1 g())",
                                     site: LogSite(file: "Real.swift", line: 42,
                                                   function: "f()"))
        XCTAssertTrue(written.hasSuffix("(Real.swift:42 f())"), written)
    }

    // MARK: - Threads

    /// `LogLine.format` builds its own DateFormatter per call, so many threads
    /// formatting at once cannot corrupt each other's output. Every line must
    /// come back complete and correctly attributed.
    func testFormattingFromManyThreadsKeepsEveryLineWhole() {
        let count = 500
        let lines = UnsafeMutablePointer<String>.allocate(capacity: count)
        lines.initialize(repeating: "", count: count)
        defer { lines.deinitialize(count: count); lines.deallocate() }

        DispatchQueue.concurrentPerform(iterations: count) { i in
            lines[i] = LogLine.format(
                date: Date(timeIntervalSince1970: 0), level: .error, category: "c\(i)",
                message: "message \(i)",
                site: LogSite(file: "F\(i).swift", line: i, function: "f\(i)()"),
                timeZone: TimeZone(identifier: "UTC")!)
        }
        for i in 0..<count {
            XCTAssertEqual(lines[i],
                           "1970-01-01 00:00:00.000 [error] [c\(i)] message \(i)"
                           + "  (F\(i).swift:\(i) f\(i)())")
        }
    }

    /// `HelmFailure.posix` reads a buffer libc shares between threads.
    ///
    /// Darwin's `strerror` returns a pointer to a constant string for a known
    /// errno, but for an unknown code it formats "Unknown error: N" into one
    /// static buffer for the whole process. A tight C loop over that — 8
    /// threads, 1.6M calls — had 1750 of them come back naming another
    /// thread's code, some torn mid-number ("Unknown error" with no number at
    /// all). The hazard is libc's and it is real.
    ///
    /// Through `posix` it is much narrower: the returned pointer is copied
    /// into a Swift String immediately and the rest of the call dwarfs the
    /// window, and the same 1.6M calls came back clean. So this is a watch,
    /// not a proof — it will catch the day a caller holds that pointer longer.
    /// `strerror_r` is the call with no window at all. Nothing calls `posix`
    /// yet, which is the only reason none of this is in the log already.
    ///
    /// Timing-dependent, so it reports rather than gates — HELM_BENCH=1.
    func testPosixUnderContentionNamesTheCodeItWasAsked() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let threads = 8, each = 200_000
        let wrong = UnsafeMutablePointer<Int>.allocate(capacity: threads)
        wrong.initialize(repeating: 0, count: threads)
        defer { wrong.deinitialize(count: threads); wrong.deallocate() }

        DispatchQueue.concurrentPerform(iterations: threads) { t in
            let code = Int32(900_000 + t)
            for _ in 0..<each where !HelmFailure.posix(code).contains("\(code)") {
                wrong[t] += 1
            }
        }
        let total = (0..<threads).reduce(0) { $0 + wrong[$1] }
        XCTAssertEqual(total, 0, "\(total) of \(threads * each) descriptions named "
                       + "another thread's errno")
    }
}
