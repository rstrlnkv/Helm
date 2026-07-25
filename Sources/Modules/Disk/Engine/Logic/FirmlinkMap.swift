import Foundation

/// On an APFS boot volume group, `/` is the read-only System volume with the
/// Data volume's directories firmlinked into it. Both mounts share a device
/// id, so a device check cannot tell them apart, and every file is reachable
/// twice — once as `/Users/…` and once as `/System/Volumes/Data/Users/…`.
///
/// A walk that follows both paths counts each file once (fileID dedup) but
/// charges it to whichever path a worker reached first: a race that parked
/// hundreds of gigabytes under "System" while "Users" showed megabytes.
///
/// macOS ships its own list of these duplicate paths at `/usr/share/firmlinks`
/// — the same table the kernel uses to build the merged root. Skipping the
/// Data-side copy keeps the view the user recognises from Finder, and keeps
/// Data-only directories (the Spotlight index, staged installers) that a
/// blanket skip of the whole mount would silently drop.
public enum FirmlinkMap {
    public static let tablePath = "/usr/share/firmlinks"
    public static let dataMount = "/System/Volumes/Data"

    /// Data-side paths that duplicate something already reachable from `/`.
    /// Each table line is `<root path>\t<data-relative path>`.
    public static func duplicatePaths(firmlinks text: String, dataMount: String) -> Set<String> {
        var paths: Set<String> = []
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count == 2 else { continue }
            let relative = fields[1].trimmingCharacters(in: .whitespaces)
            guard !relative.isEmpty else { continue }
            paths.insert(dataMount + "/" + relative)
        }
        return paths
    }

    /// True when the scan would descend into the Data mount from above.
    /// Scanning the Data volume directly duplicates nothing.
    public static func applies(scanRoot: String, dataMount: String) -> Bool {
        guard scanRoot != dataMount else { return false }
        let prefix = scanRoot.hasSuffix("/") ? scanRoot : scanRoot + "/"
        return dataMount.hasPrefix(prefix)
    }

    /// The live set for a scan, read from the running system.
    public static func skipSet(scanRoot: String) -> Set<String> {
        guard applies(scanRoot: scanRoot, dataMount: dataMount),
              let text = try? String(contentsOfFile: tablePath, encoding: .utf8)
        else { return [] }
        return duplicatePaths(firmlinks: text, dataMount: dataMount)
    }
}
