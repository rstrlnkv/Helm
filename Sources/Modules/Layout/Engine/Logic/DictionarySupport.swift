import Foundation

/// Which installed layouts macOS has no spelling dictionary for.
///
/// **This is the module's multilingual ceiling, and it was silent.** The
/// verdict needs two answers from the dictionary — the word as typed and the
/// word translated — and `SpellPort.isWord` returns `nil` when there is no
/// dictionary for a language, which is not «not a word» and must never be read
/// as one. `LayoutEngine.convert` returns outright on a nil, so on such a
/// layout «Fix as I type» does nothing at all: the switch is on, the badge is
/// green, and no word is ever fixed.
///
/// Measured on this Mac, `NSSpellChecker.availableLanguages` holds 44 entries
/// and does not include Kazakh, Belarusian, Georgian, Armenian, Serbian, Thai,
/// Japanese or Chinese. So «multilingual» is not a property Helm can grant
/// itself here — what it can do is stop pretending, and say which layout it
/// cannot decide for.
///
/// **The gesture is unaffected and that is the point.** `LayoutVerdict.decideForced`
/// asks no dictionary, so pressing the key still converts. The sentence the
/// page owes is «Helm cannot decide for itself on this layout», not «this does
/// not work here».
enum DictionarySupport {

    /// The installed layouts with no dictionary, in the order they are
    /// installed, or empty when every one of them has one.
    ///
    /// The whole installed set is asked rather than the active layout alone: a
    /// conversion is a pair, so a missing dictionary is a hole in every pair
    /// that includes it, whichever side is active at the moment.
    ///
    /// `hasDictionary` is asked once per layout and never per word — the real
    /// probe costs about 150 µs, which is fine where a page is drawn and is a
    /// third of the whole per-word decision on the tap's own thread.
    static func missing(installed: [String],
                        hasDictionary: (String) -> Bool) -> [String] {
        installed.filter { !hasDictionary($0) }
    }
}
