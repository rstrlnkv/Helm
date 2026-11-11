import Foundation

/// The words that more than one part of Helm draws, said once.
///
/// A word two modules, the kit or the host all show is one text in eight
/// languages, not one per caller: «Cancel» in Uninstaller, in Disk and in the
/// host's dialogs is the same button, and three spellings of it drift. A page's
/// own strings file reads its shared words from here and its own words from its
/// own table. `HelmControlName` and `HelmSectionName` are the same shape for the
/// names of controls and of sections; these are not controls (`Stopped`
/// and the colours are not), hence a name of their own.
///
/// `String` only: a catalog's symbols are internal to the target that owns it,
/// and what crosses from the kit's words to a caller is a `String`, so no bundle
/// can be confused with another (a module's own resource goes to the kit's `L`,
/// which is the one door). The ones that a caller asks in a language other than
/// the app's — a test reads the other seven — take it
/// (`command grep -n 'language: AppLanguage)' Sources/HelmUI/HelmWord.swift`).
public enum HelmWord {
    public static var addApp: String { L(.addApp) }
    public static var apps: String { L(.apps) }
    public static var back: String { L(.back) }
    public static func cancel(language: AppLanguage) -> String { L(.cancel, language: language) }
    public static var cancel: String { cancel(language: AppLanguage.current) }
    public static var choose: String { L(.choose) }
    public static var clear: String { L(.clear) }
    public static var clearSelection: String { L(.clearSelection) }
    public static var close: String { L(.close) }
    public static var copy: String { L(.copy) }
    public static var done: String { L(.done) }
    public static var edit: String { L(.edit) }
    public static func cannotReadThisFolder(language: AppLanguage) -> String { L(.cannotReadThisFolder, language: language) }
    public static var keyboardShortcuts: String { L(.keyboardShortcuts) }
    public static var launchAgents: String { L(.launchAgents) }
    public static var leftovers: String { L(.leftovers) }
    public static var moveToTrash: String { L(.moveToTrash) }
    public static var noLeftoversFound: String { L(.noLeftoversFound) }
    public static var refreshList: String { L(.refreshList) }
    public static var scanAgain: String { L(.scanAgain) }
    public static var scanning: String { L(.scanning) }
    public static var searching: String { L(.searching) }
    public static var selectAll: String { L(.selectAll) }
    public static var settingsFiles: String { L(.settingsFiles) }
    public static var showInFinder: String { L(.showInFinder) }
    public static var showWhatIsMarkedForRemoval: String { L(.showWhatIsMarkedForRemoval) }
    public static var stop: String { L(.stop) }
    public static var stopScan: String { L(.stopScan) }
    public static var stopped: String { L(.stopped) }
    public static var timer: String { L(.timer) }
    public static var blue: String { L(.blue) }
    public static var green: String { L(.green) }
    public static var next: String { L(.next) }
    public static var orange: String { L(.orange) }
    public static var purple: String { L(.purple) }
    public static var red: String { L(.red) }
    public static var white: String { L(.white) }
    public static var yellow: String { L(.yellow) }
    public static var clipboard: String { L(.clipboard) }
    public static var openFullDiskAccess: String { L(.openFullDiskAccess) }
    public static var rename: String { L(.rename) }
    public static func show(language: AppLanguage) -> String { L(.show, language: language) }
    public static var show: String { show(language: AppLanguage.current) }
    public static func turnOn(language: AppLanguage) -> String { L(.turnOn, language: language) }
    public static var turnOn: String { turnOn(language: AppLanguage.current) }
    public static var grant: String { L(.grant) }
    public static var media: String { L(.media) }
    public static var network: String { L(.network) }
    public static var openHelmAtLogin: String { L(.openHelmAtLogin) }
}
