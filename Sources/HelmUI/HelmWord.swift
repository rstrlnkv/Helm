import Foundation

/// The words that more than one part of Helm draws, said once.
///
/// A word two modules, the kit or the host all show is one text in eight
/// languages, not one per caller: «Cancel» in Uninstaller, in Disk and in the
/// host's dialogs is the same button, and three spellings of it drift. A page's
/// own strings file reads its shared words from here and its own words from its
/// own table. `HelmControlName` and `HelmSectionName` are the same shape for the
/// names of controls and of sections; these are not controls (`System`,
/// `Stopped` and the colours are not), hence a name of their own.
///
/// `String` only: a catalog's symbols are internal to the target that owns it,
/// and no `LocalizedStringResource` crosses a target, so no bundle can be
/// confused with another. The four that a caller asks in a language other than
/// the app's — a test reads the other seven — take it.
public enum HelmWord {
    public static var addApp: String { L("Add app…") }
    public static var apps: String { L("Apps") }
    public static var back: String { L("Back") }
    public static func cancel(language: AppLanguage) -> String { L("Cancel", language: language) }
    public static var cancel: String { cancel(language: AppLanguage.current) }
    public static var choose: String { L("Choose…") }
    public static var clear: String { L("Clear") }
    public static var clearSelection: String { L("Clear selection") }
    public static var close: String { L("Close") }
    public static var copy: String { L("Copy") }
    public static var done: String { L("Done") }
    public static var edit: String { L("Edit") }
    public static func cannotReadThisFolder(language: AppLanguage) -> String { L("Helm cannot read this folder", language: language) }
    public static var cannotReadThisFolder: String { cannotReadThisFolder(language: AppLanguage.current) }
    public static var keyboardShortcuts: String { L("Keyboard shortcuts") }
    public static var launchAgents: String { L("Launch agents") }
    public static var leftovers: String { L("Leftovers") }
    public static var moveToTrash: String { L("Move to Trash") }
    public static var noLeftoversFound: String { L("No leftovers found.") }
    public static var refreshList: String { L("Refresh list") }
    public static var scanAgain: String { L("Scan again") }
    public static var scanning: String { L("Scanning…") }
    public static var searching: String { L("Searching…") }
    public static var selectAll: String { L("Select all") }
    public static var settingsFiles: String { L("Settings files") }
    public static var showInFinder: String { L("Show in Finder") }
    public static var showWhatIsMarkedForRemoval: String { L("Show what is marked for removal") }
    public static var stop: String { L("Stop") }
    public static var stopScan: String { L("Stop scan") }
    public static var stopped: String { L("Stopped") }
    public static var system: String { L("System") }
    public static var timer: String { L("Timer") }
    public static var blue: String { L("Blue") }
    public static var green: String { L("Green") }
    public static var next: String { L("Next") }
    public static var orange: String { L("Orange") }
    public static var purple: String { L("Purple") }
    public static var red: String { L("Red") }
    public static var white: String { L("White") }
    public static var yellow: String { L("Yellow") }
    public static var clipboard: String { L("Clipboard") }
    public static var openFullDiskAccess: String { L("Open Full Disk Access…") }
    public static var rename: String { L("Rename") }
    public static func show(language: AppLanguage) -> String { L("Show", language: language) }
    public static var show: String { show(language: AppLanguage.current) }
    public static func turnOn(language: AppLanguage) -> String { L("Turn on", language: language) }
    public static var turnOn: String { turnOn(language: AppLanguage.current) }
    public static var grant: String { L("Grant…") }
    public static var media: String { L("Media") }
    public static var network: String { L("Network") }
    public static var openHelmAtLogin: String { L("Open Helm at login") }
}
