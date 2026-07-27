import Foundation

/// Counted nouns. Interpolating a number in front of a fixed word produces
/// "Переместить 3 объектов" in Russian and "Move 1 items" in English; both
/// read as a bug to the person looking at the dialog.
public enum Plural {
    /// "3 объекта", "1 item" — the generic noun Helm counts in confirmations.
    public static func items(_ count: Int, language: String) -> String {
        switch language {
        case "ru": return "\(count) " + russian(count, "объект", "объекта", "объектов")
        case "es": return "\(count) " + (count == 1 ? "elemento" : "elementos")
        case "fr": return "\(count) " + (count <= 1 ? "élément" : "éléments")
        case "de": return "\(count) " + (count == 1 ? "Objekt" : "Objekte")
        case "pt": return "\(count) " + (count == 1 ? "item" : "itens")
        case "ja": return "\(count)項目"
        case "zh": return "\(count)个项目"
        default: return "\(count) " + (count == 1 ? "item" : "items")
        }
    }

    /// "3 приложения", "1 app" — the uninstaller's status line, which counts
    /// applications rather than the files inside them.
    public static func apps(_ count: Int, language: String) -> String {
        switch language {
        case "ru": return "\(count) " + russian(count, "приложение", "приложения", "приложений")
        case "es": return "\(count) " + (count == 1 ? "app" : "apps")
        case "fr": return "\(count) " + (count <= 1 ? "app" : "apps")
        case "de": return "\(count) " + (count == 1 ? "App" : "Apps")
        case "pt": return "\(count) " + (count == 1 ? "app" : "apps")
        case "ja": return "アプリ\(count)件"
        case "zh": return "\(count)个应用"
        default: return "\(count) " + (count == 1 ? "app" : "apps")
        }
    }

    /// "3 файла", "1 file" — for the modules that count files rather than the
    /// generic objects `items` counts. A duplicate finder saying "2 файлов"
    /// reads as a bug in exactly the dialog that must not look buggy.
    public static func files(_ count: Int, language: String) -> String {
        switch language {
        case "ru": return "\(count) " + russian(count, "файл", "файла", "файлов")
        case "es": return "\(count) " + (count == 1 ? "archivo" : "archivos")
        case "fr": return "\(count) " + (count <= 1 ? "fichier" : "fichiers")
        case "de": return "\(count) " + (count == 1 ? "Datei" : "Dateien")
        case "pt": return "\(count) " + (count == 1 ? "arquivo" : "arquivos")
        case "ja": return "\(count)個のファイル"
        case "zh": return "\(count)个文件"
        default: return "\(count) " + (count == 1 ? "file" : "files")
        }
    }

    /// "3 правила", "1 rule" — the autopilot page counts these.
    public static func rules(_ count: Int, language: String) -> String {
        switch language {
        case "ru": return "\(count) " + russian(count, "правило", "правила", "правил")
        case "es": return "\(count) " + (count == 1 ? "regla" : "reglas")
        case "fr": return "\(count) " + (count <= 1 ? "règle" : "règles")
        case "de": return "\(count) " + (count == 1 ? "Regel" : "Regeln")
        case "pt": return "\(count) " + (count == 1 ? "regra" : "regras")
        case "ja": return "\(count)個のルール"
        case "zh": return "\(count)条规则"
        default: return "\(count) " + (count == 1 ? "rule" : "rules")
        }
    }

    /// "30 дней", "1 day" — a rule's age conditions are written in these.
    public static func days(_ count: Int, language: String) -> String {
        switch language {
        case "ru": return "\(count) " + russian(count, "день", "дня", "дней")
        case "es": return "\(count) " + (count == 1 ? "día" : "días")
        case "fr": return "\(count) " + (count <= 1 ? "jour" : "jours")
        case "de": return "\(count) " + (count == 1 ? "Tag" : "Tage")
        case "pt": return "\(count) " + (count == 1 ? "dia" : "dias")
        case "ja": return "\(count)日"
        case "zh": return "\(count)天"
        default: return "\(count) " + (count == 1 ? "day" : "days")
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
