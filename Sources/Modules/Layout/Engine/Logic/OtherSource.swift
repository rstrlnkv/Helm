import Foundation

/// Which layout a word is converted into.
///
/// With two input sources installed there is one other and no question. With
/// three — English, Russian and Ukrainian is an ordinary Mac — the engine took
/// `installed().first(where: { $0 != current })`, which is whichever the system
/// lists first. On such a Mac the module converted into a layout the word has
/// nothing to do with and then switched the keyboard to it, which is a worse
/// outcome than doing nothing at all.
///
/// The rule: ask each candidate whether converting into it produces something
/// that makes sense, and take the first that says yes. Nothing fitting is not a
/// refusal — `Fix` exists to force a conversion the spell-checker would not
/// bless — so the fallback is the old order.
enum OtherSource {

    /// `makesSense` is asked at most once per candidate and stops at the first
    /// yes: it spell-checks a translation, and somebody is waiting on a key.
    static func pick(current: String,
                     installed: [String],
                     makesSense: (String) -> Bool) -> String? {
        let others = installed.filter { $0 != current }
        guard !others.isEmpty else { return nil }
        for candidate in others where makesSense(candidate) { return candidate }
        return others.first
    }
}
