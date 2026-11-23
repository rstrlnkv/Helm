import Foundation

/// Where macOS mounts the Data volume, on which every user file appears a
/// second time (`FirmlinkMap`, `Redact`, `LogRoot` all name it).
enum DataVolume {
    static let mount = "/System/Volumes/Data"
}
