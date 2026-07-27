import Foundation

/// Russian written in Latin letters, and back.
///
/// One function rather than two, because the direction is not a setting: a
/// person who selected `привет` and pressed the key has already said which way
/// this goes. Any Cyrillic in the text means "out"; none means "back".
///
/// The table is the BGN/PCGN-flavoured spelling people actually type — `zh`,
/// `sh`, `shch`, `yu`, `ya` — rather than a standard nobody reads aloud. It
/// matters that it is the common one: this is used to name files and to write
/// addresses, where the point is that a Russian speaker recognises the result.
public enum Transliteration {

    /// Longest first: `shch` has to beat `sh`, which has to beat `s`, or `щ`
    /// comes back as `сх` and the round trip is lost.
    private static let pairs: [(String, String)] = [
        ("щ", "shch"), ("ш", "sh"), ("ч", "ch"), ("ж", "zh"), ("ю", "yu"),
        ("я", "ya"), ("ё", "yo"), ("э", "ee"), ("ц", "ts"), ("х", "kh"),
        ("а", "a"), ("б", "b"), ("в", "v"), ("г", "g"), ("д", "d"), ("е", "e"),
        ("з", "z"), ("и", "i"), ("й", "i"), ("к", "k"), ("л", "l"), ("м", "m"),
        ("н", "n"), ("о", "o"), ("п", "p"), ("р", "r"), ("с", "s"), ("т", "t"),
        ("у", "u"), ("ф", "f"), ("ы", "y"), ("ъ", "ie"), ("ь", ""),
    ]

    public static func convert(_ text: String) -> String {
        text.contains(where: isCyrillic) ? toLatin(text) : toCyrillic(text)
    }

    private static func isCyrillic(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x0400...0x04FF).contains(scalar.value)
    }

    // MARK: - Out

    private static func toLatin(_ text: String) -> String {
        var out = ""
        for character in text {
            let lower = String(character).lowercased()
            guard let latin = pairs.first(where: { $0.0 == lower })?.1 else {
                out.append(character)
                continue
            }
            out += carryCase(of: character, onto: latin, in: text)
        }
        return out
    }

    /// One Cyrillic capital can become four Latin letters, and `Щука` is
    /// `Shchuka` rather than `SHCHuka`. So a capital only shouts when its
    /// neighbours do.
    private static func carryCase(of character: Character, onto latin: String,
                                  in text: String) -> String {
        guard character.isUppercase, !latin.isEmpty else { return latin }
        return shouting(text) ? latin.uppercased() : latin.capitalized
    }

    /// Text with no lowercase letters in it at all.
    private static func shouting(_ text: String) -> Bool {
        !text.contains { $0.isLowercase }
    }

    // MARK: - Back

    private static func toCyrillic(_ text: String) -> String {
        // Sorted long-first so the greedy walk cannot take `s` out of `shch`.
        let table = pairs.filter { !$0.1.isEmpty }
            .sorted { $0.1.count > $1.1.count }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            var matched = false
            for (cyrillic, latin) in table {
                guard let end = text.index(index, offsetBy: latin.count,
                                           limitedBy: text.endIndex),
                      text[index..<end].lowercased() == latin
                else { continue }
                let capital = text[index].isUppercase
                out += capital ? cyrillic.uppercased() : cyrillic
                index = end
                matched = true
                break
            }
            if !matched {
                out.append(text[index])
                index = text.index(after: index)
            }
        }
        return out
    }
}

/// The case of a selection, walked in a cycle rather than toggled.
///
/// A toggle needs an opposite, and `Hello World` has none — it is neither upper
/// nor lower, and guessing produces whichever the author did not want. Three
/// states in a fixed order means the key is pressed until the text is right,
/// which is what people do with this feature anyway.
public enum CaseCycle {

    /// Nil when there is no case to change. A replacement is an edit, and an
    /// edit that changes nothing still clears the undo stack of the app it
    /// happened in — so a selection of digits is left alone rather than
    /// rewritten with itself.
    public static func apply(_ text: String) -> String? {
        guard text.contains(where: \.isLetter) else { return nil }
        return next(text)
    }

    static func next(_ text: String) -> String {
        if text == text.lowercased() { return text.uppercased() }
        if text == text.uppercased() { return titled(text) }
        if text == titled(text) { return text.lowercased() }
        // Anything else — `heLLo` — is not a state the cycle has, so it enters
        // at the top rather than being left where it is.
        return text.uppercased()
    }

    /// Every word's first letter, and only that: `localizedCapitalized` also
    /// lowercases the rest, which is what is wanted here, but it is
    /// locale-dependent and this runs on text in two alphabets at once.
    private static func titled(_ text: String) -> String {
        var out = ""
        var atWordStart = true
        for character in text {
            if character.isLetter {
                out += atWordStart ? String(character).uppercased()
                                   : String(character).lowercased()
                atWordStart = false
            } else {
                out.append(character)
                atWordStart = true
            }
        }
        return out
    }
}
