import Foundation
import Network
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NetworkMonitor")

/// @unchecked Sendable is safe: `isConnected` is only mutated via DispatchQueue.main.async,
/// and all reads happen on @MainActor (AppState, SwiftUI views).
@Observable
final class NetworkMonitor: @unchecked Sendable {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier!).networkmonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = connected
                if !wasConnected && connected {
                    logger.info("Network connectivity restored")
                } else if wasConnected && !connected {
                    logger.info("Network connectivity lost")
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
