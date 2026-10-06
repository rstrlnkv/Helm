import CoreGraphics
import Foundation
import HelmLaunch
import HelmRuntime

/// **A window's corner radius, read in order, and which reading said so.** The
/// radius is what `ShellGeometry.cardRadius(windowRadius:)` is handed; a number
/// of Helm's own is never passed off as one the system gave, because `rung`
/// says where it came from and `logLine` says it in words.
///
/// The rungs, first answer wins:
/// 1. the public reading, handed in by the caller, when it is a number;
/// 2. the window's own `_cornerRadius`, a non-public selector, read through
///    `HelmReadNumber` so that an absent selector, a method of that name that is
///    not a getter of a floating-point number and an accessor that throws all
///    read as "did not answer" — only when it answers above
///    zero. Zero is what a borderless window answered on 27.2, and it is also
///    what a key that means nothing would answer; the two cannot be told apart,
///    so the ladder goes on to the guess, and a borderless window is therefore
///    cut from a guess rather than square;
/// 3. a guess by chrome (`guess(for:)`), called a guess in `rung` and in the line;
/// 4. a square corner, where nobody has stated a guess.
///
/// **What the guess rests on.** Each row carries its standing:
/// - macOS 26 with a toolbar, 26 pt: stated on the web, measured by nobody;
/// - macOS 26 without one, 16 pt: stated on the web, measured by nobody;
/// - macOS 27, 16 pt either way: measured on 27.2 only, in three kinds of window
///   off screen, and a window with a toolbar and one without had the same 16 pt
///   corner mask;
/// - any other system: nobody has stated one, so there is no guess.
///
/// That the window's `_cornerRadius` is answered by an `NSWindow` on macOS 26,
/// and that its number is the corner the window is drawn with, is measured by
/// nobody. On 27.2 it agreed with the public reading in three kinds of window.
/// The line `logLine` builds is how a machine that was not measured reports what
/// its window answered.
///
/// The window is an object for the main thread: the statics are `nonisolated`
/// so that they can be called from tests, not because another thread may call
/// them.
///
/// `ShellContentView` reads the corner in its `layout()` and writes the line.
/// Whoever writes the line owns one `Journal` for the window it is in, and
/// starts a new one when it moves to another window object.
nonisolated struct WindowCorner: Equatable {

    /// Which reading said the radius.
    nonisolated enum Rung: String {
        case publicAPI = "public"
        case windowSelector = "window selector"
        case guess = "guess"
        case none = "none"
    }

    /// What can be seen of the window's chrome through public calls: the key
    /// of the guess, nothing else.
    nonisolated struct Chrome: Equatable {
        let hasToolbar: Bool
        let systemMajor: Int
    }

    let radius: CGFloat
    let rung: Rung

    /// The window's own key; the only one the radius is ever read from, and the
    /// only file under `Sources` that spells it.
    nonisolated static let selector = "_cornerRadius"

    /// Printed in the line, never fed to the card.
    nonisolated static let alsoPrinted = ["_topCornerRadius", "_bottomCornerRadius"]

    /// The defaults key a person may have set. `ShellContentView` reads it when
    /// it writes a line and hands the value to `logLine` as `override`, which
    /// prints it.
    nonisolated static let overrideKey = "NSConvolutionOverride1"

    /// One ceiling for every reading. Not a design number: it keeps a huge
    /// value (1e300) away from a layer, with room above the largest corner
    /// anybody has named (26, stated on the web, measured by nobody).
    nonisolated static let believable: ClosedRange<CGFloat> = 0...64

    /// The log category `ShellContentView` writes the line under.
    nonisolated static let logCategory = "window"

    // MARK: - the guess

    /// **What somebody has stated the corner to be for this chrome;** nil where
    /// nobody has. See the type's comment for the standing of each row.
    nonisolated static func guess(for chrome: Chrome) -> CGFloat? {
        switch chrome.systemMajor {
        case 26: chrome.hasToolbar ? 26 : 16
        case 27: 16
        default: nil
        }
    }

    // MARK: - the rungs

    /// **The corner, by the rungs in the type's comment.** `publicReading` is nil
    /// where the system has no public reading, and until one has been reported.
    /// A nil `window` reads as an object that answers nothing. The object is a
    /// window and the call is for the main thread.
    ///
    /// A reading that is not-a-number or infinite means "this rung did not
    /// answer": the ladder goes down a rung, it does not land on a bound. A
    /// finite one is held in `believable`.
    nonisolated static func read(publicReading: CGFloat?, from window: NSObject?, chrome: Chrome) -> WindowCorner {
        if let reading = publicReading?.clampedIfFinite(to: believable) {
            return WindowCorner(radius: reading, rung: .publicAPI)
        }
        if let own = number(window, selector)?.clampedIfFinite(to: believable), own > 0 {
            return WindowCorner(radius: own, rung: .windowSelector)
        }
        if let guessed = guess(for: chrome) {
            return WindowCorner(radius: guessed, rung: .guess)
        }
        return WindowCorner(radius: 0, rung: .none)
    }

    /// The number `window` answers for `key`, as it came.
    private nonisolated static func number(_ window: NSObject?, _ key: String) -> CGFloat? {
        guard let window, let value = HelmReadNumber(window, key) else { return nil }
        return CGFloat(value.doubleValue)
    }

    // MARK: - the line

    /// **The line for the log, built from the same value the caller cuts with.**
    /// Where the rung is 1 or 2 the line prints three non-public numbers,
    /// `_cornerRadius` and the two in `alsoPrinted`; where it is a guess or a
    /// square it prints `_cornerRadius` only. Of these only `_cornerRadius` is
    /// used, and only on rung 2. Each is a number; `absent` where the object does
    /// not respond to the key; `-` where no floating-point number came of it: a
    /// method of another shape, which is not invoked, or a throw. That
    /// difference is what a machine nobody measured exists to tell. `override` is
    /// handed in and printed when it is a number, `-` for nil, and `not a number`
    /// for anything else: no foreign text enters the line. `publicReading` is what
    /// `read` was handed: a guess line says `no public reading` for nil and prints
    /// the number, `nan` and `inf` included, for one that was handed in and did not
    /// answer.
    ///
    /// The object is a window and the call is for the main thread. Only the
    /// question "does it respond" is asked in Swift, with `responds(to:)`; every
    /// value is read through `HelmReadNumber`.
    nonisolated static func logLine(_ corner: WindowCorner, publicReading: CGFloat?, chrome: Chrome,
                                    window: NSObject?, override: Any?, system: OperatingSystemVersion) -> String {
        let card = ShellGeometry.cardRadius(windowRadius: corner.radius)
        let toolbar = chrome.hasToolbar ? "toolbar yes" : "toolbar no"
        let shown: String
        switch override {
        case nil: shown = "-"
        case let number as NSNumber: shown = "\(number)"
        default: shown = "not a number"
        }
        let tail = "override \(shown); macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"

        switch corner.rung {
        case .publicAPI, .windowSelector:
            let keys = ([selector] + alsoPrinted).map { "\($0) \(printed(window, $0))" }.joined(separator: ", ")
            return "corner \(Double(corner.radius)) by \(corner.rung.rawValue); card \(Double(card)); \(toolbar); \(keys); \(tail)"
        case .guess:
            let with = chrome.hasToolbar ? "with a toolbar" : "without a toolbar"
            let standing = chrome.systemMajor == 27 ? "measured on 27.2" : "from the web, unmeasured"
            let heard = publicReading.map { "public reading \(Double($0))" } ?? "no public reading"
            return "corner not read: \(heard), \(selector) \(printed(window, selector)); "
                + "guessed \(Double(corner.radius)) for macOS \(chrome.systemMajor) \(with) (\(standing)); "
                + "card \(Double(card)); \(tail)"
        case .none:
            let with = chrome.hasToolbar ? "with a toolbar" : "without a toolbar"
            return "corner not read and nothing to guess from for macOS \(chrome.systemMajor) \(with); card square; "
                + "\(selector) \(printed(window, selector)); \(tail)"
        }
    }

    /// One key as the line prints it.
    private nonisolated static func printed(_ window: NSObject?, _ key: String) -> String {
        guard let window, window.responds(to: NSSelectorFromString(key)) else { return "absent" }
        guard let value = HelmReadNumber(window, key) else { return "-" }
        return "\(value.doubleValue)"
    }

    // MARK: - how often

    /// **Which lines have been written for one window object:** a line only
    /// when (radius, rung) differs from the last one written, and at most `cap`
    /// of them, the last saying that further changes are not logged. A growing
    /// record is bounded.
    nonisolated struct Journal {
        nonisolated static let cap = 8
        private var last: WindowCorner?
        private var written = 0

        nonisolated init() {}

        /// The line for `corner` if one is due, else nil; `make` runs only when
        /// one is.
        nonisolated mutating func line(for corner: WindowCorner, _ make: () -> String) -> String? {
            guard written < Self.cap, corner != last else { return nil }
            last = corner
            written += 1
            let line = make()
            return written == Self.cap ? line + "; further changes in this window are not logged" : line
        }
    }
}
