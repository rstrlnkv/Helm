import XCTest

/// An event name is a declaration both sides read, never a string typed twice.
///
/// `CommandNamesAreAnsweredTests` pins this for commands — a module sending a
/// name its own engine has no `case` for. Events are the same contract in the
/// other direction and had no check at all, which is how the host came to write
///
///     for await event in events where event.name == "trashChanged"
///
/// under a comment explaining that the transport boundary left it no choice. It
/// did not: a descriptor re-exports its engine's enum the way `KeepAwakeCommand`
/// and `LayoutCommand` are already re-exported for the hotkeys, so the host can
/// say the name instead of spelling it.
///
/// **The failure has no symptom at the seam.** Rename the case in the engine and
/// nothing is an error anywhere; the emitter emits a name nobody listens for and
/// the listener waits for a name nobody emits. What the person sees is a feature
/// going quiet — drag an app to the Trash and Helm never offers to clear up
/// after it — which is indistinguishable from the feature being switched off.
///
/// Both directions are checked, because either one alone can drift: a literal
/// handed to `EngineEvent(name:)` and a literal compared against an event's
/// `name`. The scan reads one line at a time, as text, and reads two spellings
/// only: `EngineEvent(name: "` and `.name == "`. A comparison written with
/// `!=`, with the literal on the left, without those spaces, or as a `case` of
/// a `switch` is not read. The scan cannot see a type, so `offences(in:)`
/// decides from what the line spells, and a comparison passes only when the
/// line shows that neither its receiver nor its literal is an event's.
final class EventNamesAreNotLiteralsTests: XCTestCase {

    /// The line with its comment tail removed: a comment that explains the rule
    /// by quoting the spelling it forbids would otherwise be reported as the
    /// offence. A `//` inside a string literal cuts the line here too.
    private func code(_ line: String) -> String {
        guard let range = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }

    /// Why a line is reported. A line can hold several reasons at once.
    private enum Reason: String {
        /// A literal handed to the event constructor.
        case constructor = "a literal handed to EngineEvent(name:)"
        /// The name just before `.name` is `e` or spells "event".
        case receiverNamedLikeAnEvent = "the receiver is named like an event"
        /// The text ahead of the receiver spells "event": a collection of
        /// events, an event stream, a closure over events.
        case lineNamesEvents = "the line names events ahead of the receiver"
        /// The receiver is the name a `for x in` or `for await x in` on the line
        /// binds; `for try await`, `for case let` and `for var` are not matched.
        case receiverBoundByLoop = "the receiver is bound by a for loop"
        /// The receiver is not one plain identifier or `$N`: it ends in `]`,
        /// `)`, `?` or `!`, is missing, or sits behind a `.`.
        case receiverNotAPlainName = "the receiver is not one plain name"
        /// The literal is one lowercase-leading word of ASCII letters and digits,
        /// the shape a declared event name has, or it does not close on the line.
        case literalShapedLikeAnEventName = "the literal is shaped like an event name"
    }

    /// Reads each `.name == "` on the line for its receiver (the run of ASCII
    /// letters, digits, `_` and `$` just before `.name`) and its literal (up to
    /// the first unescaped quote), and reports the line for every reason that
    /// holds. `EngineEvent(name: "` is always reported. A comparison passes only
    /// when the receiver is one plain identifier or `$N`, is not `e`, does not
    /// spell "event", does not sit behind a `.`, and is not the name a `for x in`
    /// or `for await x in` on the line binds; nothing ahead of it on the line
    /// spells "event"; and the literal closes on the line and is not one
    /// lowercase-leading word of ASCII letters and digits. The names that fall
    /// outside that shape and pass are listed in
    /// `testAComparisonOfAnotherValuesNameWithALiteralIsNoOffence`.
    private func offences(in line: String) -> [Reason] {
        var found: [Reason] = []
        func add(_ reason: Reason) { if !found.contains(reason) { found.append(reason) } }

        if line.contains("EngineEvent(name: \"") { add(.constructor) }

        let marker = ".name == \""
        var from = line.startIndex
        while let hit = line.range(of: marker, range: from..<line.endIndex) {
            from = hit.upperBound
            let head = line[line.startIndex..<hit.lowerBound]

            var start = head.endIndex
            while start > head.startIndex {
                let before = head.index(before: start)
                let c = head[before]
                guard c.isASCII, c.isLetter || c.isNumber || c == "_" || c == "$" else { break }
                start = before
            }
            let receiver = String(head[start...])
            let ahead = head[head.startIndex..<start].lowercased()
            let behindADot = start > head.startIndex && head[head.index(before: start)] == "."

            if receiver == "e" || receiver.lowercased().contains("event") {
                add(.receiverNamedLikeAnEvent)
            }
            if ahead.contains("event") { add(.lineNamesEvents) }
            if isBoundByLoop(receiver, in: line) { add(.receiverBoundByLoop) }
            if !isPlainName(receiver) || behindADot { add(.receiverNotAPlainName) }

            var literal = ""
            var closed = false
            var escaped = false
            for c in line[hit.upperBound...] {
                if escaped { literal.append(c); escaped = false; continue }
                if c == "\\" { literal.append(c); escaped = true; continue }
                if c == "\"" { closed = true; break }
                literal.append(c)
            }
            if !closed || isShapedLikeAnEventName(literal) { add(.literalShapedLikeAnEventName) }
        }
        return found
    }

