import Foundation

extension OutputStream {
    /// Write all of `data`, looping until the stream accepts every byte.
    @discardableResult
    func writeFully(_ data: Data) throws -> Int {
        guard !data.isEmpty else { return 0 }
        var total = 0
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var ptr = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var remaining = data.count
            while remaining > 0 {
                let n = write(ptr, maxLength: remaining)
                if n < 0 { throw streamError ?? CypherdexError.ioFailure }
                if n == 0 { break } // stream at capacity with no error; treat as done
                remaining -= n
                total += n
                ptr = ptr.advanced(by: n)
            }
        }
        return total
    }
}
