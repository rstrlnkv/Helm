import XCTest
import HelmTestSupport

/// **A setting written from two screens is re-read on the store's own
/// announcement, or the second screen lies about it.**
///
/// `LayoutSettingsPage` mirrors stored values into `@State` in its `init`,
/// which SwiftUI evaluates once per view identity — so a value written by
/// somebody else afterwards never reaches the mirror. The page was already
/// listening to `.helmStoreChanged` for exactly this reason, and refreshed two
/// keys on it: the never-list count and the app-rule count, both edited in the
/// lists window.
///
/// The three switches were not among them, and three of them are written from
/// elsewhere: the tour's step 3 writes all three, and the panel tile writes
/// `automatic` from its own toggle. Turn «Fix as I type» on at step 3 and the
/// switch of the same name a card below still read «off» — over an engine that
/// had already been told to start. It healed only when the settings window was
/// closed and reopened, which is a fresh `@State`.
///
/// **Derived, not listed.** The keys are computed from the other views' source
/// rather than written out here, because a hand-written list of names is tied
/// to nothing: a fourth switch added to the tour tomorrow would join the tour
/// and not this test, and the test would go on passing.
final class ASwitchWrittenElsewhereIsReReadTests: XCTestCase {

    /// Thrown when the scan cannot find what it reads. A scan that quietly
    /// answers nothing is a test that quietly passes, so it says so instead.
    private struct ScanFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepoSource.root.appendingPathComponent(path), encoding: .utf8)
    }

    private static let page = "Sources/Modules/Layout/UI/LayoutSettingsPage.swift"
    /// Every view that writes this module's settings and is not the page.
    private static let elsewhere = [
        "Sources/Modules/Layout/UI/LayoutTour.swift",
        "Sources/Modules/Layout/UI/LayoutDescriptor.swift",
        "Sources/Modules/Layout/UI/LayoutWidgets.swift",
    ]

    /// `LayoutKey.<name>` wherever it appears, comments stripped — this
    /// repository writes backticked names in doc comments on purpose, and a
    /// scan that counted those would find keys nobody writes.
    private func keysNamed(in text: String) -> Set<String> {
        var found: Set<String> = []
        let code = SwiftSource.uncommented(text)
        var rest = Substring(code)
        while let hit = rest.range(of: "LayoutKey.") {
            let tail = rest[hit.upperBound...]
            let name = tail.prefix { $0.isLetter || $0.isNumber }
            if !name.isEmpty { found.insert(String(name)) }
            rest = tail
        }
        return found
    }

    /// The body of the closure the page hands `.onReceive` for the store's
    /// announcement — from the first brace after the notification's name to the
    /// one that matches it.
    private func handlerBody(in text: String) throws -> String {
        guard let mention = text.range(of: "helmStoreChanged"),
              let open = text[mention.upperBound...].firstIndex(of: "{") else {
            throw ScanFailure("the page no longer observes `helmStoreChanged`")
        }
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" {
                depth -= 1
                if depth == 0 { return String(text[text.index(after: open)..<index]) }
            }
            index = text.index(after: index)
        }
        throw ScanFailure("the `helmStoreChanged` handler has no closing brace")
    }

    func testEveryKeyTheOtherViewsWriteIsRefreshedOnThePage() throws {
        let pageText = SwiftSource.uncommented(try source(Self.page))

        // What the page holds in `@State`: the keys it reads in its own `init`.
        guard let pageInit = SwiftSource.body(of: "init", in: pageText) else {
            return XCTFail("\(Self.page) has no `init` — the mirrors are somewhere else now")
        }
        let mirrored = keysNamed(in: pageInit)
        XCTAssertGreaterThan(mirrored.count, 4,
                             "the page mirrors \(mirrored.count) keys at init — the scan is "
                             + "reading the wrong body")

        // What somebody else writes.
        var writtenElsewhere: Set<String> = []
        for file in Self.elsewhere {
            let text = SwiftSource.uncommented(try source(file))
            guard text.contains("store.set(") || text.contains("write(") else { continue }
            writtenElsewhere.formUnion(keysNamed(in: text))
        }
        XCTAssertGreaterThan(writtenElsewhere.count, 2,
                             "found \(writtenElsewhere.count) keys written outside the page — "
                             + "the files listed here have moved or stopped writing")

        // And what the page re-reads when the store says so.
        //
        // **The handler's own braces, not the rest of the file.** The first
        // version of this took everything after the last `helmStoreChanged`,
        // which is the whole tail of the source — including `behaviourSection`,
        // where every one of these keys is named again in an `onChange`. The
        // mutation that should have proved this guard passed instead: the
        // refresh deleted, the name still found forty rows below.
        let refreshed = keysNamed(in: try handlerBody(in: pageText))

        for key in mirrored.intersection(writtenElsewhere).sorted() {
            XCTAssertTrue(refreshed.contains(key),
                          "`\(key)` is mirrored into @State by the page and written by another "
                          + "view, and the page never re-reads it — so the two disagree until "
                          + "the window is closed and reopened")
        }
    }
}
