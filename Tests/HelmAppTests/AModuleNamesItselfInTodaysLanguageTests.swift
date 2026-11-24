import HelmContract
import HelmUI
import XCTest
@testable import HelmApp

/// A module's name, short name and summary follow the language the app is in.
///
/// `ModuleMetadata` is a struct of finished strings, so metadata held in a
/// `static let` is built in whatever language first touches it and stays in it
/// for the life of the process. The sidebar's rows, every page header, the
/// welcome sheet's steps and the panel draw it: change the language in Settings
/// and the pages would change under names that do not.
///
/// **Per module, not over all of them together.** A single descriptor left
/// frozen is invisible to a reading that joins them all: the others still
/// differ between two languages and the blob differs with them.
@MainActor
final class AModuleNamesItselfInTodaysLanguageTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// Everything a descriptor says about itself that a person reads.
    private func spoken(_ descriptor: any ModuleDescriptor) -> String {
        let metadata = descriptor.moduleMetadata
        return "\(metadata.name)|\(metadata.shortName)|\(metadata.summary)"
    }

    func testEveryModuleSaysSomethingDifferentInSomeOtherLanguage() {
        for descriptor in ModuleRegistry.all {
            var readings: [AppLanguage: String] = [:]
            for language in AppLanguage.allCases {
                AppLanguage.override = language
                readings[language] = spoken(descriptor)
            }

            XCTAssertFalse(readings.values.contains { $0 == "||" },
                           "`\(descriptor.idRaw)` says nothing at all, and eight nothings are "
                           + "identical for free")
            XCTAssertGreaterThan(Set(readings.values).count, 1, """
                `\(descriptor.idRaw)` reads the same in all eight languages — \
                \(readings[.en] ?? "") — so its metadata is frozen in whichever language first \
                touched it rather than answering in the one the app is set to.
                """)
        }
    }

    /// And the language it answers in is today's, not the one asked for before.
    ///
    /// The check above is satisfied by metadata that merely *varies*; this one
    /// pins which reading belongs to which language, by taking the eight again
    /// in the opposite order. It guards against a memo for a property that
    /// spells three `L()` lookups on every read: a descriptor that returns the
    /// *previous* read varies, and fails here. A frozen `static let` is
    /// consistently wrong, which is the other test's business.
    func testTheReadingBelongsToTheLanguageItWasTakenIn() {
        var first: [AppLanguage: [String]] = [:]
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            first[language] = ModuleRegistry.all.map(spoken)
        }
        for language in AppLanguage.allCases.reversed() {
            AppLanguage.override = language
            XCTAssertEqual(ModuleRegistry.all.map(spoken), first[language], """
                the modules read differently in \(language.rawValue) depending on which \
                language was asked for before it
                """)
        }
    }
}
