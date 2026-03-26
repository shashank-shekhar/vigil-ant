import Foundation
import os

#if canImport(Sparkle)
import Sparkle
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SparkleUpdater")

// MARK: - Xcode Project Setup Required
//
// 1. Add Sparkle SPM dependency:
//    File > Add Package Dependencies...
//    URL: https://github.com/sparkle-project/Sparkle
//    Rule: Up to Next Major Version from 2.6.0
//    Add "Sparkle" product to the Vigil-ant target
//
// 2. Add to Info.plist (target > Info > Custom macOS Application Target Properties):
//    SUFeedURL (String): your appcast URL, e.g. https://yourdomain.com/appcast.xml
//    SUPublicEDKey (String): your EdDSA public key (generate with Sparkle's generate_keys tool)

/// Wraps Sparkle's `SPUStandardUpdaterController` for use in SwiftUI.
/// Falls back to a no-op stub if the Sparkle dependency hasn't been added yet.
@Observable
final class SparkleUpdater {
    private(set) var canCheckForUpdates = false

    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        observation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, change in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = change.newValue ?? false
            }
        }

        logger.info("Sparkle updater initialized")
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    #else
    var automaticallyChecksForUpdates: Bool = false

    init() {
        logger.info("Sparkle not available — updater disabled")
    }

    func checkForUpdates() {}
    #endif
}
