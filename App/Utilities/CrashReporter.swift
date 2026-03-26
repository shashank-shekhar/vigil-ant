import Foundation
import MetricKit
import os

nonisolated final class CrashReporter: NSObject, MXMetricManagerSubscriber {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CrashReporter")
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f
    }()
    private let diagnosticsDirectory: URL
    private let maxFileCount = 35
    private let maxFileAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    override init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier!
        diagnosticsDirectory = appSupport.appendingPathComponent(bundleID).appendingPathComponent("diagnostics")

        super.init()

        try? FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)

        MXMetricManager.shared.add(self)
        CrashReporter.logger.info("CrashReporter registered with MetricKit")

        processPastPayloads()
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            CrashReporter.logger.warning("Diagnostic payload received: \(payload.dictionaryRepresentation())")
            persist(payload.jsonRepresentation(), prefix: "diagnostic", date: payload.timeStampBegin)
        }
    }

    // MARK: - Past payloads

    private func processPastPayloads() {
        let pastDiagnostics = MXMetricManager.shared.pastDiagnosticPayloads
        if !pastDiagnostics.isEmpty {
            CrashReporter.logger.info("Processing \(pastDiagnostics.count) past diagnostic payload(s)")
            for payload in pastDiagnostics {
                persist(payload.jsonRepresentation(), prefix: "diagnostic", date: payload.timeStampBegin)
            }
        }
    }

    // MARK: - Persistence

    private func persist(_ data: Data, prefix: String, date: Date) {
        let timestamp = CrashReporter.dateFormatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(prefix)_\(timestamp).json"
        let fileURL = diagnosticsDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: .atomic)
            CrashReporter.logger.debug("Saved \(prefix) payload to \(fileURL.lastPathComponent)")
            pruneOldFiles()
        } catch {
            CrashReporter.logger.error("Failed to save \(prefix) payload: \(error.localizedDescription)")
        }
    }

    private func pruneOldFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: diagnosticsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let now = Date()
        var remaining = files.filter { url in
            guard url.pathExtension == "json",
                  let attrs = try? url.resourceValues(forKeys: [.creationDateKey]),
                  let created = attrs.creationDate else { return false }

            if now.timeIntervalSince(created) > maxFileAge {
                try? fm.removeItem(at: url)
                CrashReporter.logger.debug("Pruned expired file: \(url.lastPathComponent)")
                return false
            }
            return true
        }

        if remaining.count > maxFileCount {
            remaining.sort { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return dateA < dateB
            }
            for file in remaining.prefix(remaining.count - maxFileCount) {
                try? fm.removeItem(at: file)
                CrashReporter.logger.debug("Pruned excess file: \(file.lastPathComponent)")
            }
        }
    }
}
