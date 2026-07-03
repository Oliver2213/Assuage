import Foundation
import Security
import LocalAuthentication

/// How a Secure Enclave key is protected — mirrors age-plugin-se's options so our
/// generated keys and exported files line up with the reference plugin.
public enum SecureEnclaveAccessControl: String, Sendable, Hashable, Codable, CaseIterable {
    /// Device-bound, but usable without any presence check.
    case none
    /// Requires the device passcode.
    case passcode
    /// Requires any enrolled biometry (Touch ID), surviving biometry changes.
    case anyBiometry
    /// Requires biometry or, as a fallback, the passcode.
    case anyBiometryOrPasscode
    /// Requires biometry and the passcode.
    case anyBiometryAndPasscode
    /// Requires the currently-enrolled biometry set (invalidated if biometry changes).
    case currentBiometry
    /// Requires the current biometry set and the passcode.
    case currentBiometryAndPasscode

    /// The exact label age-plugin-se writes in the `# access control:` comment.
    public var ageLabel: String {
        switch self {
        case .none: return "none"
        case .passcode: return "passcode"
        case .anyBiometry: return "any biometry"
        case .anyBiometryOrPasscode: return "any biometry or passcode"
        case .anyBiometryAndPasscode: return "any biometry and passcode"
        case .currentBiometry: return "current biometry"
        case .currentBiometryAndPasscode: return "current biometry and passcode"
        }
    }

    /// A concise description for the key-generation UI.
    public var displayName: String {
        switch self {
        case .none: return "No presence required"
        case .passcode: return "Passcode"
        case .anyBiometry: return "Touch ID (any)"
        case .anyBiometryOrPasscode: return "Touch ID or passcode"
        case .anyBiometryAndPasscode: return "Touch ID and passcode"
        case .currentBiometry: return "Touch ID (current enrollment)"
        case .currentBiometryAndPasscode: return "Touch ID (current) and passcode"
        }
    }

    /// Whether using this key prompts the user for presence.
    public var requiresPresence: Bool { self != .none }

    /// Build the `SecAccessControl` for a Secure Enclave private key, replicating
    /// age-plugin-se's flag mapping exactly.
    func makeSecAccessControl() throws -> SecAccessControl {
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        switch self {
        case .anyBiometry, .anyBiometryAndPasscode:
            flags.insert(.biometryAny)
        case .currentBiometry, .currentBiometryAndPasscode:
            flags.insert(.biometryCurrentSet)
        case .anyBiometryOrPasscode:
            flags.insert(.userPresence)
        case .none, .passcode:
            break
        }
        switch self {
        case .passcode, .anyBiometryAndPasscode, .currentBiometryAndPasscode:
            flags.insert(.devicePasscode)
        default:
            break
        }

        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            &error
        ) else {
            throw error!.takeRetainedValue() as Swift.Error
        }
        return accessControl
    }
}
