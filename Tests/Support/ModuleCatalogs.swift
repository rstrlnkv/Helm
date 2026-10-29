// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmUI

/// The modules' own string catalogs, read as data: `Sources/Modules/<Name>/UI/Localizable.xcstrings`.
///
/// A catalog's symbols are internal to its target, so a test in the kit's target
/// cannot name one — and `Bundle.module` inside a test target is the test's own
/// bundle, never the module's. The file is what ships, and reading the file is
/// how the guards that read the kit's `.lproj` tables see a module's
/// words too (`StringsCoverageTests.testEveryCatalogSymbolCarriesTheEightLanguages`). Walking `Sources/Modules` rather
/// than naming modules means a catalog added by the next module is guarded the
/// day it lands.
public enum ModuleCatalogs {

    public struct Catalog: Sendable {
        public let module: String
        public let path: String
        /// symbol → language code → value.
        public let strings: [String: [String: String]]
        /// symbol → language code → the unit's `state`, so «needs review» is not read as a translation.
        public let states: [String: [String: String]]
    }

    public static func all() throws -> [Catalog] {
        let modules = RepoSource.root.appendingPathComponent("Sources/Modules")
        let names = try FileManager.default.contentsOfDirectory(atPath: modules.path).sorted()
        var out: [Catalog] = []
        for name in names {
            let relative = "Sources/Modules/\(name)/UI/Localizable.xcstrings"
            guard FileManager.default.fileExists(atPath:
                RepoSource.root.appendingPathComponent(relative).path) else { continue }
            out.append(try read(relative, module: name))
        }
        return out
    }

    static func read(_ relative: String, module: String) throws -> Catalog {
        let data = try Data(contentsOf: RepoSource.root.appendingPathComponent(relative))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: [String: Any]]
        else { throw RepoSource.Failure("\(relative) is not a string catalog") }
        var values: [String: [String: String]] = [:]
        var states: [String: [String: String]] = [:]
        for (symbol, entry) in strings {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for (code, localization) in localizations {
                let unit = localization["stringUnit"] as? [String: String] ?? [:]
                values[symbol, default: [:]][code] = unit["value"] ?? ""
                states[symbol, default: [:]][code] = unit["state"] ?? ""
            }
        }
        return Catalog(module: module, path: relative, strings: values, states: states)
    }

    /// Every catalog's values for one language, **keyed by the English value** — the shape the kit's
    /// `.lproj` tables have, so a guard that judges values and prints a key reads both with one loop.
    /// A symbol with no localization in the language is left out; a missing language is
    /// `StringsCoverageTests.testEveryCatalogSymbolCarriesTheEightLanguages`' to report, not this table's.
    public static func tableByEnglish(for language: AppLanguage) throws -> [String: String] {
        var out: [String: String] = [:]
        for catalog in try all() {
            for (symbol, values) in catalog.strings {
                guard let english = values["en"], let value = values[language.rawValue] else { continue }
                if out[english] != nil {
                    throw RepoSource.Failure("\(catalog.path): \(symbol) repeats the English «\(english)» — "
                                            + "one English text means one thing")
                }
                out[english] = value
            }
        }
        return out
    }
}
