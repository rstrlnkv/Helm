import Foundation
import SwiftUI

/// What the app says to a reader who is not looking at it: names for controls
/// that show only an icon, and — at the bottom — the one way it speaks unasked.
///
/// `.help()` fills `accessibilityHelp`, which is a hint — it does not name the
/// control. Without a label these read as "button" in the rotor and in the item
/// chooser, so a row with a remove button and an actions menu offered VoiceOver
/// two anonymous buttons and no way to tell them apart.
///
/// They live in `HelmUI` because the same controls appear across seven modules
/// and the host app, and a label that differs per module is the same defect in
/// a nicer costume. No count here: it was "four controls in four modules" when
/// it was written and is neither now, which is what a number in a comment does.
public enum HelmA11y {
    public static var moveUp: String {
        L("Move up")
    }
    public static var moveDown: String {
        L("Move down")
    }
    public static var remove: String {
        L("Remove")
    }
    public static var moreActions: String {
        L("More actions")
    }
    public static var showInFinder: String {
        L("Show in Finder")
    }

    /// A segmented picker that narrows what a list is showing. Three modules
    /// have one and none of them labelled it, because on screen the segments
    /// say everything — "Installed / Updates / Search" needs no heading above
    /// it. Read aloud it was a tab group with no name.
    public static var whatToShow: String {
        L("What to show")
    }
    /// Whether a disclosure is open. SwiftUI has no trait for it on macOS — the
    /// rotor gets `.isButton` and nothing else — so the state has to be said,
    /// and a control whose whole purpose is to open and close must say it.
    ///
    /// Read out of the system's own tables rather than translated: searching
    /// every `.loctable` macOS ships for the strings whose English is
    /// "expanded" / "collapsed" gives seven of the eight. Four of the first
    /// attempt's eight guesses were wrong — French says *condensé*, not
    /// *réduit*; Japanese says 折りたたまれています, not 閉じています; Russian
    /// spells it without the ё it is normally written with.
    ///
    /// Portuguese is the exception: no system table carries it, so it is a
    /// translation, and it is the only one here that is.
    public static func expanded(_ isExpanded: Bool) -> String {
        isExpanded
            ? L("expanded")
            : L("collapsed")
    }

    /// Calendar's own last item in this menu, and its own word: `Other…` in
    /// `CalendarUI.framework`'s table, «Другой…» in Russian — where a
    /// translator reaching for the dictionary writes «Свой цвет…».
    public static var otherColour: String { L("Other colour…") }

    /// Said once, out loud, for a change nobody pressed a button to cause.
    ///
    /// A sighted reader sees a notice grow into a page; VoiceOver does not,
    /// because nothing moved focus and nothing the reader is on has changed its
    /// value. The state that needs this is the one where the app stops doing what
    /// it was asked and the only account of it is a new field on screen.
    ///
    /// A function rather than an announcement inlined at the call site, so the
    /// one call is nameable and so a second surface cannot spell it differently.
    /// Callers hold it as a closure they can substitute in a test: an
    /// announcement leaves no trace anything can read back, so the alternative is
    /// a promise with no test under it.
    public static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
