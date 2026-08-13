import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Leftovers_UI
@testable import Module_Uninstaller_UI

/// A width written onto a picker has to fit that picker's own labels — in the
/// eight languages Helm ships, not in the one the number was chosen in.
///
/// **This is the measurement `LongStringGeometryRatchetTests` cannot take, and the
/// reason that file used to carry a red reminder instead.** That ratchet reads
/// `intrinsicContentSize` off the AppKit-backed views inside a rendered page, and
/// what it finds, measured over all nine pages, is 24 controls — 18 switches, 3
/// text fields, one search field, two segmented controls. What keeps it away from
/// the rest is that SwiftUI draws `Picker(.menu)`, `Button` and `Slider` itself on
/// macOS 26/27, so they are in no view tree at all.
///
/// **The second reason is gone, and this paragraph is what says so.** It used to
/// be that pages whose content arrives from an engine drew almost nothing —
/// Homebrew's whole page was 12 layers — so the segmented control in its toolbar
/// was measured in no render, in no language. `ModulePageRender.Wire` answers
/// those pages from a fixture now, and Homebrew's toolbar is in the ratchet's
/// reading. Leftovers' filter row and the log's level filter are the two left,
/// which is why they are the two `recorded` below: this file is the measurement of
/// what the render still cannot see, and it shrinks when the render grows.
///
/// **The rule here is the ratchet's own rule**, not a new one: a control drawn
/// narrower than the width it asks for clips (`testWhatDoesNotFitTodayDoesNotGrow`),
/// and one drawn narrower than 1.4 × that has no room for a longer word
/// (`testWhatBreaksOnAFortyPerCentLongerStringDoesNotGrow`). What is new is the
/// reach: the *imposed* width is read out of the source by a scan, and the width
/// the labels ask for is measured by hosting the same picker offscreen and reading
/// the same `intrinsicContentSize` — calibrated against the page's own reading for
/// the one control both can see.
///
/// The defect class has shipped twice here. `f69fcaf`: «the picker sizes itself —
/// a fixed 200 clipped Russian at 208». `HelmPickerWidth`'s own doc: «260 was 3 pt
/// from clipping in Russian and 110 pt too wide in Chinese». Both were a number
/// chosen against English and translated past, and both were invisible until
/// somebody switched the app to Russian and looked at it.
///
/// **And the sanctioned answer was a model of a different control.**
/// `HelmPickerWidth.segmented` used to add up the label widths and 26 pt a
/// segment, which is what `NSSegmentedControl` does with
/// `.segmentDistribution = .fit`. SwiftUI's `.segmented` picker fills its segments
/// **equally**: measured here, the hosted control's intrinsic width equals
/// `.fillEqually`'s `sizeToFit` in all 24 readings taken, and exceeded the old
/// answer by up to 140 pt (the log's level filter in Russian: 263 written, 403.5
/// asked for). Both sites that clipped were that arithmetic — once written out by
/// hand as 300, once called directly — and `PickerWidthTests` now pins the helper
/// against `.fillEqually` label set by label set.
@MainActor
final class AnImposedPickerWidthFitsItsLabelsTests: XCTestCase {

    // MARK: - What the source imposes

    /// How a site decides its width.
    private enum Imposed: Hashable {
        /// A number in the source, the `f69fcaf` shape.
        case points(CGFloat)
        /// `HelmPickerWidth.segmented`, computed from the same labels the picker
        /// draws — the sanctioned form, and a model of `.fit` rather than of what
        /// SwiftUI draws.
        case helmSegmented

        var described: String {
            switch self {
            case .points(let width): return "width \(Int(width))"
            case .helmSegmented: return "width HelmPickerWidth.segmented(…)"
            }
        }
    }

    /// One width written onto a picker, where it was written.
    private struct Site: Hashable {
        let file: String
        let line: Int
        let imposed: Imposed
        var shortFile: String { URL(fileURLWithPath: file).lastPathComponent }
        var key: String {
            switch imposed {
            case .points(let width): return "\(shortFile)|\(Int(width))"
            case .helmSegmented: return "\(shortFile)|HelmPickerWidth"
            }
        }
        var described: String { "\(shortFile):\(line) \(imposed.described)" }
    }

