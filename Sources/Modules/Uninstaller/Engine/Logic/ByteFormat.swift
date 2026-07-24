import Foundation

/// Humanizes a byte count ("128 MB"). Base-1024, one decimal above bytes.
public enum ByteFormat {
    public static func string(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(max(0, bytes)); var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(Int(v)) B" : String(format: "%.1f %@", v, units[i])
    }
}
