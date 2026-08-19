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
        let digits = HelmBytes.grouped(count, language: language)
        switch language {
        case "ru": return digits + " " + russian(count, "объект", "объекта", "объектов")
        case "es": return digits + " " + (count == 1 ? "elemento" : "elementos")
        case "fr": return digits + " " + (count <= 1 ? "élément" : "éléments")
        case "de": return digits + " " + (count == 1 ? "Objekt" : "Objekte")
        case "pt": return digits + " " + (count == 1 ? "item" : "itens")
        case "ja": return "\(digits)項目"
        case "zh": return "\(digits)个项目"
        default: return digits + " " + (count == 1 ? "item" : "items")
        }
    }

    /// "3 записи", "1 entry" — the lines of `/etc/hosts` the panel tile counts.
    ///
    /// An inline table rather than eight `.strings` keys, for the reason every
    /// counted noun in this file has one: the interpolation runs before the
    /// lookup would, so there is no English key to be the key.
    public static func entries(_ count: Int, language: String) -> String {
        let digits = HelmBytes.grouped(count, language: language)
        switch language {
        case "ru": return digits + " " + russian(count, "запись", "записи", "записей")
        case "es": return digits + " " + (count == 1 ? "entrada" : "entradas")
        case "fr": return digits + " " + (count <= 1 ? "entrée" : "entrées")
        case "de": return digits + " " + (count == 1 ? "Eintrag" : "Einträge")
        case "pt": return digits + " " + (count == 1 ? "entrada" : "entradas")
        case "ja": return "\(digits)件"
        case "zh": return "\(digits)条"
        default: return digits + " " + (count == 1 ? "entry" : "entries")
        }
    }

    /// "3 ключа", "1 key" — what the tile says about `~/.ssh`.
    public static func keys(_ count: Int, language: String) -> String {
        let digits = HelmBytes.grouped(count, language: language)
        switch language {
        case "ru": return digits + " " + russian(count, "ключ", "ключа", "ключей")
        case "es": return digits + " " + (count == 1 ? "clave" : "claves")
        case "fr": return digits + " " + (count <= 1 ? "clé" : "clés")
        case "de": return digits + " " + (count == 1 ? "Schlüssel" : "Schlüssel")
        case "pt": return digits + " " + (count == 1 ? "chave" : "chaves")
        case "ja": return "\(digits)個の鍵"
        case "zh": return "\(digits)个密钥"
        default: return digits + " " + (count == 1 ? "key" : "keys")
        }
    }

    /// "3 приложения", "1 app" — the uninstaller's status line, which counts
    /// applications rather than the files inside them.
    public static func apps(_ count: Int, language: String) -> String {
        let digits = HelmBytes.grouped(count, language: language)
        switch language {
        case "ru": return digits + " " + russian(count, "приложение", "приложения", "приложений")
        case "es": return digits + " " + (count == 1 ? "app" : "apps")
        case "fr": return digits + " " + (count <= 1 ? "app" : "apps")
        case "de": return digits + " " + (count == 1 ? "App" : "Apps")
        case "pt": return digits + " " + (count == 1 ? "app" : "apps")
        case "ja": return "アプリ\(digits)件"
        case "zh": return "\(digits)个应用"
        default: return digits + " " + (count == 1 ? "app" : "apps")
        }
    }

    /// "3 файла", "1 file" — for the modules that count files rather than the
    /// generic objects `items` counts. A duplicate finder saying "2 файлов"
    /// reads as a bug in exactly the dialog that must not look buggy.
    public static func files(_ count: Int, language: String) -> String {
        let digits = HelmBytes.grouped(count, language: language)
        switch language {
        case "ru": return digits + " " + russian(count, "файл", "файла", "файлов")
        case "es": return digits + " " + (count == 1 ? "archivo" : "archivos")
        case "fr": return digits + " " + (count <= 1 ? "fichier" : "fichiers")
        case "de": return digits + " " + (count == 1 ? "Datei" : "Dateien")
        case "pt": return digits + " " + (count == 1 ? "arquivo" : "arquivos")
        case "ja": return "\(digits)個のファイル"
        case "zh": return "\(digits)个文件"
        default: return digits + " " + (count == 1 ? "file" : "files")
        }
    }

    /// "3 правила", "1 rule" — the autopilot page counts these.
    public static func rules(_ count: Int, language: String) -> String {
        let digits = HelmBytes.grouped(count, language: language)
        switch language {
        case "ru": return digits + " " + russian(count, "правило", "правила", "правил")
        case "es": return digits + " " + (count == 1 ? "regla" : "reglas")
        case "fr": return digits + " " + (count <= 1 ? "règle" : "règles")
        case "de": return digits + " " + (count == 1 ? "Regel" : "Regeln")
        case "pt": return digits + " " + (count == 1 ? "regra" : "regras")
        case "ja": return "\(digits)個のルール"
        case "zh": return "\(digits)条规则"
        default: return digits + " " + (count == 1 ? "rule" : "rules")
        }
    }

    /// "30 дней", "1 day" — a rule's age conditions are written in these.
    public static func days(_ count: Int, language: String) -> String {
        let digits = HelmBytes.grouped(count, language: language)
        switch language {
        case "ru": return digits + " " + russian(count, "день", "дня", "дней")
        case "es": return digits + " " + (count == 1 ? "día" : "días")
        case "fr": return digits + " " + (count <= 1 ? "jour" : "jours")
        case "de": return digits + " " + (count == 1 ? "Tag" : "Tage")
        case "pt": return digits + " " + (count == 1 ? "dia" : "dias")
        case "ja": return "\(digits)日"
        case "zh": return "\(digits)天"
        default: return digits + " " + (count == 1 ? "day" : "days")
        }
    }

    /// Russian picks its form from the last two digits: 11–14 always take the
    /// "many" form, whatever their final digit says.
    public static func russian(_ count: Int, _ one: String, _ few: String,
                               _ many: String) -> String {
        let magnitude = abs(count)
        if (11...14).contains(magnitude % 100) { return many }
        switch magnitude % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
