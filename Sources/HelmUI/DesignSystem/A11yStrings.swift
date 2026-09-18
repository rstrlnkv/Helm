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
    /// The ⓘ beside a settings row's name (`HelmExplainer`). macOS's own word
    /// for this control, read out of its tables rather than translated: «More
    /// Info» is «Подробнее», «Weitere Infos», «En savoir plus», «Más
    /// información», «Mais informações», 「詳しい情報」, 「更多信息」.
    public static var moreInfo: String {
        L("More Info")
    }

    /// A segmented picker that narrows what a list is showing. Three modules
    /// have one and none of them labelled it, because on screen the segments
    /// say everything — "Installed / Updates / Search" needs no heading above
    /// it. Read aloud it was a tab group with no name.
    public static var whatToShow: String {
        L("What to show")
    }
    /// The search field (`HelmSearchField`), which had no name at all.
    ///
    /// **A placeholder is not a name**, and this one is the house rule read from
    /// the other end: «Search formulae and casks» disappears the moment there is
    /// a value, so the field was anonymous exactly while somebody was using it.
    /// AppKit does not promote it either — measured on a bare `NSSearchField`,
    /// `accessibilityLabel()` is nil with the field empty **and** nil with a word
    /// typed into it, so the label is ours to set.
    ///
    /// **The word is «Search» and nothing longer.** VoiceOver already says the
    /// role — "search field" — so a label spelling the role again reads as
    /// "search field search field". This is the same key the Homebrew segment
    /// draws, which is deliberate rather than an accident of the lookup: the
    /// English text *is* the key, so a second key reading «Search» is not
    /// representable, and the eight translations of that one word are the word
    /// macOS itself uses for this control in each of them.
    public static var searchField: String {
        L("Search")
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

    /// Calendar's own last item in this menu. The seven translations are its
    /// words, read out of `Calendar.app`'s `Localizable.loctable` under the key
    /// `Other…`: «Другой…» in Russian, where a translator reaching for the
    /// dictionary writes «Свой цвет…».
    ///
    /// **The English is deliberately longer than Calendar's.** Calendar draws
    /// «Other…» and this draws «Other colour…», because the English text is the
    /// key and `Other…` is already spoken for — the fourth answer to «for how
    /// long» in KeepAwake is the same macOS word for a *time*. Two of the eight
    /// then disagree with this one: Russian says «Другое…» of a time and
    /// «Другой…» of a colour, Portuguese «Outro…» against «Outra…», and
    /// German's non-breaking space before the ellipsis is in both. One key
    /// would have picked whichever of the two shipped first and been wrong in
    /// the other menu, in the two languages that draw a distinction English
    /// has lost.
    ///
    /// The wrong tables, both tried: `CalendarUI.framework` carries an `Other…`
    /// of its own, and it is a third item again — its Spanish is «Otra…» and
    /// its Portuguese «Outro…», neither of which agrees with *el color* or *a
    /// cor*. The colour *names* are in `CalendarFoundation.framework`; see
    /// `PaletteColor.label`.
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

public extension View {
    /// Speaks `text` once, each time it becomes a new non-nil value.
    ///
    /// For a verdict that grows into a banner without moving focus or changing
    /// the value of anything a VoiceOver reader is on — a removal report, a
    /// return's report — so it is not silent to them. Disk and Autopilot each
    /// spelled the same `onChange` around `HelmA11y.announce`; this is the one
    /// place it lives now.
    func helmAnnounces(_ text: String?) -> some View {
        onChange(of: text) { _, new in
            if let new { HelmA11y.announce(new) }
        }
    }
}
