import Foundation

/// Reads the document `brew info --json=v2` answers about one package.
///
/// The document has ninety-odd keys, four of which differ in kind between a
/// formula and a cask: the install facts (`installed` array of objects versus
/// `installed`/`installed_time` scalars), the name (`name` string versus a
/// `name` *array* that is a display list, not an identity — a cask's identity
/// is `token`), the current version (`versions.stable` inside an object versus
/// a flat `version`), and the licence (present for a formula, absent from a
/// cask's document altogether). A synthesized `Decodable` over a struct that only
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
    /// about the kind that was asked for. An entry whose name is blank is
    /// refused with them: a package with no identity is nothing the rest of
    /// this module can act on, and an empty display name has claimed a whole
    /// directory elsewhere in this app before.
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
            name = text(entry["token"])
        } else {
            name = text(entry["name"])
        }
        guard let name else { return nil }

        let deprecated = entry["deprecated"] as? Bool ?? false
        // Read only when the package is actually deprecated: a stray
        // `deprecation_reason` on an entry that isn't would say something
        // Homebrew itself is not claiming.
        let deprecationReason = deprecated ? text(entry["deprecation_reason"]) : nil
        let replacement = deprecated
            ? (text(entry["deprecation_replacement_formula"])
                ?? text(entry["deprecation_replacement_cask"]))
            : nil

        // The fourth shape the two documents disagree about: a formula's
        // current version is `versions.stable` — an object, beside `head` and a
        // `bottle` flag — while a cask carries a flat `version`. Read here
        // rather than left out because it is the *only* version a package that
        // is not installed has anywhere in this module: `brew search` answers
        // with names alone.
        let latestVersion: String?
        if isCask {
            latestVersion = text(entry["version"])
        } else {
            latestVersion = text((entry["versions"] as? [String: Any])?["stable"])
        }

        var installedVersion: String?
        var installedAt: Date?
        var installedOnRequest: Bool?
        // **The version is the fact the rest hang off.** Every reader keys "is
        // this package here" on `installedVersion` (`PackageFacts.of` decides the
        // whole tile set on it), so a date or a "came as a dependency" read from
        // a record whose version is unreadable is a fact about a package
        // reported as not installed — one screen with two accounts of one
        // package, which is the shape this module's other defects took.
        if isCask {
            // A cask's install facts are top-level scalars — there is no
            // array of past installs to look inside, and no record of who
            // asked for it.
            if let version = text(entry["installed"]) {
                installedVersion = version
                if let epoch = entry["installed_time"] as? Double {
                    installedAt = Date(timeIntervalSince1970: epoch)
                }
            }
        } else if let installs = entry["installed"] as? [[String: Any]], let first = installs.first,
                  let version = text(first["version"]) {
            installedVersion = version
            if let epoch = first["time"] as? Double {
                installedAt = Date(timeIntervalSince1970: epoch)
            }
            installedOnRequest = first["installed_on_request"] as? Bool
        }

        return PackageInfo(
            name: name,
            isCask: isCask,
            desc: text(entry["desc"]),
            homepage: text(entry["homepage"]),
            license: isCask ? nil : text(entry["license"]),
            tap: text(entry["tap"]),
            latestVersion: latestVersion,
            installedVersion: installedVersion,
            installedAt: installedAt,
            installedOnRequest: installedOnRequest,
            deprecationReason: deprecationReason,
            replacement: replacement,
            siblings: texts(entry["versioned_formulae"]),
            dependencies: texts(entry["dependencies"]),
            caveats: text(entry["caveats"])
        )
    }

    /// A value the document has something in, or nil.
    ///
    /// **An empty string is not an absent fact, and nothing downstream can tell
    /// the two apart.** `PackageInfo` carries optionals precisely so that "brew
    /// had nothing to say" is a shape the page cannot draw — and a `""` walks
    /// straight past that: `"license": ""` drew a licence tile with nothing
    /// under it, which reads as Homebrew having been asked and having had no
    /// answer, and `"deprecation_replacement_formula": ""` drew "use  instead".
    /// So blankness is collapsed here, at the one place the document is read,
    /// rather than at each of the sites that draw one of these values — a check
    /// in every view is a check in no parser, and the next reader of a new field
    /// would have to know to add one.
    ///
    /// Whitespace counts as blank: one space is the same absence spelled less
    /// obviously. What is *carried* is the original string rather than the
    /// trimmed one — the only question asked here is whether the fact is there,
    /// and `caveats` is the tool's own text, usually a path or a command
    /// somebody has to copy, which this parser has no business re-spelling.
    private static func text(_ raw: Any?) -> String? {
        guard let value = raw as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// The same question of a list of names: a blank entry draws an empty pill
    /// in the dependency row and an empty gap in "other version lines".
    private static func texts(_ raw: Any?) -> [String] {
        (raw as? [String] ?? []).compactMap(text)
    }
}
