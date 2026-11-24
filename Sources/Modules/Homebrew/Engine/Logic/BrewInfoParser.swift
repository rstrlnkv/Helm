import Foundation

/// Reads the document `brew info --json=v2` answers about one package.
///
/// The document has ninety-odd keys, four of which differ in kind between a
/// formula and a cask: the install facts (`installed` array of objects versus
/// `installed`/`installed_time` scalars), the name (`name` string versus a
/// `name` *array* that is a display list, not an identity — a cask's identity
/// is `token`), the current version (`versions.stable` inside an object versus
/// a flat `version`), and the licence (present for a formula, absent from a
/// cask's document altogether). A synthesized `Decodable` cannot tell "a key
/// was renamed upstream" from "Homebrew has nothing to say", so it is read by
/// hand through `JSONSerialization`, as `InstallCounts.parse` is. This parser
/// returns `nil` only when the document is not the one it was promised.
enum BrewInfoParser {
    /// nil when the bytes are not a document this parser recognises: not
    /// JSON, not an object, missing the `formulae`/`casks` key entirely, or
    /// naming no entry of the requested kind at all — an empty array is a
    /// name brew could not resolve, not a package with no facts, and a
    /// formula document read as a cask (or the reverse) is not an answer
    /// about the kind that was asked for. An entry whose name is blank is
    /// refused with them: a package with no identity is nothing to act on, and
    /// an empty name appended to a path names the whole directory.
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
            // A cask's `name` is a display list; `token` is its identity.
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

        // A formula's current version is `versions.stable`, a cask's a flat
        // `version`: the only version a package that is not installed has.
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
        // this package here" on `installedVersion` (`PackageFacts.of`), so a
        // date read from a record whose version is unreadable would describe a
        // package reported as not installed.
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
    /// the two apart.** `PackageInfo` carries optionals so "brew had nothing to
    /// say" is a shape the page cannot draw; a `""` walks past that (a licence
    /// row with nothing under it, "use  instead"). So blankness is collapsed
    /// here, at the one place the document is read, not in every view.
    ///
    /// Whitespace counts as blank. The original string is carried, not the
    /// trimmed one: `caveats` is the tool's own text, often a path or a command
    /// somebody has to copy.
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
