import Foundation
import SwiftUI

/// What the app says to a reader who is not looking at it: names for controls
/// that show only an icon, and — at the bottom — the one way it speaks unasked.
///
/// `.help()` fills `accessibilityHelp`, which is a hint and does not name the
/// control: without a label an icon-only control reads as "button", and two of
/// them on one row cannot be told apart.
///
/// They live in `HelmUI` because the same controls appear across modules and
/// the host, and a label that differs per module is the same defect.
public enum HelmA11y {
    public static var moveUp: String { L(.moveUp) }
    public static var moveDown: String { L(.moveDown) }
    public static var remove: String { L(.remove) }
    public static var moreActions: String { L(.moreActions) }
    public static var showInFinder: String { L(.showInFinder) }
    /// The ⓘ beside a settings row's name (`HelmExplainer`). macOS's own word
    /// for this control, read out of its tables rather than translated: «More
    /// Info» is «Подробнее», «Weitere Infos», «En savoir plus», «Más
    /// información», «Mais informações», 「詳しい情報」, 「更多信息」.
    static var moreInfo: String { L(.moreInfo) }

    /// The search field's name. The header row's field (`HelmHeaderSearch`) sets it.
    ///
    /// A placeholder is not a name: it disappears the moment there is a value,
    /// and AppKit does not promote it (`accessibilityLabel()` of a bare
    /// `NSSearchField` is nil, empty or not), so the label is ours to set.
    ///
    /// The word is «Search» and nothing longer: VoiceOver already says "search
    /// field", so a label spelling the role again reads it twice. One English
    /// text is one key (`testOneEnglishTextIsOneWordAcrossEveryCatalog`).
    static var searchField: String { L(.search) }

    /// Where a row stands in a column of buttons, which VoiceOver does not say by itself ("1 of 5"). The
    /// sidebar's rows read it as their value. `language` is explicit for the reason `HelmBasket` gives.
    ///
    /// Read out of the system's own table, as `expanded` and `collapsed` below are: the `%ld of %ld`
    /// entry of `SCRGeneral.loctable` in VoiceOver's ScreenReader.framework; zh is `zh_CN`, pt is `pt_BR`.
    /// The note variant below is not the system's `%@, %ld of %ld` (note first; ja `%1$@、%2$ld / %3$ld`):
    /// it keeps the position first, as the plain form does.
    static func position(_ n: Int, of m: Int,
                                language: AppLanguage = AppLanguage.current) -> String {
        L(.rowPosition(String(n), String(m)), language: language)
    }

    /// The same with a note after it — a row that cannot act says why. `note` arrives already localized.
    static func position(_ n: Int, of m: Int, after note: String,
                                language: AppLanguage = AppLanguage.current) -> String {
        L(.rowPositionAfter(String(n), String(m), note), language: language)
    }

    /// Whether a disclosure is open. SwiftUI has no trait for it on macOS, so
    /// the state has to be said. One pair for the whole app, so a person never
    /// hears one state under two names.
    ///
    /// Read out of the system's own tables rather than translated: the
    /// stand-alone `expanded` and `collapsed` entries of
    /// `/System/Library/PrivateFrameworks/ScreenReader.framework/Versions/A/Resources/SCRGeneral.loctable`,
    /// which VoiceOver itself draws from; zh is `zh_CN` and pt is `pt_BR`. The
    /// table's spellings are kept as they stand (French *condensé*, Russian
    /// without the ё). Japanese is the exception: its stand-alone `expanded` is
    /// a typography term, so it keeps 表示されました from `expanded. %@`.
    ///
    /// Lower case in every language: the value is read inside a sentence
    /// (`PanelChrome` joins it to a count) as often as alone.
    public static func expanded(_ isExpanded: Bool) -> String {
        isExpanded ? L(.expanded) : L(.collapsed)
    }

    /// Calendar's own last item in this menu. The seven translations are its
    /// words, read out of `Calendar.app`'s `Localizable.loctable` under the key
    /// `Other…`, not a translator's guess.
    ///
    /// The English is longer than Calendar's «Other…», because one English text
    /// is one word (`testOneEnglishTextIsOneWordAcrossEveryCatalog`) and
    /// `Other…` already names a time in Keep Awake. The two differ where a
    /// language has gender: Russian «Другое…» of a time and «Другой…» of a
    /// colour, Portuguese «Outro…» against «Outra…».
    ///
    /// Not `CalendarUI.framework`'s `Other…`, which is a third item whose
    /// Spanish and Portuguese agree with neither. The colour names are in
    /// `CalendarFoundation.framework`; see `PaletteColor.label`.
    public static var otherColour: String { L(.otherColour) }

    /// Said once, out loud, for a change nobody pressed a button to cause.
    ///
    /// A sighted reader sees a notice grow into a page; VoiceOver does not,
    /// because nothing moved focus and nothing the reader is on changed its
    /// value. One function, so a second surface cannot spell it differently.
    public static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

extension View {
    /// Speaks `text` once, each time it becomes a new non-nil value.
    ///
    /// For a verdict that grows into a banner without moving focus or changing
    /// the value of anything a VoiceOver reader is on, such as a removal report,
    /// so it is not silent to them.
    public func helmAnnounces(_ text: String?) -> some View {
        onChange(of: text) { _, new in
            if let new { HelmA11y.announce(new) }
        }
    }
}
