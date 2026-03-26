import Foundation

/// Credentials for the registered GitHub App.
/// Register at: https://github.com/settings/apps
/// Enable "Device Flow" in your GitHub App settings.
///
/// The client ID is injected at build time via Secrets.xcconfig → Info.plist.
/// See Secrets.xcconfig.template for setup instructions.
enum OAuthConfig {
    static var clientID: String {
        // 1. Build-time injection via xcconfig → Info.plist (preferred)
        if let bundleID = Bundle.main.infoDictionary?["GHClientID"] as? String,
           !bundleID.isEmpty, bundleID != "YOUR_CLIENT_ID_HERE" {
            return bundleID
        }
        // 2. Environment variable fallback (CI / xcodebuild)
        if let envID = ProcessInfo.processInfo.environment["VIGILANT_CLIENT_ID"],
           !envID.isEmpty {
            return envID
        }
        fatalError("GitHub Client ID not configured. Copy Secrets.xcconfig.template to Secrets.xcconfig and set GH_CLIENT_ID.")
    }
}
