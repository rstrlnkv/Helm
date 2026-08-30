import Foundation

/// The two- and three-letter words people actually type.
///
/// Short words used to be refused outright, and the reasoning was sound: a
/// spell checker's yes/no is nearly worthless at this length. Ask one whether
/// `yt` is a word and it may well say yes — checkers carry abbreviations,
/// proper nouns and stray entries, and at two letters almost every keystroke
/// pair lands on something. A verdict built on "is this a word" therefore
/// converts noise, and the cost is a rewritten word in the middle of somebody
/// else's sentence.
///
/// So short words are not decided by permission but by confidence. This list
/// is what the decision rests on: convert only when the *translated* form is
/// here and the typed form is not. It is deliberately a curated list of common
/// function words — prepositions, conjunctions, pronouns, particles — because
/// those are what short mislayouts are, and it is deliberately small, because
/// every entry is a word this module may now rewrite without asking a
/// dictionary.
///
/// Nothing here is longer than three characters. A long word would bypass the
/// spell checker entirely, which is the one thing the list must never do.
enum ShortWords {

    /// The one-letter words, which are the ones this list exists for most.
    ///
    /// **Russian's commonest words are one letter long, and the module refused
    /// every one of them.** `LayoutVerdict.minimumLength` was 2 under a comment
    /// saying «one character is a keystroke, not a word» — true of English,
    /// where only `a` and `I` qualify, and false of Russian, where `в`, `и`,
    /// `с`, `к`, `о`, `у`, `а` and `я` are prepositions, conjunctions and a
    /// pronoun that appear in almost every sentence. Type `d ` on a latin
    /// layout and it stayed `d`.
    ///
    /// By list rather than by dictionary, and more strictly than at two
    /// letters: a checker asked about a single character is worthless, and the
    /// latin side of these keys — `d`, `b`, `c`, `r`, `j`, `e`, `f`, `z` — is
    /// also what variable names, flags, initials and list markers look like.
    /// Terminals and password managers are refused before any of this runs;
    /// what remains is a chat about the language C, and the answer to that is
    /// «take `с` out of the list», which is one line.
    static let russianSingles: Set<String> = ["а", "в", "и", "к", "о", "с", "у", "я"]

    /// English's are exactly two, and `i` is here lowercased because the rule
    /// lowercases before it asks — `I` typed on a Russian layout is `Ш`, which
    /// is the case that started this.
    static let englishSingles: Set<String> = ["a", "i"]

    /// Common Russian words of two and three letters.
    static let russian: Set<String> = [
        // prepositions and conjunctions
        "на", "по", "за", "до", "из", "от", "во", "со", "об", "не", "ни", "но",
        "то", "та", "те", "уж", "же", "ли", "бы", "их", "ей", "ею", "им",
        "мы", "вы", "ты", "он", "да", "ко", "ну", "ах", "ох", "эх",
        // three letters
        "что", "как", "все", "они", "она", "оно", "его", "её", "нас", "вас",
        "нам", "вам", "них", "был", "три", "два", "сто", "год", "раз",
        "там", "тут", "так", "уже", "или", "под", "над", "при", "про", "без",
        "для", "еще", "ещё", "мой", "моя", "моё", "наш", "ваш",
        "кто", "где", "чем", "чей", "тот", "эта", "это", "эти", "тем", "том",
        "нет", "две", "дом", "пол", "имя", "час", "миг", "шаг", "сон", "рот",
        "нос", "рук", "ног", "лес", "мир", "вид", "род", "ряд", "бок", "низ",
        "всё", "вот", "сам", "оба", "обе", "лет", "дня", "сих", "чей", "чьи",
    ]

    /// Common English words of two and three letters.
    static let english: Set<String> = [
        "an", "as", "at", "be", "by", "do", "go", "he", "if", "in", "is", "it",
        "me", "my", "no", "of", "on", "or", "so", "to", "up", "us", "we", "am",
        "id", "ok", "hi",
        "the", "and", "for", "you", "are", "but", "not", "can", "has", "was",
        "its", "our", "his", "her", "out", "who", "all", "any", "new", "now",
        "old", "one", "two", "six", "ten", "top", "way", "day", "may", "say",
        "see", "get", "got", "put", "run", "set", "use", "yes", "how", "why",
        "did", "had", "him", "let", "man", "own", "too", "off", "far", "few",
        "big", "bad", "job", "key", "law", "lot", "map", "net", "war", "win",
    ]

    /// Every word in the list, both languages and both lengths.
    static var all: Set<String> {
        russian.union(english).union(russianSingles).union(englishSingles)
    }

    /// Whether this is a short word common enough to convert towards.
    ///
    /// One character is answered from `russianSingles`/`englishSingles` and
    /// never from the two- and three-letter lists, so a single letter cannot
    /// borrow confidence from a longer word that happens to start with it.
    static func isCommon(_ word: String) -> Bool {
        let lowered = word.lowercased()
        switch lowered.count {
        case 1: return russianSingles.contains(lowered) || englishSingles.contains(lowered)
        case 2, 3: return russian.contains(lowered) || english.contains(lowered)
        default: return false
        }
    }
}
