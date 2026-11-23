import Foundation

/// Counted nouns. Interpolating a number in front of a fixed word produces
/// "Переместить 3 объектов" in Russian and "Move 1 items" in English; both
/// read as a bug to the person looking at the dialog.
///
/// The digits are grouped the way the language groups them (`HelmBytes.grouped`)
/// rather than interpolated raw: the Disk basket runs to five digits, and
/// "12345 файлов" in a confirmation dialog is read by counting the digits.
/// The word's form still follows the raw `count` — grouping changes how the
/// number is drawn, never which form it takes.
public enum Plural {
    /// "3 объекта", "1 item" — the generic noun Helm counts in confirmations.
    public static func items(_ count: Int, language: String) -> String {
        counted(count, language,
                ru: ("объект", "объекта", "объектов"),
                es: ("elemento", "elementos"), fr: ("élément", "éléments"),
                de: ("Objekt", "Objekte"), pt: ("item", "itens"), other: ("item", "items"),
                ja: { "\($0)項目" }, zh: { "\($0)个项目" })
    }

    /// "3 приложения", "1 app" — the uninstaller's status line, which counts
    /// applications rather than the files inside them.
    public static func apps(_ count: Int, language: String) -> String {
        counted(count, language,
                ru: ("приложение", "приложения", "приложений"),
                es: ("app", "apps"), fr: ("app", "apps"),
                de: ("App", "Apps"), pt: ("app", "apps"), other: ("app", "apps"),
                ja: { "アプリ\($0)件" }, zh: { "\($0)个应用" })
    }

    /// "3 файла", "1 file" — for the modules that count files rather than the
    /// generic objects `items` counts. A duplicate finder saying "2 файлов"
    /// reads as a bug in exactly the dialog that must not look buggy.
    public static func files(_ count: Int, language: String) -> String {
        counted(count, language,
                ru: ("файл", "файла", "файлов"),
                es: ("archivo", "archivos"), fr: ("fichier", "fichiers"),
                de: ("Datei", "Dateien"), pt: ("arquivo", "arquivos"), other: ("file", "files"),
                ja: { "\($0)個のファイル" }, zh: { "\($0)个文件" })
    }

    /// "30 дней", "1 day" — a rule's age conditions are written in these.
    public static func days(_ count: Int, language: String) -> String {
        counted(count, language,
                ru: ("день", "дня", "дней"),
                es: ("día", "días"), fr: ("jour", "jours"),
                de: ("Tag", "Tage"), pt: ("dia", "dias"), other: ("day", "days"),
                ja: { "\($0)日" }, zh: { "\($0)天" })
    }

    /// The one place a noun's word is chosen: the grouped digits, then the form
    /// `form` picks for the language. Japanese and Chinese write the digits
    /// into a phrase of their own and have no form to pick.
    private static func counted(_ count: Int, _ language: String,
                                ru: (String, String, String),
                                es: (String, String), fr: (String, String),
                                de: (String, String), pt: (String, String),
                                other: (String, String),
                                ja: (String) -> String, zh: (String) -> String) -> String {
        let digits = HelmBytes.grouped(count, language: language)
        func word(_ pair: (String, String)) -> String {
            digits + " " + (form(count, language: language) == .one ? pair.0 : pair.1)
        }
        switch language {
        case "ru": return digits + " " + russian(count, ru.0, ru.1, ru.2)
        case "es": return word(es)
        case "fr": return word(fr)
        case "de": return word(de)
        case "pt": return word(pt)
        case "ja": return ja(digits)
        case "zh": return zh(digits)
        default: return word(other)
        }
    }

    /// Which of a noun's three forms a language writes after `count`. Russian
    /// has all three; French counts 0 with the singular; every other language
    /// has two, so its middle form is the last one, and Japanese and Chinese
    /// write one form whatever this says. A catalog that cannot hold a plural
    /// without `%lld` (which groups digits and so changes bytes) holds one key
    /// per form, and the caller picks the key from this.
    public enum Form { case one, few, many }

    public static func form(_ count: Int, language: String) -> Form {
        switch language {
        case "ru":
            let magnitude = abs(count)
            if (11...14).contains(magnitude % 100) { return .many }
            switch magnitude % 10 {
            case 1: return .one
            case 2...4: return .few
            default: return .many
            }
        case "fr": return count <= 1 ? .one : .many
        default: return count == 1 ? .one : .many
        }
    }

    /// Russian picks its form from the last two digits: 11–14 always take the
    /// "many" form, whatever their final digit says (`form`).
    public static func russian(_ count: Int, _ one: String, _ few: String,
                               _ many: String) -> String {
        switch form(count, language: "ru") {
        case .one: return one
        case .few: return few
        case .many: return many
        }
    }
}
