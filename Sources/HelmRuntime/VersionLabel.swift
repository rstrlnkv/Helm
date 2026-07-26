import Foundation

/// How a version is shown, as opposed to how it is compared (`UpdateVersion`).
///
/// The About page presents the version as an instrument figure in a cell it
/// shares with two others. "0.7.1-dev.1" is nearly twice the width of a release
/// number and runs into the divider, so the release number stays the figure and
/// the prerelease part joins the caption below it.
public enum VersionLabel {
    public static func split(_ version: String) -> (figure: String, suffix: String?) {
        let parts = version.split(separator: "-", maxSplits: 1)
        guard parts.count == 2 else { return (version, nil) }
        // "dev.1" → "DEV 1": the dot separates a name from its ordinal.
        let suffix = parts[1].split(separator: ".").joined(separator: " ").uppercased()
        return (String(parts[0]), suffix.isEmpty ? nil : suffix)
    }

    /// "ВЕРСИЯ" for a release, "ВЕРСИЯ · DEV 1" for a dev build.
    public static func caption(_ label: String, for version: String) -> String {
        guard let suffix = split(version).suffix else { return label }
        return label + " · " + suffix
    }
}
