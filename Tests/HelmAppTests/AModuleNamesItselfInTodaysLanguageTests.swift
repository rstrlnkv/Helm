import HelmContract
import HelmUI
import XCTest
@testable import HelmApp

/// A module's name, short name and summary follow the language the app is in.
///
/// They did not. `ModuleMetadata` is a struct of finished strings and every
/// descriptor held one in a `public static let` — so the nine of them were built
/// the first time anything touched them, in whatever language that first touch
/// happened to be, and stayed in it for the life of the process. `L()` had
/// already answered by then; nothing downstream could put it right.
///
/// What that cost is everywhere the metadata is drawn rather than the module's
/// own strings: the sidebar's rows, every page header, the welcome sheet's steps
/// and the panel. Change the language in Settings and the pages change under
/// names that do not — until the app is restarted, which is the one thing the
/// in-app language picker exists to avoid.
///
/// **Per module, not over the nine of them together.** A single descriptor left
/// frozen is invisible to a reading that joins all nine: the other eight still
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
    /// in the opposite order. It is the guard against the natural next edit
    /// here: a memo, for a property that now spells three `L()` lookups on every
    /// read.
    ///
    /// **It passed before the fix as well, and that is not the same as being
    /// unable to fail** — a frozen `static let` is consistent, it is just
    /// consistently wrong, which is the other test's business. Proven with a
    /// descriptor that returned the *previous* read: this went red in four
    /// languages naming the module and both readings, while the check above
    /// stayed green because the values still varied.
    func testTheReadingBelongsToTheLanguageItWasTakenIn() {
        var first: [AppLanguage: [String]] = [:]
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            first[language] = ModuleRegistry.all.map(spoken)
        }
        for language in AppLanguage.allCases.reversed() {
            AppLanguage.override = language
            XCTAssertEqual(ModuleRegistry.all.map(spoken), first[language], """
                the nine modules read differently in \(language.rawValue) depending on which \
                language was asked for before it
                """)
        }
    }
}
