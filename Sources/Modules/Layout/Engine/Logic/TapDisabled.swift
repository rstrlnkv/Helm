import CoreGraphics

/// What to do when macOS switches the tap off by itself.
///
/// A tap is not only stopped by its owner. The system disables one whose
/// callback it judged too slow (`tapDisabledByTimeout`) and one interrupted by
/// user input, and it revokes the whole thing when Accessibility is withdrawn
/// while Helm is running. In every case it announces this by delivering an
/// event *of that type* down the tap it is disabling — the one notification
/// there will be, arriving through the same callback as ordinary keys and
/// looking like nothing unless it is read for.
///
/// It was not read for. Both types fell through `deliver`'s switch into the
/// keycode default, produced no characters, and returned — so Layout stopped
/// converting words with nothing said anywhere and its own switch still
/// reading "on". A timeout needs no permission change to happen: the callback
/// asks the accessibility server for the frontmost app, and one slow app in
/// front is enough.
///
/// Here rather than in the port because it is a decision, and decisions in this
/// module are checkable without a keyboard.
public enum TapDisabled {

    public enum Response: Equatable {
        /// The grant is intact and the tap was disabled for being slow. Turning
        /// it back on is the documented repair.
        case enableItAgain
        /// The grant is gone. Re-enabling cannot succeed, and retrying against
        /// a permission somebody has just withdrawn is the module arguing with
        /// them — so the tap goes quiet and the module says it is not watching.
        case standDown
    }

    /// The two event types that mean "this tap is no longer live". They arrive
    /// whatever the tap asked to be sent, so neither is in the event mask.
    public static func disables(_ type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }

    public static func response(stillTrusted: Bool) -> Response {
        stillTrusted ? .enableItAgain : .standDown
    }
}
