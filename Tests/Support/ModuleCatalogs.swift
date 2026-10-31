// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmUI

/// Every string catalog Helm ships, read as data: the kit's `Sources/HelmUI/Localizable.xcstrings`,
/// each module's `Sources/Modules/<Name>/UI/Localizable.xcstrings`, and the host's
/// `Sources/HelmAppStrings/Localizable.xcstrings` and `Changelog.xcstrings`.
///
/// A catalog's symbols are internal to its target, so a test in another target cannot name one — and
/// `Bundle.module` inside a test target is the test's own bundle, never the catalog's owner's. The file
/// is what ships, and reading the file is how every string guard sees every word
/// (`StringsCoverageTests.testEveryCatalogSymbolCarriesTheEightLanguages`). Walking `Sources/Modules`
/// rather than naming modules means a catalog added by the next module is guarded the day it lands.
///
/// **The kit's catalog is not optional.** A module without a UI catalog is a module with no words of
/// its own, and is skipped; the kit without one would leave every guard reading the modules alone and
/// passing, so `all()` throws when `Sources/HelmUI/Localizable.xcstrings` is not there.
public enum ModuleCatalogs {

    public struct Catalog: Sendable {
        public let module: String
        public let path: String
        /// symbol → language code → value.
        public let strings: [String: [String: String]]
        /// symbol → language code → the unit's `state`, so «needs review» is not read as a translation.
        public let states: [String: [String: String]]

        public init(module: String, path: String, strings: [String: [String: String]],
                    states: [String: [String: String]]) {
            self.module = module
            self.path = path
            self.strings = strings
            self.states = states
        }

        /// A module's own catalog, as against the kit's and the host's.
        public var isModule: Bool { path.hasPrefix("Sources/Modules/") }
    }

    /// The kit's catalog: the words two parts draw, and the host's own controls.
    public static let kitPath = "Sources/HelmUI/Localizable.xcstrings"

    /// One value of one symbol in one language, with the English it translates.
    public struct Entry: Sendable {
        public let module: String
        public let symbol: String
        public let english: String
        public let value: String
        /// `Module.symbol`, the name a finding is printed under.
        public var name: String { "\(module).\(symbol)" }
    }

    /// Every symbol's value in `language`, one entry per symbol — nothing keyed by English, so two
    /// symbols that share a placeholder-bearing English (`%1$@ of %2$@`, the kit's `rowPosition` and `Screenshots`) are
    /// both judged and neither overwrites the other.
    public static func entries(for language: AppLanguage) throws -> [Entry] {
        var out: [Entry] = []
        for catalog in try all() {
            for (symbol, values) in catalog.strings {
                guard let english = values["en"], let value = values[language.rawValue] else { continue }
                out.append(Entry(module: catalog.module, symbol: symbol, english: english, value: value))
            }
        }
        return out
    }

    public static func all() throws -> [Catalog] {
        let modules = RepoSource.root.appendingPathComponent("Sources/Modules")
        let names = try FileManager.default.contentsOfDirectory(atPath: modules.path).sorted()
        var found: [(relative: String, module: String)] = names.map {
            ("Sources/Modules/\($0)/UI/Localizable.xcstrings", $0)
        }
        let kitFile = RepoSource.root.appendingPathComponent(kitPath).path
        guard FileManager.default.fileExists(atPath: kitFile) else {
            throw RepoSource.Failure("\(kitPath) is not there — the kit's words are in no catalog, "
                                    + "and a guard that read the modules alone would pass")
        }
        found.insert((kitPath, "HelmUI"), at: 0)
        // The host's two: its own words, and the changelog (the English sentence is the key there).
        found.append(("Sources/HelmAppStrings/Localizable.xcstrings", "HelmApp"))
        found.append(("Sources/HelmAppStrings/Changelog.xcstrings", "Changelog"))
        var out: [Catalog] = []
        for (relative, module) in found {
            guard FileManager.default.fileExists(atPath:
                RepoSource.root.appendingPathComponent(relative).path) else { continue }
            out.append(try read(relative, module: module))
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
}
