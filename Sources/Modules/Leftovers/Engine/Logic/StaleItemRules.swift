import Foundation

/// What may be offered for removal. These files are loaded by macOS at login,
/// so the rules err on the side of leaving things alone: anything Apple's,
/// anything in a system location, anything whose owner is still installed, and
/// anything whose owner cannot be identified stays put.
public enum StaleItemRules {
    /// An extension id is its host app's id plus one component:
    /// com.acme.app.networkExtension → com.acme.app.
    static func hostIdentifier(of identifier: String) -> String {
        let parts = identifier.split(separator: ".")
        return parts.count > 3 ? parts.dropLast().joined(separator: ".") : identifier
    }

    /// Locations Helm never touches, whatever they contain.
    static let protectedPrefixes = [
        "/System/", "/Library/Apple/", "/usr/", "/bin/", "/sbin/", "/private/var/db/",
    ]

    /// Namespaces that belong to macOS or to shared plumbing rather than to a
    /// single app: sandbox groups, the printing stack, the Sparkle updater
    /// framework many apps embed.
    static let protectedNamespaces = [
        "com.apple.", "systemgroup.", "group.", "org.cups.", "org.sparkle-project.",
    ]

    public static func isRemovable(identifier: String, path: String,
                                   ownerInstalled: Bool, installedIDs: Set<String>) -> Bool {
        guard !ownerInstalled else { return false }
        guard !identifier.isEmpty, !identifier.hasPrefix(".") else { return false }
        guard !protectedNamespaces.contains(where: identifier.hasPrefix) else { return false }
        guard !protectedPrefixes.contains(where: path.hasPrefix) else { return false }
        // Reverse-DNS with at least vendor + name: a bare word says nothing
        // about who owns the file.
        guard identifier.split(separator: ".").count >= 3 else { return false }
        // A helper of an installed app carries its prefix; that app still needs it.
        guard !installedIDs.contains(where: { identifier.hasPrefix($0 + ".") }) else { return false }
        // A dry run on a real machine offered com.adobe.Photoshop and
        // com.microsoft.office: settings whose ids match no app bundle, while
        // the software was very much installed. If a vendor has anything
        // installed at all, leave their files alone.
        guard !vendorHasInstalledApp(identifier, installedIDs) else { return false }
        return !installedIDs.contains(identifier)
    }

    /// "com.adobe.Photoshop" → "com.adobe."
    static func vendorPrefix(_ identifier: String) -> String? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: ".") + "."
    }

    static func vendorHasInstalledApp(_ identifier: String, _ installedIDs: Set<String>) -> Bool {
        guard let vendor = vendorPrefix(identifier) else { return false }
        return installedIDs.contains { $0.hasPrefix(vendor) }
    }
}
