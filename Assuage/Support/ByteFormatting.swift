import Foundation

/// Human-readable byte counts and throughput for progress read-outs.
enum ByteFormatting {
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let clamped = Int64(max(0, bytesPerSecond))
        return "\(clamped.formatted(.byteCount(style: .file)))/s"
    }
}
