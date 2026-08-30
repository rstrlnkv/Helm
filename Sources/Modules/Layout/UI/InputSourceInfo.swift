import Carbon
import Foundation
import Module_Layout_Engine

/// One input source, as the indicator needs it.
struct InputSourceInfo {
    let id: String
    let name: String
    let badge: String
    let region: String?

    static func all() -> [InputSourceInfo] {
        InputSources.keyboardLayouts().compactMap(make(from:))
    }

    /// macOS's own name for a source id, or the id when the source is gone.
    ///
    /// The system's spelling rather than one of ours — the same rule the pane
    /// names follow. A layout can be removed while Helm holds its id, and an id
    /// on screen is still better than an empty space.
    static func name(of id: String) -> String {
        guard let source = InputSources.source(id: id) else { return id }
        return InputSources.string(source, kTISPropertyLocalizedName) ?? id
    }

    static func current() -> InputSourceInfo {
        guard let source = InputSources.current(), let info = make(from: source) else {
            return InputSourceInfo(id: "", name: "", badge: "?", region: nil)
        }
        return info
    }

    private static func make(from source: TISInputSource) -> InputSourceInfo? {
        guard let id = InputSources.identifier(of: source) else { return nil }
        let name = InputSources.string(source, kTISPropertyLocalizedName) ?? id
        let language = languages(source).first ?? ""
        // From the layout's name first. `Locale("en").region` is nil — the tag
        // for a plain US layout names no country at all — so asking the tag
        // first left every flag style falling back to letters on an ordinary
        // Mac, which is to say the feature did not work at all.
        let region = LanguageBadge.region(sourceID: id, language: language)
        return InputSourceInfo(id: id, name: name,
                               badge: LanguageBadge.label(language: language, region: region),
                               region: region)
    }

    private static func languages(_ source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
        else { return [] }
        return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]) ?? []
    }
}
