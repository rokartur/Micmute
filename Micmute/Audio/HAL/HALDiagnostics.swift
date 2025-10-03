import Foundation
import os.log

@MainActor
enum HALDiagnostics {
    private static let log = Logger(subsystem: "com.rokartur.Micmute", category: "HALDiagnostics")

    static func reportBackendStart(isAvailable: Bool) {
        if isAvailable {
            log.info("HAL backend available and selected")
        } else {
            log.error("HAL backend not present; no fallback available")
        }
    }

    static func reportProcessSync(bundleIDs: [String]) {
        log.debug("HAL backend process sync count=\(bundleIDs.count, privacy: .public)")
    }

    static func reportError(_ message: String, status: OSStatus) {
        log.error("HAL error: \(message, privacy: .public) status=\(status)")
    }
}
