import Foundation

/// The mark that says "this rule has already had its turn at this file".
///
/// Without it, a rule that sorts a file into a subfolder of the folder it
/// watches sees that file again on the next sweep, and again after that. The
/// mark is an extended attribute rather than a list in a database because it
/// has to travel with the file: a moved file keeps its xattrs within a volume,
/// and a list of paths would be stale the moment the rule that consults it did
/// its job.
///
/// One attribute holding a set of rule ids, not one attribute per rule: a file
/// carries a handful of these at most, and a single value keeps the accumulate
/// case — several rules stamping the same file over time — from depending on
/// how many attributes a filesystem will hold.
public enum RuleStamp {
    static let attribute = "com.helm.rules.stamp"

    public static func isStamped(_ path: String, by ruleID: String) -> Bool {
        ids(at: path).contains(ruleID)
    }

    /// Returns whether the mark stuck. Stamping is a courtesy, not a
    /// permission: a volume without extended attributes, or a file Helm may
    /// read but not annotate, still gets acted on — the caller logs the miss
    /// and moves on rather than refusing the file or looping on it.
    @discardableResult
    public static func stamp(_ path: String, by ruleID: String) -> Bool {
        var stamped = ids(at: path)
        guard !stamped.contains(ruleID) else { return true }
        stamped.append(ruleID)
        guard let data = try? JSONEncoder().encode(stamped) else { return false }
        return data.withUnsafeBytes { buffer in
            setxattr(path, attribute, buffer.baseAddress, buffer.count, 0, 0) == 0
        }
    }

    private static func ids(at path: String) -> [String] {
        let length = getxattr(path, attribute, nil, 0, 0, 0)
        guard length > 0 else { return [] }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { buffer in
            getxattr(path, attribute, buffer.baseAddress, length, 0, 0)
        }
        guard read == length else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
