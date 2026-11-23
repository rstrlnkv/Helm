import Foundation

/// A GitHub release as the API spells it, for the update tests.
///
/// The update tests of this target each wrote this by hand with the values their
/// test needed. Every field a caller may differ in is a parameter; `prerelease` and `draft`
/// are left out of the object unless given, because a response without them is
/// a case of its own.
enum ReleaseJSON {

    /// One release object.
    static func release(tag: String,
                        page: String = "https://example.com/r",
                        body: String = "",
                        prerelease: Bool? = nil,
                        draft: Bool? = nil,
                        assets: [(name: String, url: String)] = []) -> String {
        var fields = [#""tag_name":"\#(tag)""#, #""html_url":"\#(page)""#, #""body":"\#(body)""#]
        if let prerelease { fields.append(#""prerelease":\#(prerelease)"#) }
        if let draft { fields.append(#""draft":\#(draft)"#) }
        let assetsJSON = assets.map { #"{"name":"\#($0.name)","browser_download_url":"\#($0.url)"}"# }
            .joined(separator: ",")
        fields.append(#""assets":[\#(assetsJSON)]"#)
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// The same, as the bytes a response carries.
    static func releaseData(tag: String,
                            page: String = "https://example.com/r",
                            body: String = "",
                            prerelease: Bool? = nil,
                            draft: Bool? = nil,
                            assets: [(name: String, url: String)] = []) -> Data {
        Data(release(tag: tag, page: page, body: body, prerelease: prerelease,
                     draft: draft, assets: assets).utf8)
    }

    /// The releases list endpoint's body: each element a `release(...)`.
    static func list(_ releases: [String]) -> Data {
        Data(("[" + releases.joined(separator: ",") + "]").utf8)
    }
}
