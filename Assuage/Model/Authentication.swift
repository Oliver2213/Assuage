import LocalAuthentication

/// A thin wrapper over `LocalAuthentication` for the app's soft, action-level
/// gates (export a key, delete a key). This is deterrence against casual access
/// on an unlocked Mac — it does *not* encrypt the key at rest. Real at-rest
/// protection comes from a Secure Enclave key's own access control.
enum Authentication {
    /// Prompt for the device owner — Touch ID with a passcode fallback. Returns
    /// `true` only on success; cancellation or any error returns `false`.
    ///
    /// If the Mac can't evaluate the policy at all (e.g. no login password set),
    /// we proceed rather than lock the user out of their own keys — the gate is
    /// meaningless without any credential to check against.
    static func authorize(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
