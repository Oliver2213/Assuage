import os

/// Unified-logging loggers, namespaced under the app's bundle id and written to the
/// system log store (visible in Console.app and sysdiagnose). Categorize by
/// subsystem area. Anything sensitive — contact identifiers, names, key material —
/// must use a `privacy:` annotation; string interpolations are redacted by default,
/// which we rely on.
enum Log {
    /// Reading and (especially) writing the user's Contacts.
    static let contacts = Logger(subsystem: AppInfo.bundleIdentifier, category: "contacts")
    /// Inspecting an age header — recipient parsing and naming from held keys/contacts.
    static let inspector = Logger(subsystem: AppInfo.bundleIdentifier, category: "inspector")
}
