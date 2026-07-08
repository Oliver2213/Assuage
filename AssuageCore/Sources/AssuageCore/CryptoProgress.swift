import Foundation

/// A snapshot of an in-flight encrypt/decrypt operation, suitable for driving a
/// progress bar with a throughput read-out.
public struct CryptoProgress: Sendable, Hashable {
    /// Bytes of *plaintext* processed so far.
    public var bytesProcessed: Int64
    /// Total plaintext bytes expected, when known ahead of time (encryption of a
    /// file or in-memory buffer). `nil` for decryption, where the plaintext size
    /// isn't known until the stream ends.
    public var totalBytes: Int64?
    /// Instantaneous-ish average throughput in bytes per second.
    public var bytesPerSecond: Double

    public init(bytesProcessed: Int64, totalBytes: Int64?, bytesPerSecond: Double) {
        self.bytesProcessed = bytesProcessed
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
    }

    /// Completion in `0...1`, or `nil` when the total isn't known.
    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(bytesProcessed) / Double(totalBytes))
    }
}

/// Callback invoked periodically during an operation. Marked `@Sendable` so the
/// synchronous crypto core can be driven from a background task.
public typealias ProgressHandler = @Sendable (CryptoProgress) -> Void

/// Tracks elapsed time to derive throughput. Value type; each operation makes one.
struct ProgressClock {
    let start = Date()

    func snapshot(processed: Int64, total: Int64?) -> CryptoProgress {
        let elapsed = max(Date().timeIntervalSince(start), 0.0001)
        return CryptoProgress(
            bytesProcessed: processed,
            totalBytes: total,
            bytesPerSecond: Double(processed) / elapsed
        )
    }
}
