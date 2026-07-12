import Foundation

/// Single source of truth for the app's identity: name, versioning, bundle ID,
/// and how this build was distributed.
///
/// Everything is derived live from `Bundle.main`, so renaming the Xcode target
/// flows through with no code change. Anything user-facing that would otherwise
/// hardcode the name should read `AppInfo.name` instead.
enum AppInfo {
    /// The app's display name, read from the bundle: `CFBundleDisplayName`, falling
    /// back to `CFBundleName`, then the process name. Never a hardcoded literal.
    static let name: String = {
        let bundle = Bundle.main
        if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !display.isEmpty {
            return display
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return ProcessInfo.processInfo.processName
    }()
    static let author = "Blake Oliver"
    static let website = URL(string: "https://smoll.dev/cypherdex")!
    static let tagline = "Native age encryption for macOS"
    static let copyright = "© 2026 Blake Oliver"

    /// Reverse-DNS bundle identifier, read live from `Bundle.main` — the single
    /// source for anything that namespaces data as "this app's". Traps on nil,
    /// which would mean a broken `Info.plist` / `PRODUCT_BUNDLE_IDENTIFIER`.
    static let bundleIdentifier: String = {
        guard let id = Bundle.main.bundleIdentifier else {
            preconditionFailure("Bundle.main.bundleIdentifier is nil — check Info.plist / PRODUCT_BUNDLE_IDENTIFIER")
        }
        return id
    }()

    /// Marketing version, e.g. `1.0` (`CFBundleShortVersionString`).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Build number (`CFBundleVersion`).
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// How this build reached the machine (App Store, TestFlight, development, …).
    static var distribution: AppDistribution { DistributionDetector.current }

    /// True only for development builds — gates developer-only UI.
    static var isDeveloperBuild: Bool { distribution == .development }
}

/// How the running build was distributed. (Ported from AudioBabble.)
enum AppDistribution: String, CaseIterable {
    case development = "Development"
    case testFlight = "TestFlight"
    case appStore = "App Store"
    case adhoc = "Ad Hoc"
    case enterprise = "Enterprise"
    case unknown = "Unknown"

    var displayName: String { rawValue }
}

enum DistributionDetector {
    static var current: AppDistribution {
        #if DEBUG
        return .development
        #else
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           receiptURL.lastPathComponent == "sandboxReceipt" {
            return .testFlight
        }
        if Bundle.main.path(forResource: "embedded", ofType: "provisionprofile") != nil {
            return .adhoc
        }
        return .appStore
        #endif
    }
}
