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
public enum ShortWords {

    /// Common Russian words of two and three letters.
    public static let russian: Set<String> = [
        // prepositions and conjunctions
        "на", "по", "за", "до", "из", "от", "во", "со", "об", "не", "ни", "но",
        "то", "та", "те", "уж", "же", "ли", "бы", "их", "ей", "ею", "им",
        "мы", "вы", "он", "да", "ко",
        // three letters
        "что", "как", "все", "они", "она", "оно", "его", "её", "нас", "вас",
        "нам", "вам", "них", "был", "три", "два", "сто", "год", "раз",
        "там", "тут", "так", "уже", "или", "под", "над", "при", "про", "без",
        "для", "еще", "ещё", "мой", "моя", "моё", "наш", "ваш",
        "кто", "где", "чем", "чей", "тот", "эта", "это", "эти", "тем", "том",
        "нет", "две", "дом", "пол", "имя", "час", "миг", "шаг", "сон", "рот",
        "нос", "рук", "ног", "лес", "мир", "вид", "род", "ряд", "бок", "низ",
    ]

    /// Common English words of two and three letters.
    public static let english: Set<String> = [
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

    /// Every word in the list, both languages.
    public static var all: Set<String> { russian.union(english) }

    /// Whether this is a short word common enough to convert towards.
    public static func isCommon(_ word: String) -> Bool {
        let lowered = word.lowercased()
        guard lowered.count >= 2, lowered.count <= 3 else { return false }
        return russian.contains(lowered) || english.contains(lowered)
    }
}
