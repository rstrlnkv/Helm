import HelmUI

/// Every user-visible string this module has.
///
/// **"Host" is about to mean three things on one page** — the module, the
/// system file, and an `~/.ssh/config` block — and one English key means one
/// thing. Seventeen keys in this app already meant two things each and twelve
/// had to be split, so these three are three keys from the first day.
public enum HostsStr {
    public static var moduleName: String { L("Hosts & Keys") }
    /// The sidebar column is fixed and cuts a long name mid-word.
    public static var moduleNameShort: String { L("Hosts") }
    public static var summary: String { L("Edit the hosts file, SSH hosts and keys") }
}
