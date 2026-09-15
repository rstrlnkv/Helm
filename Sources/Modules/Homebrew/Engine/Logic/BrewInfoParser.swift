import Foundation

/// Reads the document `brew info --json=v2` answers about one package.
///
/// The document has ninety-odd keys, three of which differ in kind between a
/// formula and a cask: the install facts (`installed` array of objects versus
/// `installed`/`installed_time` scalars), the name (`name` string versus a
/// `name` *array* that is a display list, not an identity — a cask's identity
/// is `token`), and the licence (present for a formula, absent from a cask's
/// document altogether). A synthesized `Decodable` over a struct that only
/// names the fields this module cares about cannot tell "a key was renamed
/// upstream" from "Homebrew has nothing to say about this field" — both come
/// back the same way, as a value quietly missing — so a renamed key would
/// hand callers a `PackageInfo` full of nils indistinguishable from a real,
/// empty answer. Reading through `JSONSerialization` and by hand, as
/// `InstallCounts.parse` does in this same module, keeps those two outcomes
/// apart: this parser returns `nil` only when the document itself is not the
/// one it was promised.
enum BrewInfoParser {
    /// nil when the bytes are not a document this parser recognises: not
    /// JSON, not an object, missing the `formulae`/`casks` key entirely, or
    /// naming no entry of the requested kind at all — an empty array is a
    /// name brew could not resolve, not a package with no facts, and a
    /// formula document read as a cask (or the reverse) is not an answer
    /// about the kind that was asked for.
    static func parse(_ data: Data, isCask: Bool) -> PackageInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let key = isCask ? "casks" : "formulae"
        guard let entries = root[key] as? [[String: Any]], let entry = entries.first else {
            return nil
        }

        let name: String?
        if isCask {
            // A cask's `name` field is a display list ("Claude Code"), not
            // its identity — `token` is what every other command names it
            // by, and what the rest of this app keys it under.
            name = entry["token"] as? String
        } else {
            name = entry["name"] as? String
        }
        guard let name else { return nil }

        let deprecated = entry["deprecated"] as? Bool ?? false
        // Read only when the package is actually deprecated: a stray
        // `deprecation_reason` on an entry that isn't would say something
        // Homebrew itself is not claiming.
        let deprecationReason = deprecated ? entry["deprecation_reason"] as? String : nil
        let replacement = deprecated
            ? ((entry["deprecation_replacement_formula"] as? String)
                ?? (entry["deprecation_replacement_cask"] as? String))
            : nil

        var installedVersion: String?
        var installedAt: Date?
        var installedOnRequest: Bool?
        if isCask {
            // A cask's install facts are top-level scalars — there is no
            // array of past installs to look inside, and no record of who
            // asked for it.
            installedVersion = entry["installed"] as? String
            if let epoch = entry["installed_time"] as? Double {
                installedAt = Date(timeIntervalSince1970: epoch)
            }
        } else if let installs = entry["installed"] as? [[String: Any]], let first = installs.first {
            installedVersion = first["version"] as? String
            if let epoch = first["time"] as? Double {
                installedAt = Date(timeIntervalSince1970: epoch)
            }
            installedOnRequest = first["installed_on_request"] as? Bool
        }

        return PackageInfo(
            name: name,
            isCask: isCask,
            desc: entry["desc"] as? String,
            homepage: entry["homepage"] as? String,
            license: isCask ? nil : entry["license"] as? String,
            tap: entry["tap"] as? String,
            installedVersion: installedVersion,
            installedAt: installedAt,
            installedOnRequest: installedOnRequest,
            deprecationReason: deprecationReason,
            replacement: replacement,
            siblings: entry["versioned_formulae"] as? [String] ?? [],
            dependencies: entry["dependencies"] as? [String] ?? [],
            caveats: entry["caveats"] as? String
        )
    }
}
