import Foundation

/// The account names Helm will paste into a privileged command, and no others.
///
/// `NSUserName()` is not a constant: on a directory-bound or MDM-managed Mac it
/// is whatever `dscl` says. Two places send it toward root — the Keep Awake
/// sudoers rule and Homebrew's `chown -R <user>:admin /opt/homebrew` — where a
/// backtick or `$(…)` is code, and where a name that breaks `sudoers` syntax
/// takes sudo down for the whole machine, recoverable only from recovery mode.
/// Neither is worth supporting an exotic name for.
///
/// It lives here because it was written twice, character for character, and a
/// rule that is stated twice is a rule that will be strengthened once.
public enum AccountName {
    public static func isPlausible(_ name: String) -> Bool {
        // `ALL` is a sudoers keyword, and a leading `-` reads as a flag to the
        // tools this name is handed to.
        guard !name.isEmpty, name.count <= 64, name != "ALL", !name.hasPrefix("-") else {
            return false
        }
        return name.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
        }
    }
}