    /// The labels each site draws, as a function rather than as strings: they are
    /// `L()` lookups, and a stored value would freeze them in whatever language
    /// this machine happened to be in.
    ///
    /// Keyed by file and by what the width *is*, never by line number — a line is
    /// a fact about everything above it, so an edit elsewhere in the page would
    /// break the record without touching the picker. Changing the width does break
    /// it, which is the moment it has to be measured again.
    /// **One entry, and it is the computed one.** Leftovers' written 180 came off on
    /// 2026-08-13 in favour of `.fixedSize()` — the sixth page to have that figure
    /// and the last one in the tree — so what is left here is a width the labels
    /// themselves answer. The scan above is what keeps a seventh from arriving
    /// unmeasured: a new hand-written width fails `testTheScanAndTheRecordAgree`
    /// until somebody records the labels it is supposed to fit.
    private static let recorded: [String: @Sendable () -> [String]] = [
        "LogView.swift|HelmPickerWidth": { [AppStr.logLevelAll, AppStr.logLevelWarnings,
                                            AppStr.logLevelErrors] },
    ]

    /// **Measured 2026-08-11, three consecutive runs in agreement.** Both numbers
    /// were 2 and 3 when this file was written; what lowered them was
    /// `HelmPickerWidth.segmented` learning the control SwiftUI actually draws —
    /// `count × (widest label + 24)`, rounded up to the half point, which is
    /// `.fillEqually`'s own arithmetic to the point — and Homebrew's written 300
    /// coming off in favour of `.fixedSize()`.
    ///
    /// `clipping` is a site whose imposed width is under what its labels ask for in
    /// at least one language, and it is **zero**: the two that clipped were the
    /// `LogView` filter (short in seven of eight languages — ru 263 against 403.5)
    /// and Homebrew's toolbar (short in four — ru 366, ja 370.5, es 357, pt 303).
    ///
    /// `tight` is a site with less than 40 % of room, and **one** is left, there
    /// honestly:
    ///
    /// - `LogView.swift` is at **exactly** 1.00 × in all eight, because a computed
    ///   width *is* what the control asks for. That is the fix, not a finding:
    ///   headroom would be slack, AppKit centres a segmented control in the width
    ///   it is given, and the row's left edge would then walk off the 20 pt gutter
    ///   with the language. Padding this number to satisfy the ratchet would be
    ///   putting the defect back.
    ///
    /// It was 2 until 2026-08-13, and the other one was `LeftoversSettingsPage`'s
    /// written 180 — a control that asks 161 pt in English, 152 in Russian and 117
    /// in German, so up to 63 pt of the frame was slack AppKit spent on centring the
    /// control away from the page's gutter. `.fixedSize()` is what it takes now, and
    /// with it the last hand-written picker width in the tree is gone: every entry
    /// in `recorded` is computed from the labels it draws.
    ///
    /// Both numbers are only ever lowered, by the commit that lowers them.
    private static let recordedClipping = 0
    private static let recordedTight = 1
    private static let inflation: CGFloat = 1.4

    /// Every file a picker can be written in: the shared enumeration the ladder
    /// scans use — HelmUI plus the UI half of every module in `Package.swift` — and
    /// `HelmApp`'s own, which it does not cover. The log window and the panel are
    /// drawn UI too, and the log is where one of the two clipping sites is.
    private func uiFiles() throws -> [String] {
        try UISources.files() + RepoSource.swiftFiles(under: "Sources/HelmApp")
    }

    private func sites() throws -> [Site] {
        var read: [(String, [String])] = []
        for file in try uiFiles() {
            read.append((file, try RepoSource.lines(of: file)))
        }
        return Self.scan(files: read)
    }

