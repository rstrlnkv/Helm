import CoreGraphics
import Foundation
import ObjectiveC
import XCTest
@testable import HelmApp

/// **A window's corner radius is read, in order, from the public reading, then
/// from the window's own `_cornerRadius`, then from a guess by chrome, and
/// last as a square: `WindowCorner.read` says which rung answered, and a
/// number that Helm made up is never passed off as one the window gave.**
///
/// No window is opened and no preference is touched. The window is a
/// test-local `NSObject` that answers one key, or answers it with the wrong
/// kind of value, or with a method that is not a getter of a floating-point
/// number, or raises or throws from the accessor, or does not know the key; each
/// stands for one side of the boundary the function reads across. The public
/// reading is a plain number handed in. The override a person may have set is
/// handed in too, as an `Any?`, so `UserDefaults` is never read.
///
/// What this file proves: the order of the rungs, that the guess moves with
/// the chrome it is handed, the bound 0...64 in both directions on both
/// readings, that a non-answer, a wrong type, an integer or Boolean answer, a
/// method of the wrong shape (which is not invoked), a `Float` answer accepted
/// on rung 2, the examined method answering and not a `get` variant of the key,
/// a raise and a throw of a
/// non-exception each end at the guess, that the journal is silent on a repeated
/// pair and bounded on a flapping one, and the words of the lines, foreign
/// text in the override included. What it cannot
/// prove: that a real `NSWindow` answers `_cornerRadius`, or that 26 and 16
/// are the corners macOS 26 draws; the 26 rows of the guess are stated on the
/// web and measured by nobody, the 27 row was measured on 27.2.
///
/// The radius this type returns is what `ShellGeometry.cardRadius(windowRadius:)`
/// is handed.
final class TheWindowsCornerIsReadNotAssumedTests: XCTestCase {

    // MARK: - the fakes: one side of the boundary each

    /// A window that answers `_cornerRadius` with a number.
    private final class AnsweringWindow: NSObject {
        @objc(_cornerRadius) var radius: CGFloat
        init(_ radius: CGFloat = 26) {
            self.radius = radius
            super.init()
        }
    }

    /// A window that answers all three keys the line prints, with numbers.
    private final class ThreeKeyWindow: NSObject {
        @objc(_cornerRadius) var radius: CGFloat = 16
        @objc(_topCornerRadius) var top: CGFloat = 16
        @objc(_bottomCornerRadius) var bottom: CGFloat = 16
    }

    /// An object that answers the key with text: a getter that returns an object, not a floating-point number.
    private final class StringAnswering: NSObject {
        @objc(_cornerRadius) var radius: String = "26"
    }

    /// An object that answers the key with a struct: a getter that returns a struct, not a floating-point number.
    private final class StructAnswering: NSObject {
        @objc(_cornerRadius) var radius: NSRange = NSRange(location: 26, length: 26)
    }

    /// An object whose accessor raises an Objective-C exception.
    private final class RaisingWindow: NSObject {
        @objc(_cornerRadius) var radius: CGFloat {
            NSException(name: .genericException, reason: nil).raise()
            return 26
        }
    }

    /// A throw that is not an `NSException`: an `NSString` goes through
    /// `objc_exception_throw`, which is what an Objective-C `@throw @"text"` does.
    private final class StringThrowingWindow: NSObject {
        @objc(_cornerRadius) var radius: CGFloat {
            objc_exception_throw("text" as NSString)
        }
    }

    /// A window whose key answers a `Float`: type `f`, a floating-point number.
    private final class FloatAnswering: NSObject {
        @objc(_cornerRadius) var radius: Float = 26
    }

    /// Three methods spelled as the key that are not getters of a floating-point
    /// number; each records that it ran.
    private final class VoidMethod: NSObject {
        var ran = false
        @objc(_cornerRadius) func answer() { ran = true }
    }
    private final class IntegerMethod: NSObject {
        var ran = false
        @objc(_cornerRadius) func answer() -> Int { ran = true; return 26 }
    }
    private final class ObjectMethod: NSObject {
        var ran = false
        @objc(_cornerRadius) func answer() -> NSNumber { ran = true; return NSNumber(value: 26.0) }
    }

    // MARK: - inputs

    private static func chrome(_ major: Int, toolbar: Bool) -> WindowCorner.Chrome {
        WindowCorner.Chrome(hasToolbar: toolbar, systemMajor: major)
    }

