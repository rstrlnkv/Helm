import Foundation

/// **What a launch may open, decided from a fresh read and nothing else.**
///
/// The path comes only from `reading`, and only if the bundle there still answers `id`: a
/// path the person saw a minute ago, or one in a planted layout file, is never opened.
/// Pure: `bundleID` is the catalog's own door, passed in.
enum LaunchResolution: Equatable {
    case open(URL)
    case gone
    case unreadable

    static func resolve(id: AppID, reading: CatalogReading, bundleID: (String) -> String?) -> LaunchResolution {
        guard let app = reading.apps.first(where: { $0.id == id }) else {
            return reading.complete ? .gone : .unreadable
        }
        guard bundleID(app.path) == id else { return .gone }
        return .open(URL(fileURLWithPath: app.path, isDirectory: true))
    }
}
