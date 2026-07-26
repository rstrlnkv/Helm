import Foundation

/// What the menu-bar indicator shows for an input source.
///
/// macOS writes the abbreviation in the language's own script — "РУ" for
/// Russian, "A" for ABC — and that is the habit to follow: somebody glancing at
/// the corner of the screen recognises the shape of their own alphabet faster
/// than they read two Latin letters.
public enum LanguageBadge {
    /// Abbreviations in the language's own script, where the script differs
    /// from Latin. Everything else is its language code in capitals, which is
    /// what the system does too.
    private static let native: [String: String] = [
        "ru": "РУ", "uk": "УК", "be": "БЕ", "bg": "БГ", "sr": "СР", "mk": "МК",
        "el": "ΕΛ", "he": "עב", "ar": "عر", "hy": "ՀԱ", "ka": "ႵႠ",
        "ja": "あ", "zh": "中", "ko": "한", "th": "ไทย",
    ]

    /// Latin layouts are told apart by country, not by language: "US" and "GB"
    /// are both English, and showing "EN" twice helps nobody.
    private static let latinByRegion: Set<String> = ["en", "de", "fr", "es", "it", "pt", "nl",
                                                     "pl", "cs", "sv", "no", "da", "fi", "tr"]

    /// The country a layout belongs to, by the layout's own name first.
    ///
    /// The language tag is not enough and never was: `ABC` names no region at
    /// all, and `US` and `British` are both English. Apple's layout ids do say
    /// which is which, so they are the first answer and the language tag is the
    /// fallback — otherwise half the indicators would be flags and half
    /// letters, which looks like a mistake rather than a choice.
    public static func region(sourceID: String, language: String) -> String? {
        let name = sourceID.split(separator: ".").last.map(String.init) ?? sourceID
        if let known = byLayout.first(where: { name.hasPrefix($0.key) })?.value { return known }
        return Locale(identifier: language).region?.identifier
    }

    /// Longest prefixes first is not needed here — every key is distinct at its
    /// start — but variants matter: "Russian-PC", "British-PC", "German-DIN"
    /// are the ones people actually have.
    private static let byLayout: [String: String] = [
        "ABC": "US", "US": "US", "Australian": "AU", "Canadian": "CA",
        "British": "GB", "Irish": "IE",
        "Russian": "RU", "Byelorussian": "BY", "Belarusian": "BY", "Ukrainian": "UA",
        "Bulgarian": "BG", "Serbian": "RS", "Macedonian": "MK", "Kazakh": "KZ",
        "German": "DE", "Austrian": "AT", "SwissGerman": "CH", "SwissFrench": "CH",
        "French": "FR", "Belgian": "BE", "Canadian-CSA": "CA",
        "Spanish": "ES", "LatinAmerican": "MX", "Italian": "IT",
        "Portuguese": "PT", "Brazilian": "BR", "Dutch": "NL",
        "Polish": "PL", "Czech": "CZ", "Slovak": "SK", "Hungarian": "HU",
        "Romanian": "RO", "Croatian": "HR", "Slovenian": "SI", "Estonian": "EE",
        "Latvian": "LV", "Lithuanian": "LT", "Finnish": "FI", "Swedish": "SE",
        "Norwegian": "NO", "Danish": "DK", "Icelandic": "IS",
        "Greek": "GR", "Turkish": "TR", "Hebrew": "IL", "Georgian": "GE",
        "Armenian": "AM", "Persian": "IR", "Thai": "TH", "Vietnamese": "VN",
        "Japanese": "JP", "Kotoeri": "JP", "Korean": "KR", "2-Set": "KR",
        "Pinyin": "CN", "Zhuyin": "TW", "Cangjie": "TW",
    ]

    public static func label(language: String, region: String?) -> String {
        let code = String(language.prefix(2)).lowercased()
        // Never nothing: a badge of no width is an indicator that is switched
        // on, invisible and impossible to click.
        guard !code.isEmpty else { return "?" }
        if let native = native[code] { return native }
        if latinByRegion.contains(code), let region, !region.isEmpty {
            return region.uppercased()
        }
        return code.uppercased()
    }

    /// The two regional-indicator characters that make a flag. Nil when there
    /// is no country to draw: a language is not a country, and guessing one is
    /// how a keyboard layout turns into a political statement.
    public static func emojiFlag(region: String?) -> String? {
        guard let region, region.count == 2,
              region.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let base: UInt32 = 0x1F1E6
        var flag = ""
        for character in region.uppercased().unicodeScalars {
            guard let scalar = UnicodeScalar(base + character.value - 65) else { return nil }
            flag.unicodeScalars.append(scalar)
        }
        return flag
    }

    /// The stripes of a drawn flag, top to bottom or left to right, as hex.
    ///
    /// A deliberately short table. A flag Helm cannot draw honestly is a flag
    /// it does not draw: the badge falls back to letters rather than inventing
    /// something close.
    public static func stripes(region: String?) -> (colors: [String], vertical: Bool)? {
        guard let region = region?.uppercased() else { return nil }
        switch region {
        case "RU": return (["FFFFFF", "0039A6", "D52B1E"], false)
        case "DE": return (["000000", "DD0000", "FFCE00"], false)
        case "FR": return (["002395", "FFFFFF", "ED2939"], true)
        case "IT": return (["008C45", "F4F5F0", "CD212A"], true)
        case "NL": return (["AE1C28", "FFFFFF", "21468B"], false)
        case "UA": return (["0057B7", "FFD700"], false)
        case "PL": return (["FFFFFF", "DC143C"], false)
        case "AT": return (["ED2939", "FFFFFF", "ED2939"], false)
        case "ES": return (["AA151B", "F1BF00", "AA151B"], false)
        case "BE": return (["000000", "FDDA24", "EF3340"], true)
        case "IE": return (["169B62", "FFFFFF", "FF883E"], true)
        case "SE": return (["006AA7", "FECC00"], false)
        default: return nil
        }
    }
}