    /// One identifier, or `$` and digits.
    private func isPlainName(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        if first == "$" { return token.count > 1 && token.dropFirst().allSatisfy(\.isNumber) }
        return (first.isLetter || first == "_")
            && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// `for x in` or `for await x in` on the line, with `x` the receiver.
    private func isBoundByLoop(_ receiver: String, in line: String) -> Bool {
        guard !receiver.isEmpty,
              let loop = try? NSRegularExpression(
                  pattern: #"\bfor\s+(?:await\s+)?([A-Za-z_][A-Za-z0-9_]*)\s+in\b"#)
        else { return false }
        let whole = NSRange(line.startIndex..., in: line)
        return loop.matches(in: line, range: whole).contains { match in
            Range(match.range(at: 1), in: line).map { line[$0] == receiver } ?? false
        }
    }

    /// One lowercase ASCII letter, then ASCII letters and digits.
    private func isShapedLikeAnEventName(_ literal: String) -> Bool {
        guard let first = literal.first, first.isASCII, first.isLowercase else { return false }
        return literal.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    // MARK: - What the classifier reads as an event name

    /// A comparison of some other value's `name` with a literal is not an event
    /// name typed twice. A release asset is chosen by its file name, a file by
    /// its own: the lines below are fed to the classifier as they stand.
    func testAComparisonOfAnotherValuesNameWithALiteralIsNoOffence() {
        let lines = [
            // The updater's own line, verbatim.
            "        return zips.first { $0.name == \"Helm-\\(version).zip\" } ?? (zips.count == 1 ? zips[0] : nil)",
            "        let match = assets.first(where: { $0.name == \"Helm.dmg\" })",
            "        if file.name == \"Package.swift\" { return }",
            "        guard asset.name == \"Helm-\\(version).zip\" else { continue }",
            "        let both = pairs.filter { $0.name == \"a b\" && $1.name == \"c-d\" }",
        ]
        for line in lines {
            XCTAssertEqual(offences(in: code(line)), [],
                           "a name that belongs to a file or an asset was taken for an event's: \(line)")
        }
    }

    /// Each line is given with the reasons the classifier reports for it, and
    /// the reasons must be exactly those: a line is written so that one reason
    /// holds, and a second one appearing is a rule that has changed.
    func testEachReasonIsReportedOnALineThatShowsItAlone() {
        let rows: [(line: String, reasons: [Reason])] = [
            ("        transport.emit(EngineEvent(name: \"x\"))", [.constructor]),
            ("        if event.name == \"trash-changed\" { return }", [.receiverNamedLikeAnEvent]),
            ("        guard e.name == \"trash-changed\" else { return }", [.receiverNamedLikeAnEvent]),
            ("        let hit = events.first { $0.name == \"trash-changed\" }", [.lineNamesEvents]),
            ("        for await note in stream where note.name == \"trash-changed\" {", [.receiverBoundByLoop]),
            ("        if items[0].name == \"trash-changed\" { return }", [.receiverNotAPlainName]),
            ("        if makeItem().name == \"trash-changed\" { return }", [.receiverNotAPlainName]),
            ("        if model.current.name == \"trash-changed\" { return }", [.receiverNotAPlainName]),
            ("        if lookup()?.name == \"trash-changed\" { return }", [.receiverNotAPlainName]),
            ("        guard msg.name == \"trashChanged\" else { return }", [.literalShapedLikeAnEventName]),
            ("        let hit = received.first { $0.name == \"state\" }", [.literalShapedLikeAnEventName]),
            ("        guard msg.name == \"trash-changed", [.literalShapedLikeAnEventName]),
        ]
        for row in rows {
            XCTAssertEqual(offences(in: code(row.line)), row.reasons,
                           "the classifier's reasons for this line changed: \(row.line)")
        }
    }

    /// An event's name written as a string stays an offence, whichever way the
    /// line spells the receiver, and a line the classifier cannot place is
    /// reported rather than passed.
    func testAnEventNameWrittenAsALiteralIsAnOffence() {
        let lines = [
            // The header's own example.
            "            for await event in events where event.name == \"trashChanged\" {",
            "        transport.emit(EngineEvent(name: \"x\"))",
            "        guard e.name == \"state\" else { return }",
            "        let hit = events.first { $0.name == \"trashChanged\" }",
            // An event bound under a name that says nothing of events.
            "        for await note in transport.events where note.name == \"trashChanged\" {",
            "        guard msg.name == \"trashChanged\" else { return }",
            // A receiver the line does not name.
            "        if items[0].name == \"state\" { return }",
            "        if makeItem().name == \"state\" { return }",
            "        let hit = received.first { $0.name == \"state\" }",
            // A comparison that passes does not clear the one beside it.
            "        if a.name == \"Helm.dmg\" || event.name == \"trash-changed\" { return }",
        ]
        for line in lines {
            XCTAssertFalse(offences(in: code(line)).isEmpty,
                           "an event name written as a string went unreported: \(line)")
        }
    }

    func testNoEventNameIsWrittenAsALiteral() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")

        var offenders: [String] = []
        var scanned = 0
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            scanned += 1
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let text = code(line)
                for reason in offences(in: text) {
                    offenders.append("\(url.lastPathComponent):\(index + 1) — \(reason.rawValue): "
                                     + text.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        XCTAssertGreaterThan(scanned, 100,
                             "only \(scanned) source files were read, so a pass proves nothing")
        XCTAssertTrue(offenders.isEmpty,
                      "a line was reported as an event name written as a string (each line says why). "
                      + "If it is one, put it in the module's `<Module>Event` enum and re-export that "
                      + "through its descriptor, the way the hotkeys re-export their command enums — a "
                      + "renamed case is then a build error rather than a feature going quiet. If it is "
                      + "not, change `offences(in:)` and add the line to its rows, never the line:\n"
                      + offenders.joined(separator: "\n"))
    }
}
