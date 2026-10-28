import CoreGraphics
import Foundation
import HelmLaunch
import HelmRuntime

/// **A window's corner radius on macOS 26, read in order, and which reading said
/// so.** On macOS 27 nobody reads it: the corner is `HelmRadius.window`, measured
/// on that system, and `ShellContentView` does not come here. The radius is what
/// `ShellGeometry.cardRadius(windowRadius:)` is handed; a number of Helm's own is
/// never passed off as one the system gave, because `rung` says where it came
/// from and `logLine` says it in words.
///
/// The rungs, first answer wins:
/// 1. the window's own `_cornerRadius`, a non-public selector, read through
///    `HelmReadNumber` so that an absent selector, a method of that name that is
///    not a getter of a floating-point number and an accessor that throws all
///    read as "did not answer" — only when it answers above zero. Zero is what a
///    borderless window answered on 27.2, and it is also what a key that means
///    nothing would answer; the two cannot be told apart, so the ladder goes on
///    to the guess;
/// 2. a guess by system (`guess(systemMajor:)`), called a guess in `rung` and in
///    the line;
/// 3. a square corner, where nobody has stated a guess.
///
/// **What the guess rests on.** macOS 26, 16 pt, for a window with no toolbar,
/// which the settings window is now: stated on the web, measured by nobody. Any other
/// system: nobody has stated one, so there is no guess.
///
/// That the window's `_cornerRadius` is answered by an `NSWindow` on macOS 26,
/// and that its number is the corner the window is drawn with, is measured by
/// nobody; there is no macOS 26 machine here. On 27.2 it agreed with the system's
/// own reading in three kinds of window. The line `logLine` builds is how a
/// machine that was not measured reports what its window answered.
///
/// `ShellContentView` reads the corner in its `layout()` on macOS 26 and writes
/// the line. Whoever writes the line owns one `Journal` for the window it is in,
/// and starts a new one when it moves to another window object.
nonisolated struct WindowCorner: Equatable {

    /// Which reading said the radius.
    nonisolated enum Rung: String {
        case windowSelector = "window selector"
        case guess = "guess"
        case none = "none"
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
    /// anybody has named for a window (26, stated on the web, measured by nobody).
    nonisolated static let believable: ClosedRange<CGFloat> = 0...64

    /// The log category `ShellContentView` writes the line under.
    nonisolated static let logCategory = "window"

    // MARK: - the guess

    /// **What somebody has stated the corner to be on this system;** nil where
    /// nobody has. See the type's comment for the standing of the one row.
    nonisolated static func guess(systemMajor: Int) -> CGFloat? {
        systemMajor == 26 ? 16 : nil
    }

    // MARK: - the rungs

    /// **The corner, by the rungs in the type's comment.** A nil `window` reads as
    /// an object that answers nothing. The object is a window and the call is for
    /// the main thread.
    ///
    /// A reading that is not-a-number or infinite means "this rung did not
    /// answer": the ladder goes down a rung, it does not land on a bound. A
    /// finite one is held in `believable`.
    nonisolated static func read(from window: NSObject?, systemMajor: Int) -> WindowCorner {
        if let own = number(window, selector)?.clampedIfFinite(to: believable), own > 0 {
            return WindowCorner(radius: own, rung: .windowSelector)
        }
        if let guessed = guess(systemMajor: systemMajor) {
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
    /// Where the rung is the window's own the line prints three non-public numbers,
    /// `_cornerRadius` and the two in `alsoPrinted`; where it is a guess or a
    /// square it prints `_cornerRadius` only. Of these only `_cornerRadius` is
    /// used, and only on that rung. Each is a number; `absent` where the object does
    /// not respond to the key; `-` where no floating-point number came of it: a
    /// method of another shape, which is not invoked, or a throw. That
    /// difference is what a machine nobody measured exists to tell. `override` is
    /// handed in and printed when it is a number, `-` for nil, and `not a number`
    /// for anything else: no foreign text enters the line.
    ///
    /// The object is a window and the call is for the main thread. Only the
    /// question "does it respond" is asked in Swift, with `responds(to:)`; every
    /// value is read through `HelmReadNumber`.
    nonisolated static func logLine(_ corner: WindowCorner, window: NSObject?, override: Any?,
                                    system: OperatingSystemVersion) -> String {
        let card = ShellGeometry.cardRadius(windowRadius: corner.radius)
        let shown: String
        switch override {
        case nil: shown = "-"
        case let number as NSNumber: shown = "\(number)"
        default: shown = "not a number"
        }
        let tail = "override \(shown); macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"

        switch corner.rung {
        case .windowSelector:
            let keys = ([selector] + alsoPrinted).map { "\($0) \(printed(window, $0))" }.joined(separator: ", ")
            return "corner \(Double(corner.radius)) by \(corner.rung.rawValue); card \(Double(card)); \(keys); \(tail)"
        case .guess:
            return "corner not read: \(selector) \(printed(window, selector)); "
                + "guessed \(Double(corner.radius)) for macOS \(system.majorVersion) (from the web, unmeasured); "
                + "card \(Double(card)); \(tail)"
        case .none:
            return "corner not read and nothing to guess from for macOS \(system.majorVersion); card square; "
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