    /// The scan, over text, so it can be shown the shapes it is looking for.
    ///
    /// A picker's modifiers are the contiguous chain after it, and that is what is
    /// walked: a window of «the next N lines» reported `HelmGlyphPicker`'s 40 pt
    /// grid cell, six lines under a category `Picker`, which carries no label and is
    /// not the picker's own frame. The chain ends at the first code line that does
    /// not continue it — which in that file is the `LazyVGrid` the cells are in.
    ///
    /// Comments are stripped by `RepoSource.code` first, and that is not optional:
    /// `HelmPickerWidth`'s doc comment says «260 was 3 pt from clipping», and a scan
    /// that read comments would report every rule's own explanation as an offence.
    private static func scan(files: [(String, [String])]) -> [Site] {
        var out: [Site] = []
        for (file, lines) in files {
            var inChain = false
            var depth = 0
            for (index, raw) in lines.enumerated() {
                let code = RepoSource.code(raw).trimmingCharacters(in: .whitespaces)
                guard !code.isEmpty else { continue }
                if code.contains("Picker(") || code.hasPrefix("Menu {") || code.contains("Menu(") {
                    inChain = true
                    depth = code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
                    continue
                }
                guard inChain else { continue }
                // Inside the picker's own content, or inside a modifier's closure.
                if depth > 0 {
                    depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
                    continue
                }
                // A modifier continues the chain; anything else ends it.
                guard code.hasPrefix(".") || code.hasPrefix("}") else { inChain = false; continue }
                depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
                if let width = number(after: ".frame(width:", in: code) {
                    out.append(Site(file: file, line: index + 1, imposed: .points(width)))
                } else if code.hasPrefix(".frame(width:"),
                          code.contains("HelmPickerWidth.segmented") {
                    out.append(Site(file: file, line: index + 1, imposed: .helmSegmented))
                }
            }
        }
        return out
    }

    private static func number(after prefix: String, in code: String) -> CGFloat? {
        guard code.hasPrefix(prefix) else { return nil }
        let rest = code.dropFirst(prefix.count).drop { $0 == " " }
        let digits = rest.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let value = Double(digits) else { return nil }
        return CGFloat(value)
    }

    // MARK: - What the labels ask for

    /// The same picker the page draws, hosted on its own.
    private struct Segmented: View {
        let labels: [String]
        @State private var choice = 0
        var body: some View {
            Picker("", selection: $choice) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// The width the hosted control asks for — the same `intrinsicContentSize`
    /// `ModulePageRender` reads, taken for a control no page in the suite draws.
    ///
    /// Hosted in 700 pt of room with a `Spacer` beside it, so the control is free
    /// to be as wide as it wants: a picker in a tight frame reports the frame.
    /// `-1` when nothing was found, so a missing control fails loudly instead of
    /// reading as a control that needs nothing.
    private func wanted(_ labels: [String]) -> CGFloat {
        let host = NSHostingView(rootView: AnyView(
            HStack { Segmented(labels: labels); Spacer(minLength: 0) }.frame(width: 700)))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 80)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        var found: CGFloat = -1
        for _ in 0..<60 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            walk(host) { view in
                if String(describing: type(of: view))
                    .hasPrefix("_NSCoreHostingView<AppKitSegmented") {
                    found = view.intrinsicContentSize.width
                }
            }
            if found > 0 { return found }
        }
        return found
    }

    private func walk(_ view: NSView, _ body: (NSView) -> Void) {
        body(view)
        view.subviews.forEach { walk($0, body) }
    }

    /// What a site imposes, in the language currently overridden.
    private func imposedWidth(_ site: Site, labels: [String]) -> CGFloat {
        switch site.imposed {
        case .points(let width): return width
        case .helmSegmented: return HelmPickerWidth.segmented(labels)
        }
    }

    // MARK: - The instrument measures the same thing the ratchet does

    /// **Calibration, and it is the first assertion for a reason.** The offscreen
    /// host and the rendered page are two instruments, and every number below comes
    /// from the first one. The Uninstaller's segmented control is the one control
    /// both can see: the page reports 161 pt in English, 208 in Russian and 117 in
    /// German (`LongStringGeometryRatchetTests` records the first two), and this
    /// host has to agree to the point.
    func testTheHostAgreesWithThePageOnTheOneControlBothCanSee() throws {
        let uninstaller = try XCTUnwrap(ModuleRegistry.all.first { $0.idRaw == "uninstaller" })
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in [AppLanguage.en, .ru, .de] {
            AppLanguage.override = language
            let page = ModulePageRender.page(for: uninstaller, in: .aqua,
                                             width: ModulePageRender.pageWidth)
            page.assertItDrewSomething()
            let drawn = try XCTUnwrap(page.controls.first { $0.name.contains("SegmentedControl") },
                                      "the uninstaller page drew no segmented control in "
                                      + "\(language.rawValue)")
            let mine = wanted([UnStr.tabApps, UnStr.tabOrphans])

            XCTAssertEqual(mine, drawn.intrinsic.width, accuracy: 0.5,
                           "the page says the uninstaller's picker wants "
                           + "\(drawn.intrinsic.width) pt in \(language.rawValue) and this "
                           + "file's own host says \(mine) — the two are not measuring the "
                           + "same control, so every number here is about something else")
        }
    }

