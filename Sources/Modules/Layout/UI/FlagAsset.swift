import AppKit
import Foundation
import HelmRuntime
import Module_Layout_Engine

/// The flag artwork, loaded from the bundle.
///
/// Artwork rather than drawn geometry, because a table of shapes cannot hold
/// Mexico's eagle, Portugal's armillary sphere or Korea's trigrams.
///
/// From flag-icons, under MIT (see NOTICE.md), rendered from its 4:3 SVGs at
/// authoring time — see `Scripts/flags/fetch-flags.sh` for why they are PNGs
/// and not the SVGs themselves. Legible at 9, 13 and 18 pt.
///
/// Images are cached: the menu bar redraws on every layout switch and every
/// theme change, and decoding a PNG each time is work nobody asked for.
enum FlagAsset {
    private static let cache = LockedMemo<String, NSImage>()

    /// The artwork for a region, or nil where Helm ships none.
    static func image(region: String?) -> NSImage? {
        guard let region = region?.uppercased(), regions.contains(region) else { return nil }
        // `valueOrNothing`: a region whose artwork would not decode is not
        // remembered as absent, which is the same reasoning the keyboard tables
        // one target over give.
        return cache.valueOrNothing(for: region) {
            guard let url = Bundle.module.url(forResource: region,
                                              withExtension: "png", subdirectory: "Flags")
            else { return nil }
            return NSImage(contentsOf: url)
        }
    }

    /// Every region with artwork, sorted. Read once from the bundle so the
    /// list cannot drift from the files actually shipped.
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

}
