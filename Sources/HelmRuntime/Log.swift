import OSLog

public enum Log {
    public static func module(_ id: String) -> Logger { Logger(subsystem: "com.helm.app", category: id) }
}