    /// **The instrument refuses the width this app actually shipped.**
    ///
    /// `f69fcaf` took a `.frame(width: 200)` off the uninstaller's picker because
    /// Russian asked for 208. That number is what this file's yardstick answers for
    /// those two labels — so the ratchets above are not two assertions that happen
    /// to hold about two controls that happen to fit: the measurement is known to
    /// reject the one defect of this class the repository has shipped.
    func testTheYardstickRefusesTheWidthThatShipped() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = .ru

        let needed = wanted([UnStr.tabApps, UnStr.tabOrphans])

        XCTAssertGreaterThan(needed, 200,
                             "the uninstaller's two tabs ask for \(needed) pt in Russian, and "
                             + "the width that shipped was 200 — `f69fcaf` recorded 208. If they "
                             + "fit in 200 now, this instrument cannot fail for the defect it "
                             + "was written from")
    }

    /// And the yardstick answers at all. A `wanted` that returned `-1` everywhere
    /// would make both ratchets pass over nothing.
    func testTheYardstickAnswers() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = .ru
        XCTAssertGreaterThan(wanted([UnStr.tabApps, UnStr.tabOrphans]), 100,
                             "no hosted segmented control was found — nothing is being measured")
    }

    // MARK: - The scan is looking at the app, and knows what it finds

    /// Every width imposed on a picker in the tree is recorded with its labels, and
    /// every record still names a site. A new one has to be measured before it can
    /// pass; a site that has been fixed has to lose its record with it.
    func testTheScanAndTheRecordAgree() throws {
        let found = try sites()
        XCTAssertFalse(found.isEmpty,
                       "the scan finds no imposed picker width at all — it has stopped matching, "
                       + "and both ratchets below pass over an empty list")

        XCTAssertEqual(Set(found.map(\.key)), Set(Self.recorded.keys), """
            a picker carries a width nothing here has measured, or a record names a site that \
            has gone.
            found:    \(found.map(\.described).sorted().joined(separator: ", "))
            recorded: \(Self.recorded.keys.sorted().joined(separator: ", "))
            """)
    }

    /// The scan recognises the shape it was written for, and not the three shapes
    /// that are not the defect.
    ///
    /// Fixtures rather than edits to the tree: the offence is the pre-`f69fcaf`
    /// uninstaller, word for word, so the scan keeps being able to fail after the
    /// tree is clean — a check whose only subject is production code says nothing
    /// about what it would do with a defect.
    func testTheScanRecognisesTheDefectAndNotTheFix() {
        let offence = """
            Picker(HelmA11y.whatToShow, selection: $tab) {
                Text(UnStr.tabApps).tag(0)
                Text(UnStr.tabOrphans).tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            .frame(width: 200)
            """
        let sanctioned = """
            Picker(RuleStr.field, selection: $field) {
                ForEach(Field.allCases, id: \\.self) { Text($0.label) }
            }
            .frame(width: HelmPickerWidth.fitting(Field.labels, minimum: 150))
            """
        let notItsOwnFrame = """
            Picker(L("Category"), selection: $category) {
                ForEach(HelmGlyphCatalogue.categories) { group in
                    Text(group.title).tag(group.id)
                }
            }
            .labelsHidden()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 4)) {
                Image(systemName: symbol)
                    .frame(width: 40, height: 32)
            }
            """
        let onlyAComment = """
            /// Hard-coded widths are what this type exists to end — 260 was 3 pt
            /// from clipping in Russian, and `.frame(width: 200)` clipped at 208.
            public static func segmented(_ labels: [String]) -> CGFloat { 0 }
            """

        XCTAssertEqual(scanned(offence).map(\.imposed), [.points(200)],
                       "the scan cannot see the width that shipped a clipped Russian tab")
        XCTAssertEqual(scanned(sanctioned).count, 0,
                       "a pop-up sized by `HelmPickerWidth.fitting` is the fix, not a finding: "
                       + "its 48 pt of chrome is pinned against `NSPopUpButton.sizeToFit` in "
                       + "`PickerWidthTests`, and a pop-up shows one label at a time")
        XCTAssertEqual(scanned(notItsOwnFrame).count, 0,
                       "a 40 pt grid cell six lines under a category picker is being read as "
                       + "that picker's width")
        XCTAssertEqual(scanned(onlyAComment).count, 0,
                       "the scan is reading comments, so every rule explained in one is a hit")
    }

    private func scanned(_ text: String) -> [Site] {
        Self.scan(files: [("fixture.swift", text.components(separatedBy: "\n"))])
    }

    // MARK: - The two ratchets

    /// What is drawn narrower than its own labels, in a language Helm ships.
    func testWhatClipsTodayDoesNotGrow() throws {
        let short = try shortfalls { imposed, needed in imposed < needed }
        XCTAssertLessThanOrEqual(short.sites, Self.recordedClipping, """
            \(short.sites) pickers are drawn narrower than the words in them, over \
            \(short.lines.count) control-and-language pairs; the recorded number of controls is \
            \(Self.recordedClipping).
            This number is only ever lowered, by the commit that lowers it.
            \(short.lines.sorted().joined(separator: "\n"))
            """)
    }

    /// And what has no room for a longer word — the audit's 40 %, the same figure
    /// the string ratchet inflates by.
    func testWhatHasNoHeadroomDoesNotGrow() throws {
        let tight = try shortfalls { imposed, needed in imposed < needed * Self.inflation }
        XCTAssertLessThanOrEqual(tight.sites, Self.recordedTight, """
            \(tight.sites) pickers have less than \(Int((Self.inflation - 1) * 100))% of room \
            for their own labels; the recorded number is \(Self.recordedTight).
            This number is only ever lowered, by the commit that lowers it.
            \(tight.lines.sorted().joined(separator: "\n"))
            """)
    }

    /// One line per site, worst language named — a count says what to fix and not
    /// where to start, and the commit that lowers a number begins at a line.
    ///
    /// Counted per site rather than per language: one control with eight long
    /// translations is one thing to fix, and counting languages would make the
    /// number move when a translator changed a word.
    private func shortfalls(_ refuse: (CGFloat, CGFloat) -> Bool) throws -> Shortfall {
        var out = Shortfall()
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        for site in try sites() {
            let labels = try XCTUnwrap(Self.recorded[site.key],
                                       "\(site.described) has no labels recorded, so it cannot "
                                       + "be measured — a site nobody measured must not read as "
                                       + "a site that fits")
            for language in AppLanguage.allCases {
                AppLanguage.override = language
                let words = labels()
                let needed = wanted(words)
                XCTAssertGreaterThan(needed, 0,
                                     "\(site.described) in \(language.rawValue): nothing hosted")
                let imposed = imposedWidth(site, labels: words)
                guard refuse(imposed, needed) else { continue }
                out.add(site: site.described,
                        line: "  \(site.described): \(imposed) pt for \(needed) pt of label in "
                            + "\(language.rawValue) — \(words.joined(separator: " · "))")
            }
        }
        return out
    }

    /// Sites and the lines that describe them, kept apart on purpose: the number
    /// that is recorded counts **controls**, because one control with eight long
    /// translations is one thing to fix — a count of language pairs would move when
    /// a translator changed a word, and a ratchet that moves on the weather stops
    /// being read. The pairs are what the message carries.
    private struct Shortfall {
        private(set) var lines: Set<String> = []
        private var found: Set<String> = []
        var sites: Int { found.count }

        mutating func add(site: String, line: String) {
            found.insert(site)
            lines.insert(line)
        }
    }
}
