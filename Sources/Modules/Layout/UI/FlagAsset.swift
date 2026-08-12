import AppKit
import Foundation
import HelmRuntime
import Module_Layout_Engine

/// The flag artwork, loaded from the bundle.
///
/// Helm used to draw these itself, from a table of constructions — bands with
/// proportions, a Nordic cross, a canton of stripes. It reached fifty regions
/// and stopped there, because the next ones needed things a table of shapes
/// cannot hold: Mexico's eagle, Portugal's armillary sphere, Korea's trigrams,
/// the counterchange of the Union Jack's saltire. Each of those was drawn as
/// an approximation or left as letters.
///
/// flag-icons has them properly, under MIT (see NOTICE.md), rendered from its
/// 4:3 SVGs at authoring time — see `Scripts/flags/fetch-flags.sh` for why
/// they are PNGs and not the SVGs themselves. Measured at 9, 13 and 18 pt
/// against the drawn set: every region legible, and the crests that used to
/// be approximations are simply there.
///
/// Images are cached: the menu bar redraws on every layout switch and every
/// theme change, and decoding a PNG each time is work nobody asked for.
enum FlagAsset {
    private static let cache = Cache()

    /// The artwork for a region, or nil where Helm ships none.
    static func image(region: String?) -> NSImage? {
        guard let region = region?.uppercased(), regions.contains(region) else { return nil }
        return cache.image(region)
    }

    /// Every region with artwork, sorted. Read once from the bundle so the
    /// list cannot drift from the files actually shipped — the previous table
    /// was a hand-maintained array beside the drawings it described.
    static let regions: Set<String> = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "png",
                                            subdirectory: "Flags"), !urls.isEmpty else {
            // The one failure the packaging script guards against, said out
            // loud on the other side: without the resource bundle every flag
            // silently becomes letters and the app looks merely misconfigured.
            HelmLog.shared.error(LayoutEngine.moduleID, "no flag artwork in the bundle — every layout "
                                 + "will fall back to letters (Bundle.module at "
                                 + "\(Redact.path(Bundle.module.bundlePath)))")
            return []
        }
        return Set(urls.map { $0.deletingPathExtension().lastPathComponent.uppercased() })
    }()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String: NSImage] = [:]

        func image(_ region: String) -> NSImage? {
            lock.lock()
            if let hit = stored[region] { lock.unlock(); return hit }
            lock.unlock()
            guard let url = Bundle.module.url(forResource: region,
                                              withExtension: "png", subdirectory: "Flags"),
                  let image = NSImage(contentsOf: url) else { return nil }
            lock.lock(); stored[region] = image; lock.unlock()
            return image
        }
    }
}
