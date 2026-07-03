import SwiftUI
import CypherdexCore

/// A determinate-or-indeterminate progress bar with a size / throughput read-out.
struct ProgressStrip: View {
    let progress: CryptoProgress?

    var body: some View {
        if let progress {
            VStack(alignment: .leading, spacing: 4) {
                if let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                HStack {
                    Text(processedLabel(progress))
                    Spacer()
                    Text(ByteFormatting.rate(progress.bytesPerSecond))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }

    private func processedLabel(_ progress: CryptoProgress) -> String {
        if let total = progress.totalBytes {
            return "\(ByteFormatting.size(progress.bytesProcessed)) of \(ByteFormatting.size(total))"
        }
        return ByteFormatting.size(progress.bytesProcessed)
    }
}
