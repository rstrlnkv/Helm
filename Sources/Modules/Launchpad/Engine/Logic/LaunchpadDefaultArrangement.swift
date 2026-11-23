import Foundation

extension LaunchpadLayout {

    /// **Where the apps stand when the person has not arranged them:** Apple's own apps in Apple's order, then a folder
    /// of the system utilities, then a page break, then every other app in catalog (A–Z) order.
    ///
    /// Used on a read with no layout file and by `.resetArrangement`; a stored layout is never rearranged by it.
    /// Apps are told by bundle id, never by name. A listed id that is not installed is skipped, an app on no list is
    /// left to the A–Z block. A page break with no app after it is dropped by `normalized()`. A utility is one whose id is listed **or** whose bundle lies under
    /// `/System/Applications/Utilities`, so one a later macOS adds lands in the folder too. `normalized()` dissolves a
    /// folder of fewer than two. The folder's name is passed in: the engine holds no strings. Hidden apps are not here;
    /// the caller keeps `hidden`.
    static func defaultArrangement(for catalog: [CatalogApp], utilitiesFolderName: String) -> LaunchpadLayout {
        let installed = Set(catalog.map(\.id))
        let utilities = catalog.filter { utilityIDs.contains($0.id) || $0.path.hasPrefix(utilitiesPath) }.map(\.id)
        let inFolder = Set(utilities)
        var items = appleOrder.filter { installed.contains($0) && !inFolder.contains($0) }.map(Item.app)
        if !utilities.isEmpty {
            items.append(.folder(Folder(id: utilitiesFolderID, name: utilitiesFolderName, apps: utilities)))
        }
        let placed = Set(items.map(\.itemID)).union(inFolder)
        items.append(.pageBreak)
        items += catalog.map(\.id).filter { !placed.contains($0) }.map(Item.app)
        return LaunchpadLayout(items: items).normalized()
    }

    /// A literal, not a fresh `UUID()`: a default with no file behind it is built again on every read, and the window holds
    /// an open folder by its id, which would be lost on each refresh. The folder is the only one a default makes, so one id serves.
    private static let utilitiesFolderID = UUID(uuidString: "0D5E3C1A-7B24-4F6A-9C18-5A2E8B7D4F03")!

    private static let utilitiesPath = "/System/Applications/Utilities/"

    /// Apple's own apps in the Dock's order of macOS 26, then Launchpad's older order for the rest.
    /// Copied on 2026-11-19 from `/System/Library/CoreServices/Dock.app/Contents/Resources/default.plist` (`persistent-apps`:
    /// Safari to System Settings; Keynote, Numbers and Pages are the `/Applications` ones) and, after it, the
    /// bundle ids of the `/System/Applications` apps the Dock leaves out, in the order the old Launchpad showed them.
    /// Read at build time, never at run time: `Apps` (the system's own launcher) goes last.
    private static let appleOrder: [AppID] = [
        "com.apple.Safari", "com.apple.MobileSMS", "com.apple.mail", "com.apple.Maps", "com.apple.Photos",
        "com.apple.FaceTime", "com.apple.mobilephone", "com.apple.iCal", "com.apple.AddressBook", "com.apple.reminders",
        "com.apple.Notes", "com.apple.TV", "com.apple.Music", "com.apple.Keynote", "com.apple.Numbers", "com.apple.Pages",
        "com.apple.games", "com.apple.AppStore", "com.apple.ScreenContinuity", "com.apple.systempreferences",
        "com.apple.findmy", "com.apple.PhotoBooth", "com.apple.Preview", "com.apple.podcasts", "com.apple.news",
        "com.apple.stocks", "com.apple.weather", "com.apple.clock", "com.apple.iBooksX", "com.apple.VoiceMemos",
        "com.apple.journal", "com.apple.freeform", "com.apple.Home", "com.apple.Passwords", "com.apple.GenerativePlaygroundApp",
        "com.apple.shortcuts", "com.apple.calculator", "com.apple.Dictionary", "com.apple.siri.launcher", "com.apple.campo",
        "com.apple.exposelauncher", "com.apple.helpviewer", "com.apple.Chess", "com.apple.Stickies", "com.apple.TextEdit",
        "com.apple.QuickTimePlayerX", "com.apple.apps.launcher",
    ]

    /// The apps of `/System/Applications/Utilities` (read from the bundles' `CFBundleIdentifier` on 2026-11-19) and the four
    /// of Apple's old "Other" folder that live outside it: Automator, Font Book, Image Capture, Time Machine.
    private static let utilityIDs: Set<AppID> = [
        "com.apple.ActivityMonitor", "com.apple.airport.airportutility", "com.apple.audio.AudioMIDISetup",
        "com.apple.BluetoothFileExchange", "com.apple.ColorSyncUtility", "com.apple.Console", "com.apple.DigitalColorMeter",
        "com.apple.DiskUtility", "com.apple.grapher", "com.apple.Magnifier", "com.apple.MigrateAssistant",
        "com.apple.printcenter", "com.apple.ScreenSharing", "com.apple.screenshot.launcher", "com.apple.ScriptEditor2",
        "com.apple.SystemProfiler", "com.apple.Terminal", "com.apple.VoiceOverUtility",
        "com.apple.Automator", "com.apple.FontBook", "com.apple.Image_Capture", "com.apple.backup.launcher",
    ]
}
