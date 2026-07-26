import Carbon
import Foundation
import Module_Layout_Engine

/// One input source, as the indicator needs it.
struct InputSourceInfo {
    let id: String
    let name: String
    let badge: String
    let emojiFlag: String?
    let stripes: (colors: [String], vertical: Bool)?

    static func all() -> [InputSourceInfo] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else { return [] }
        return list
            .filter { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) != nil }
            .compactMap(make(from:))
    }

    static func current() -> InputSourceInfo {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let info = make(from: source) else {
            return InputSourceInfo(id: "", name: "", badge: "?", emojiFlag: nil, stripes: nil)
        }
        return info
    }

    private static func make(from source: TISInputSource) -> InputSourceInfo? {
        guard let id = string(source, kTISPropertyInputSourceID) else { return nil }
        let name = string(source, kTISPropertyLocalizedName) ?? id
        let language = languages(source).first ?? ""
        // The region comes from the tag when it carries one ("en-GB"), and
        // otherwise from the layout's own name, which is where "British" and
        // "U.S." live. No region means no flag, deliberately.
        let region = Locale(identifier: language).region?.identifier
        return InputSourceInfo(id: id, name: name,
                               badge: LanguageBadge.label(language: language, region: region),
                               emojiFlag: LanguageBadge.emojiFlag(region: region),
                               stripes: LanguageBadge.stripes(region: region))
    }

    private static func languages(_ source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
        else { return [] }
        return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]) ?? []
    }

    private static func string(_ source: TISInputSource, _ key: CFString!) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String)
    }
}
