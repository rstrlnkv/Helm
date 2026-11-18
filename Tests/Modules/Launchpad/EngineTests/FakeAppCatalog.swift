@testable import Module_Launchpad_Engine

/// Stands for the installed-apps side of `AppCatalogPort`, whose duplicate ids collapse to one entry; a test sets what the next read answers.
final class FakeAppCatalog: AppCatalogPort, @unchecked Sendable {
    var reading: CatalogReading
    init(_ ids: [String] = [], complete: Bool = true) {
        var seen = Set<String>()
        reading = CatalogReading(apps: ids.filter { seen.insert($0).inserted }.map { CatalogApp(id: $0, name: $0.capitalized, path: "/Applications/\($0).app") },
                                 complete: complete)
    }
}

extension FakeAppCatalog {
    func read() -> CatalogReading { reading }
}
