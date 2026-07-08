import Foundation
import AssuageCore

/// UI-facing presentation for an inspected age file, kept out of the core library.
extension AgeFileInfo.Kind {
    /// A short human label for a recipient scheme.
    var label: String {
        switch self {
        case .x25519: return "age recipient"
        case .passphrase: return "Passphrase (scrypt)"
        case .sshEd25519: return "SSH key (Ed25519)"
        case .sshRSA: return "SSH key (RSA)"
        case .secureEnclave: return "Secure Enclave (P-256)"
        case .p256Tag: return "P-256 (YubiKey)"
        case .postQuantum: return "Post-quantum (ML-KEM)"
        case .other(let type): return "Other (\(type))"
        }
    }

    var systemImage: String {
        switch self {
        case .x25519: return "person"
        case .passphrase: return "key"
        case .sshEd25519, .sshRSA: return "terminal"
        case .secureEnclave, .p256Tag: return "cpu"
        case .postQuantum: return "shield.lefthalf.filled"
        case .other: return "questionmark.circle"
        }
    }
}

extension AgeFileInfo {
    /// Recipient kinds collapsed to `(kind, count)` in first-appearance order —
    /// so "3 × age recipient" reads as one line instead of three.
    var recipientCounts: [(kind: Kind, count: Int)] {
        var order: [Kind] = []
        var counts: [Kind: Int] = [:]
        for recipient in recipients {
            if counts[recipient.kind] == nil { order.append(recipient.kind) }
            counts[recipient.kind, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    /// A one-line summary suitable for a compact caption.
    var summary: String {
        if isPassphrase { return "Locked with a passphrase" }
        let people = recipients.count
        let noun = people == 1 ? "recipient" : "recipients"
        return "Encrypted to \(people) \(noun)"
    }
}
