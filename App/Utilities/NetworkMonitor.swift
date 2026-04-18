import Foundation
import Network
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NetworkMonitor")

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier!).networkmonitor")

    init() {
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self.update(isConnected: connected)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func update(isConnected connected: Bool) {
        let wasConnected = isConnected
        isConnected = connected
        if !wasConnected && connected {
            logger.info("Network connectivity restored")
        } else if wasConnected && !connected {
            logger.info("Network connectivity lost")
        }
    }
}