    /// A chrome whose guess is 16, so a window's 26 can never be mistaken for it.
    private static let sixteenGuess = chrome(26, toolbar: false)

    private static func system(_ major: Int, _ minor: Int, _ patch: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
    }

    private static func corner(_ radius: CGFloat, _ rung: WindowCorner.Rung) -> WindowCorner {
        WindowCorner(radius: radius, rung: rung)
    }

    // MARK: - the order of the ladder, and the journal

    func testWithoutAPublicReadingTheWindowsOwnNumberCutsTheCard() {
        let read = WindowCorner.read(publicReading: nil, from: AnsweringWindow(),
                                     chrome: Self.sixteenGuess)

        // The subject happened: something was read, and the guess here is not 26.
        XCTAssertEqual(WindowCorner.guess(for: Self.sixteenGuess), 16,
                       "the chrome of this test no longer guesses a number other than the window's")

        XCTAssertEqual(read, Self.corner(26, .windowSelector),
                       "the window answered 26 and the card was cut for \(read.radius): the window's own number lost to a guess")
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: read.radius), 22,
                       "the window answered 26 and the card was cut for \(ShellGeometry.cardRadius(windowRadius: read.radius)): the window's own number lost to a guess")
    }

    func testWithNothingReadTheGuessFollowsTheChromeAndIsCalledAGuess() {
        let withBar = WindowCorner.read(publicReading: nil, from: NSObject(),
                                        chrome: Self.chrome(26, toolbar: true))
        let withoutBar = WindowCorner.read(publicReading: nil, from: NSObject(),
                                           chrome: Self.chrome(26, toolbar: false))

        XCTAssertEqual(withBar, Self.corner(26, .guess),
                       "a guess was drawn and it is not 26 with the rung .guess for a macOS 26 window with a toolbar: got \(withBar)")
        XCTAssertEqual(withoutBar, Self.corner(16, .guess),
                       "a guess was drawn and it is not 16 with the rung .guess for a macOS 26 window without a toolbar: got \(withoutBar)")
        XCTAssertNotEqual(withBar.radius, withoutBar.radius,
                          "a macOS 26 window with a toolbar and one without got the same guess: the bottom rung is one constant again")

        for toolbar in [true, false] {
            let on27 = WindowCorner.read(publicReading: nil, from: NSObject(),
                                         chrome: Self.chrome(27, toolbar: toolbar))
            XCTAssertEqual(on27, Self.corner(16, .guess),
                           "macOS 27 (toolbar \(toolbar)) did not read as a guess of 16: got \(on27)")

            let on28 = WindowCorner.read(publicReading: nil, from: NSObject(),
                                         chrome: Self.chrome(28, toolbar: toolbar))
            XCTAssertEqual(on28, Self.corner(0, .none),
                           "a system nobody described (macOS 28, toolbar \(toolbar)) got a number of Helm's instead of a square card: got \(on28)")
        }
    }

    func testFiftyAsksForOnePairWriteOneLine() {
        let pair = Self.corner(16, .publicAPI)
        var journal = WindowCorner.Journal()
        var made = 0
        var lines: [String] = []
        for _ in 0..<50 {
            if let line = journal.line(for: pair, { made += 1; return "corner 16.0" }) { lines.append(line) }
        }
        XCTAssertEqual(lines.count, 1, "fifty asks wrote \(lines.count) lines")
        XCTAssertEqual(made, 1, "the line was built \(made) times for one pair: make ran when no line was due")

        // Alternating pairs: bounded by the cap, the last line says so, and
        // nothing is built after it.
        let a = Self.corner(16, .publicAPI)
        let b = Self.corner(26, .windowSelector)
        var flapping = WindowCorner.Journal()
        var flappingMade = 0
        var flappingLines: [String] = []
        for index in 0..<50 {
            let corner = index.isMultiple(of: 2) ? a : b
            if let line = flapping.line(for: corner, { flappingMade += 1; return "line \(flappingMade)" }) {
                flappingLines.append(line)
            }
        }
        let tail = "; further changes in this window are not logged"
        XCTAssertEqual(WindowCorner.Journal.cap, 8)
        XCTAssertEqual(flappingLines.count, WindowCorner.Journal.cap,
                       "fifty alternating asks wrote \(flappingLines.count) lines, not \(WindowCorner.Journal.cap)")
        XCTAssertEqual(flappingMade, WindowCorner.Journal.cap, "make ran after the cap, for a line nobody was owed")
        XCTAssertTrue(flappingLines.last?.hasSuffix(tail) == true,
                      "the last line does not say further changes are not logged: \(flappingLines.last ?? "none")")
        XCTAssertEqual(flappingLines.dropLast().filter { $0.hasSuffix(tail) }.count, 0,
                       "a line before the last one already said the log was closed")
    }

    /// The journal keys on the pair, not the radius: the same radius reached by
    /// another rung (a guess that the window later confirms) is a change a
    /// reader of the log needs, and the same pair twice is not.
    func testTheSameRadiusByAnotherRungIsALineOfItsOwn() {
        var journal = WindowCorner.Journal()
        var lines: [String] = []
        let sequence = [Self.corner(16, .guess), Self.corner(16, .publicAPI), Self.corner(16, .publicAPI),
                        Self.corner(16, .windowSelector), Self.corner(16, .guess)]
        for (index, corner) in sequence.enumerated() {
            if let line = journal.line(for: corner, { "line \(index)" }) { lines.append(line) }
        }
        XCTAssertEqual(lines, ["line 0", "line 1", "line 3", "line 4"],
                       "same radius, different rung must write a line; the same pair twice must not: \(lines)")
    }

    // MARK: - the rungs

    func testAPublicReadingWinsOverTheWindowWhateverTheChrome() {
        for chrome in [Self.chrome(26, toolbar: true), Self.chrome(26, toolbar: false),
                       Self.chrome(27, toolbar: true), Self.chrome(28, toolbar: false)] {
            let read = WindowCorner.read(publicReading: 16, from: AnsweringWindow(), chrome: chrome)
            XCTAssertEqual(read, Self.corner(16, .publicAPI),
                           "the public reading 16 lost to the window or to a guess for \(chrome): got \(read)")
        }
    }

    func testNoWindowBehavesAsAnObjectThatKnowsNothing() {
        for chrome in [Self.chrome(26, toolbar: true), Self.chrome(26, toolbar: false),
                       Self.chrome(27, toolbar: false), Self.chrome(28, toolbar: true)] {
            XCTAssertEqual(WindowCorner.read(publicReading: nil, from: nil, chrome: chrome),
                           WindowCorner.read(publicReading: nil, from: NSObject(), chrome: chrome),
                           "no window read differently from a bare object for \(chrome)")
        }
        XCTAssertEqual(WindowCorner.read(publicReading: nil, from: nil, chrome: Self.chrome(26, toolbar: true)),
                       Self.corner(26, .guess), "no window and nothing to read did not end at the guess")
    }

    func testTheGuessIsStatedForTwoSystemsAndNobodyElse() {
        XCTAssertEqual(WindowCorner.guess(for: Self.chrome(26, toolbar: true)), 26)
        XCTAssertEqual(WindowCorner.guess(for: Self.chrome(26, toolbar: false)), 16)
        XCTAssertEqual(WindowCorner.guess(for: Self.chrome(27, toolbar: true)), 16)
        XCTAssertEqual(WindowCorner.guess(for: Self.chrome(27, toolbar: false)), 16)
        for major in [0, 15, 25, 28, 99] {
            for toolbar in [true, false] {
                XCTAssertNil(WindowCorner.guess(for: Self.chrome(major, toolbar: toolbar)),
                             "a number of Helm's was invented for macOS \(major) (toolbar \(toolbar)), which nobody has described")
            }
        }
    }

    // MARK: - the window's own number, and the bound

    func testAWindowAnswerThatIsNotAnAnswerFallsToTheGuess() {
        let chrome = Self.sixteenGuess
        for answer in [CGFloat.nan, .infinity, -.infinity, -1, 0] {
            let read = WindowCorner.read(publicReading: nil, from: AnsweringWindow(answer), chrome: chrome)
            XCTAssertEqual(read, Self.corner(16, .guess),
                           "the window answered \(answer) and the ladder landed on \(read) instead of going down to the guess")
        }
    }

    func testAWindowAnswerAboveTheCeilingIsHeldAtTheCeiling() {
        XCTAssertEqual(WindowCorner.believable, 0...64)
        for answer in [CGFloat(500), 64.5, .greatestFiniteMagnitude] {
            let read = WindowCorner.read(publicReading: nil, from: AnsweringWindow(answer), chrome: Self.sixteenGuess)
            XCTAssertEqual(read, Self.corner(64, .windowSelector),
                           "the window answered \(answer) and the card was cut for \(read.radius), not held at 64")
        }
        // The ceiling itself and a small honest number pass untouched.
        XCTAssertEqual(WindowCorner.read(publicReading: nil, from: AnsweringWindow(64), chrome: Self.sixteenGuess),
                       Self.corner(64, .windowSelector))
        XCTAssertEqual(WindowCorner.read(publicReading: nil, from: AnsweringWindow(0.5), chrome: Self.sixteenGuess),
                       Self.corner(0.5, .windowSelector))
    }

    func testAPublicReadingThatIsNotANumberFallsToTheWindowNotToABound() {
        for reading in [CGFloat.nan, .infinity, -.infinity] {
            let read = WindowCorner.read(publicReading: reading, from: AnsweringWindow(), chrome: Self.sixteenGuess)
            XCTAssertEqual(read, Self.corner(26, .windowSelector),
                           "the public reading \(reading) was believed or landed on a bound instead of going down a rung: got \(read)")

            let bare = WindowCorner.read(publicReading: reading, from: NSObject(), chrome: Self.sixteenGuess)
            XCTAssertEqual(bare, Self.corner(16, .guess),
                           "the public reading \(reading) with nothing below it did not end at the guess: got \(bare)")
        }
    }

    func testAPublicReadingOfZeroIsAnAnswerAndAnOutOfRangeOneIsHeld() {
        XCTAssertEqual(WindowCorner.read(publicReading: 0, from: AnsweringWindow(), chrome: Self.sixteenGuess),
                       Self.corner(0, .publicAPI), "a public zero was taken for 'not set' and the window or a guess answered over it")
        XCTAssertEqual(WindowCorner.read(publicReading: 500, from: AnsweringWindow(), chrome: Self.sixteenGuess),
                       Self.corner(64, .publicAPI), "a public 500 was not held at 64")
        XCTAssertEqual(WindowCorner.read(publicReading: -3, from: AnsweringWindow(), chrome: Self.sixteenGuess),
                       Self.corner(0, .publicAPI), "a public -3 was not held at 0")
    }

    // MARK: - an answer of the wrong kind, and a raise

    func testAnObjectAnsweringWithTextOrAStructFallsToTheGuess() {
        let chrome = Self.sixteenGuess
        XCTAssertEqual(WindowCorner.read(publicReading: nil, from: StringAnswering(), chrome: chrome),
                       Self.corner(16, .guess), "text in the key's place was read as a number")
        XCTAssertEqual(WindowCorner.read(publicReading: nil, from: StructAnswering(), chrome: chrome),
                       Self.corner(16, .guess), "a struct in the key's place was read as a number")
    }

    func testAnAccessorThatRaisesFallsToTheGuessThreeTimesRunning() {
        let window = RaisingWindow()
        var reads: [WindowCorner] = []
        for _ in 0..<3 {
            reads.append(WindowCorner.read(publicReading: nil, from: window, chrome: Self.sixteenGuess))
        }
        // The equality is the proof: a raise that got through is reported by
        // XCTest as a failure of this test, and no read lands on the guess.
        XCTAssertEqual(reads, Array(repeating: Self.corner(16, .guess), count: 3),
                       "a raising accessor did not end at the guess three times running: \(reads)")
    }

    func testAThrowThatIsNotAnExceptionFallsToTheGuessThreeTimesRunning() {
        let window = StringThrowingWindow()
        var reads: [WindowCorner] = []
        for _ in 0..<3 {
            reads.append(WindowCorner.read(publicReading: nil, from: window, chrome: Self.sixteenGuess))
        }
        XCTAssertEqual(reads, Array(repeating: Self.corner(16, .guess), count: 3),
                       "a thrown NSString did not end at the guess three times running: \(reads)")
    }

    // MARK: - the shape of the method: only a getter of a floating-point number is believed

    func testAMethodThatIsNotAGetterOfAFloatingPointNumberIsNotInvoked() {
        let void = VoidMethod()
        let integer = IntegerMethod()
        let object = ObjectMethod()
        for window in [void, integer, object] as [NSObject] {
            XCTAssertTrue(window.responds(to: NSSelectorFromString(WindowCorner.selector)),
                          "\(type(of: window)) does not answer the key: the test would pass without the shape test")
            let read = WindowCorner.read(publicReading: nil, from: window, chrome: Self.sixteenGuess)
            XCTAssertEqual(read, Self.corner(16, .guess),
                           "a method of the wrong shape on \(type(of: window)) was believed: \(read)")
        }
        XCTAssertFalse(void.ran, "a method returning nothing was invoked")
        XCTAssertFalse(integer.ran, "a method returning an integer was invoked")
        XCTAssertFalse(object.ran, "a method returning an object was invoked")
    }

    func testAFloatAnswerIsReadAsANumberOnRungTwo() {
        let read = WindowCorner.read(publicReading: nil, from: FloatAnswering(), chrome: Self.sixteenGuess)
        XCTAssertEqual(read, Self.corner(26, .windowSelector),
                       "a Float 26 was not read as the window's number: \(read)")
    }

    // MARK: - the line

    func testALineForARungOneOrTwoNamesTheRungAndPrintsTheThreeNumbersAsTheyCame() {
        let line = WindowCorner.logLine(Self.corner(16, .publicAPI), chrome: Self.chrome(27, toolbar: true),
                                        window: ThreeKeyWindow(), override: nil, system: Self.system(27, 2, 0))
        XCTAssertEqual(line,
                       "corner 16.0 by public; card 12.0; toolbar yes; _cornerRadius 16.0, _topCornerRadius 16.0, _bottomCornerRadius 16.0; override -; macOS 27.2.0",
                       "the line a person reads for a public reading changed")

        let window = WindowCorner.logLine(Self.corner(26, .windowSelector), chrome: Self.chrome(26, toolbar: false),
                                          window: AnsweringWindow(), override: nil, system: Self.system(26, 4, 1))
        XCTAssertTrue(window.hasPrefix("corner 26.0 by window selector; card 22.0; toolbar no; "),
                      "the line for the window's own number does not name its rung and the card: \(window)")
        XCTAssertTrue(window.hasSuffix("; override -; macOS 26.4.1"), window)
        XCTAssertFalse(window.contains("not read"), "a number the window gave was reported as not read: \(window)")
        XCTAssertFalse(window.contains("guessed"), "a number the window gave was reported as a guess: \(window)")
    }

    func testALineForAGuessSaysSoAndSaysWhereTheNumberCameFrom() {
        let on26 = WindowCorner.logLine(Self.corner(26, .guess), chrome: Self.chrome(26, toolbar: true),
                                        window: NSObject(), override: nil, system: Self.system(26, 4, 1))
        XCTAssertEqual(on26,
                       "corner not read: no public reading, _cornerRadius absent; guessed 26.0 for macOS 26 with a toolbar (from the web, unmeasured); card 22.0; override -; macOS 26.4.1",
                       "a guess was drawn and the line does not call it one, or does not say where it came from")

        let noBar = WindowCorner.logLine(Self.corner(16, .guess), chrome: Self.chrome(26, toolbar: false),
                                         window: NSObject(), override: nil, system: Self.system(26, 0, 0))
        for phrase in ["not read", "guessed 16.0 for macOS 26 without a toolbar", "from the web, unmeasured", "card 12.0"] {
            XCTAssertTrue(noBar.contains(phrase), "a guess was drawn and the line lacks \"\(phrase)\": \(noBar)")
        }

        let on27 = WindowCorner.logLine(Self.corner(16, .guess), chrome: Self.chrome(27, toolbar: true),
                                        window: NSObject(), override: nil, system: Self.system(27, 2, 0))
        for phrase in ["not read", "guessed 16.0 for macOS 27 with a toolbar", "(measured on 27.2)"] {
            XCTAssertTrue(on27.contains(phrase), "a guess was drawn and the line lacks \"\(phrase)\": \(on27)")
        }
        XCTAssertFalse(on27.contains("from the web"), "the 27 row was measured, and the line says it is from the web: \(on27)")
    }

    func testALineForNothingToGuessFromSaysTheCardIsSquare() {
        let line = WindowCorner.logLine(Self.corner(0, .none), chrome: Self.chrome(28, toolbar: false),
                                        window: NSObject(), override: nil, system: Self.system(28, 0, 0))
        XCTAssertTrue(line.hasPrefix("corner not read and nothing to guess from for macOS 28 without a toolbar; card square; "),
                      "a square card was drawn and the line does not say there was nothing to guess from: \(line)")
        XCTAssertFalse(line.contains("guessed"), "a number nobody stated was reported as a guess: \(line)")
        XCTAssertTrue(line.hasSuffix("; macOS 28.0.0"), line)
    }

    func testALineTellsAbsentFromRespondingWithNoNumber() {
        let chrome = Self.chrome(26, toolbar: true)
        let os = Self.system(26, 4, 1)
        let absent = WindowCorner.logLine(Self.corner(26, .guess), chrome: chrome, window: NSObject(),
                                          override: nil, system: os)
        let silent = WindowCorner.logLine(Self.corner(26, .guess), chrome: chrome, window: StringAnswering(),
                                          override: nil, system: os)
        XCTAssertTrue(absent.contains("_cornerRadius absent"), "an object without the key is not told as absent: \(absent)")
        XCTAssertTrue(silent.contains("_cornerRadius -"),
                      "an object that answers the key with no number is not told as '-': \(silent)")
        XCTAssertFalse(silent.contains("_cornerRadius absent"), "an object that responds was told as absent: \(silent)")
        XCTAssertNotEqual(absent, silent, "absent and responding-with-no-number print the same line")

        let nobody = WindowCorner.logLine(Self.corner(26, .guess), chrome: chrome, window: nil,
                                          override: nil, system: os)
        XCTAssertTrue(nobody.contains("_cornerRadius absent"), "no window is not told as absent: \(nobody)")
    }

    func testTheOverrideIsPrintedAsADashANumberOrTheWordsNotANumber() {
        let chrome = Self.chrome(26, toolbar: true)
        let os = Self.system(26, 4, 1)
        func line(_ override: Any?) -> String {
            WindowCorner.logLine(Self.corner(26, .guess), chrome: chrome, window: NSObject(),
                                 override: override, system: os)
        }
        XCTAssertTrue(line(nil).contains("override -;"), "no override did not print '-': \(line(nil))")
        XCTAssertTrue(line(26).contains("override 26;"), "an Int override of 26 was not printed as 26: \(line(26))")
        XCTAssertTrue(line(26.5).contains("override 26.5;"), "a Double override of 26.5 was not printed as 26.5: \(line(26.5))")
        XCTAssertNotEqual(line(nil), line(26))
        XCTAssertEqual(WindowCorner.overrideKey, "NSConvolutionOverride1")
    }

    func testAnOverrideThatIsNotANumberNeverEntersTheLine() {
        let chrome = Self.chrome(26, toolbar: true)
        let os = Self.system(26, 4, 1)
        let long = String(repeating: "ZZZZ", count: 1000)
        let foreign: [(Any, String)] = [("FOREIGN\nTEXT", "FOREIGN"), (long, "ZZZZ"), (["FOREIGNARRAY", 1] as [Any], "FOREIGNARRAY")]
        for (override, marker) in foreign {
            let line = WindowCorner.logLine(Self.corner(26, .guess), chrome: chrome, window: NSObject(),
                                            override: override, system: os)
            XCTAssertTrue(line.contains("override not a number;"), "a foreign override was not told as 'not a number': \(line.prefix(300))")
            XCTAssertFalse(line.contains(marker), "foreign text entered the line: \(line.prefix(300))")
            XCTAssertFalse(line.contains("\n"), "a newline from the override entered the line: \(line.prefix(300))")
            XCTAssertLessThan(line.count, 400, "the line grew with the override: \(line.count) characters")
        }
    }

    // MARK: - an answer of an unusual kind, in a line and in the read; the spelling of the keys

    /// An object whose key answers an `Int` boxed as an `NSNumber`.
    private final class IntAnswering: NSObject {
        @objc(_cornerRadius) var radius: NSNumber = NSNumber(value: 26 as Int)
    }

    /// An object whose key answers a Swift `Int` property: not a floating-point return type.
    private final class IntPropertyAnswering: NSObject {
        @objc(_cornerRadius) var radius: Int = 26
    }

    /// An object whose key answers a `Bool`: not a floating-point return type.
    private final class BoolAnswering: NSObject {
        @objc(_cornerRadius) var radius: Bool = true
    }

    /// An object whose key answers `NSNumber(value: true)`: a getter that returns an object.
    private final class BoolNumberAnswering: NSObject {
        @objc(_cornerRadius) var radius: NSNumber = NSNumber(value: true)
    }

    func testALineBuiltForAWindowWhoseAccessorRaisesIsStillALineWithADash() {
        let window = RaisingWindow()
        let os = Self.system(26, 4, 1)
        let chrome = Self.sixteenGuess
        var lines: [String] = []
        for _ in 0..<3 {
            lines.append(WindowCorner.logLine(Self.corner(16, .guess), chrome: chrome, window: window,
                                              override: nil, system: os))
        }
        XCTAssertEqual(lines.count, 3)
        for line in lines {
            XCTAssertTrue(line.contains("_cornerRadius -;"),
                          "a window that responds and raises was not told as '-': \(line)")
            XCTAssertFalse(line.contains("_cornerRadius absent"), "a raising window was told as absent: \(line)")
        }
        XCTAssertEqual(Set(lines).count, 1, "the same raising window printed different lines: \(lines)")

        for rung in [WindowCorner.Rung.publicAPI, .windowSelector] {
            let line = WindowCorner.logLine(Self.corner(16, rung), chrome: chrome, window: window,
                                            override: nil, system: os)
            XCTAssertTrue(line.contains("_cornerRadius -, _topCornerRadius absent, _bottomCornerRadius absent"),
                          "a rung-\(rung) line for a raising window lost a key: \(line)")
        }
        let none = WindowCorner.logLine(Self.corner(0, .none), chrome: Self.chrome(28, toolbar: true), window: window,
                                        override: nil, system: Self.system(28, 0, 0))
        XCTAssertTrue(none.contains("_cornerRadius -;"), none)
    }

    func testAGuessLineShowsTheRawNumberAWindowRefusedNotAbsentAndNotADash() {
        let chrome = Self.sixteenGuess
        let os = Self.system(26, 4, 1)
        let expected: [(CGFloat, String)] = [(0, "0.0"), (.nan, "nan"), (-1, "-1.0")]
        for (answer, slot) in expected {
            let window = AnsweringWindow(answer)
            // The ladder refuses it, and the line is built for that very read.
            let read = WindowCorner.read(publicReading: nil, from: window, chrome: chrome)
            XCTAssertEqual(read, Self.corner(16, .guess), "the answer \(answer) was not refused by the ladder")
            let line = WindowCorner.logLine(read, chrome: chrome, window: window, override: nil, system: os)
            XCTAssertTrue(line.contains("no public reading, _cornerRadius \(slot);"),
                          "the window answered \(answer) and the slot did not show \(slot): \(line)")
            XCTAssertFalse(line.contains("_cornerRadius absent"), "an answered \(answer) was told as absent: \(line)")
            XCTAssertFalse(line.contains("_cornerRadius -;"), "an answered \(answer) was told as '-': \(line)")
        }
    }

    /// Only a getter of a floating-point number is believed: an integer answer,
    /// boxed or not, is refused and the ladder goes to the guess, because a method
    /// of that shape is not what the window's corner is answered with.
    func testAnIntegerAnswerIsRefusedAndTheLadderGoesToTheGuess() {
        for window in [IntAnswering(), IntPropertyAnswering()] as [NSObject] {
            let read = WindowCorner.read(publicReading: nil, from: window, chrome: Self.sixteenGuess)
            XCTAssertEqual(read, Self.corner(16, .guess),
                           "an integer 26 from \(type(of: window)) was believed or did not end at the guess: \(read)")
        }
    }

    /// A Boolean answer, whether a `Bool` getter or a getter that returns an
    /// `NSNumber` holding one, is refused for its return type and not invoked; read
    /// as a number it would be a one-point corner.
    func testABooleanAnswerIsRefusedAndTheLadderGoesToTheGuess() {
        for window in [BoolNumberAnswering(), BoolAnswering()] as [NSObject] {
            let read = WindowCorner.read(publicReading: nil, from: window, chrome: Self.sixteenGuess)
            XCTAssertEqual(read, Self.corner(16, .guess),
                           "a Bool from \(type(of: window)) was believed or did not end at the guess: \(read)")
        }
    }

    // MARK: - only the method that was examined answers

    /// Key-value coding looks for `get<Key>` before the key itself; these are
    /// objects that have both, the second a method nobody examined.
    private final class DoubleWithGetInteger: NSObject {
        var gotRan = false
        @objc(_cornerRadius) var radius: Double = 26
        @objc(get_cornerRadius) func got() -> Int { gotRan = true; return 99 }
    }
    private final class DoubleWithGetVoid: NSObject {
        var gotRan = false
        @objc(_cornerRadius) var radius: Double = 26
        @objc(get_cornerRadius) func got() { gotRan = true }
    }
    private final class DoubleWithGetString: NSObject {
        var gotRan = false
        @objc(_cornerRadius) var radius: Double = 26
        @objc(get_cornerRadius) func got() -> NSString { gotRan = true; return "text" }
    }

    func testAGetVariantOfTheKeyDoesNotAnswerInPlaceOfTheExaminedMethod() {
        let integer = DoubleWithGetInteger()
        let read = WindowCorner.read(publicReading: nil, from: integer, chrome: Self.sixteenGuess)
        XCTAssertEqual(read, Self.corner(26, .windowSelector),
                       "the number came from a method nobody examined (get_cornerRadius): got \(read), the examined _cornerRadius answers 26")
        XCTAssertFalse(integer.gotRan, "get_cornerRadius ran: a method nobody examined was invoked in place of _cornerRadius")

        let void = DoubleWithGetVoid()
        let readVoid = WindowCorner.read(publicReading: nil, from: void, chrome: Self.sixteenGuess)
        XCTAssertEqual(readVoid, Self.corner(26, .windowSelector),
                       "a get_cornerRadius that returns nothing took the place of _cornerRadius: got \(readVoid)")
        XCTAssertFalse(void.gotRan, "a get_cornerRadius that returns nothing was invoked")

        let string = DoubleWithGetString()
        let readString = WindowCorner.read(publicReading: nil, from: string, chrome: Self.sixteenGuess)
        XCTAssertEqual(readString, Self.corner(26, .windowSelector),
                       "a get_cornerRadius that returns text took the place of _cornerRadius: got \(readString)")
        XCTAssertFalse(string.gotRan, "a get_cornerRadius that returns text was invoked")
    }

    func testTheLineShowsTheExaminedMethodsNumberNotAGetVariants() {
        let chrome = Self.sixteenGuess
        let os = Self.system(26, 4, 1)
        for window in [DoubleWithGetInteger(), DoubleWithGetVoid(), DoubleWithGetString()] as [NSObject] {
            let line = WindowCorner.logLine(Self.corner(26, .windowSelector), chrome: chrome, window: window,
                                            override: nil, system: os)
            XCTAssertTrue(line.contains("_cornerRadius 26.0, _topCornerRadius absent"),
                          "the slot printed for _cornerRadius did not come from the examined method on \(type(of: window)): \(line)")
            let guess = WindowCorner.logLine(Self.corner(16, .guess), chrome: chrome, window: window,
                                             override: nil, system: os)
            XCTAssertTrue(guess.contains("no public reading, _cornerRadius 26.0;"),
                          "the guess line's slot did not come from the examined method on \(type(of: window)): \(guess)")
        }
        let void = DoubleWithGetVoid()
        _ = WindowCorner.logLine(Self.corner(26, .windowSelector), chrome: chrome, window: void, override: nil, system: os)
        XCTAssertFalse(void.gotRan, "building the line invoked get_cornerRadius, a method nobody examined")
    }

    func testTheKeysAndTheRungNamesAreSpelledOnce() {
        XCTAssertEqual(WindowCorner.selector, "_cornerRadius")
        XCTAssertEqual(WindowCorner.alsoPrinted, ["_topCornerRadius", "_bottomCornerRadius"])
        XCTAssertEqual(WindowCorner.logCategory, "window")
        XCTAssertEqual(WindowCorner.Rung.publicAPI.rawValue, "public")
        XCTAssertEqual(WindowCorner.Rung.windowSelector.rawValue, "window selector")
        XCTAssertEqual(WindowCorner.Rung.guess.rawValue, "guess")
        XCTAssertEqual(WindowCorner.Rung.none.rawValue, "none")
    }
}
