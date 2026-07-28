import Foundation

/// Giving the pages back after a module has finished with them.
///
/// Freeing an allocation returns it to malloc, not to the system: after a scan
/// of a large volume the process kept gigabytes of emptied regions — 13 299 of
/// them at one measurement — and the person watching Activity Monitor sees a
/// menu-bar utility holding three gigabytes half an hour after they last asked
/// it for anything. The memory is not leaked and not in use; it is simply
/// still on our side of the fence.
///
/// `malloc_zone_pressure_relief` is the supported way to hand it back: the same
/// path the system takes when it warns processes about pressure, done on
/// purpose at the moment we know the work is over rather than waiting for a
/// machine to run short.
public enum MemoryReclaim {

    /// Call after work that allocated in bulk — a scan, a walk, a measurement —
    /// and after a module is switched off. Logs what it gave back, because a
    /// reclaim that quietly does nothing is worse than none: it would end the
    /// hunt for the next leak.
    ///
    /// Not free (it walks the zones), so it belongs at the end of an operation
    /// the user waited seconds for, never in a loop.
    public static func afterHeavyWork(_ label: String) {
        let before = MemoryFootprint.current()
        malloc_zone_pressure_relief(nil, 0)
        guard let before, let after = MemoryFootprint.current() else { return }
        let mb = { (b: Int) in b / (1024 * 1024) }
        // Only when it actually moved something: on a small operation this is
        // a no-op and a line saying so is noise on every scan.
        guard before - after >= 8 * 1024 * 1024 else { return }
        HelmLog.shared.info("memory", "\(label): returned \(mb(before - after)) MB, now \(mb(after)) MB")
    }
}
