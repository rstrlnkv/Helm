import Carbon
import Foundation
import Module_Layout_Engine

/// One input source, as the indicator needs it.
struct InputSourceInfo {
    let id: String
    let name: String
    let badge: String
    let emojiFlag: String?
    let region: String?

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
            return InputSourceInfo(id: "", name: "", badge: "?", emojiFlag: nil, region: nil)
        }
        return info
    }

    private static func make(from source: TISInputSource) -> InputSourceInfo? {
        guard let id = string(source, kTISPropertyInputSourceID) else { return nil }
        let name = string(source, kTISPropertyLocalizedName) ?? id
        let language = languages(source).first ?? ""
        // From the layout's name first. `Locale("en").region` is nil — the tag
        // for a plain US layout names no country at all — so asking the tag
        // first left every flag style falling back to letters on an ordinary
        // Mac, which is to say the feature did not work at all.
        let region = LanguageBadge.region(sourceID: id, language: language)
        return InputSourceInfo(id: id, name: name,
                               badge: LanguageBadge.label(language: language, region: region),
                               emojiFlag: LanguageBadge.emojiFlag(region: region),
                               region: region)
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
