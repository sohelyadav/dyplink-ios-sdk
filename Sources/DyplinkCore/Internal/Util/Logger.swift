import Foundation
import os.log

/// Internal logger for the Dyplink SDK.
///
/// Mirrors the Android `Logger` — a centralized emitter whose verbosity
/// is controlled by a mutable `logLevel` property. Uses `os.log` under
/// the hood for Console integration.
internal enum DyplinkLogger {
    /// Global log level — defaults to `.none` until `Dyplink.initialize`
    /// flips it.
    nonisolated(unsafe) static var logLevel: DyplinkLogLevel = .none

    private static let log = OSLog(subsystem: "com.dyplink.sdk", category: "Dyplink")

    static func e(_ message: @autoclosure () -> String, _ error: Error? = nil) {
        guard logLevel.rawValue >= DyplinkLogLevel.error.rawValue else { return }
        let m = message()
        if let e = error {
            os_log("%{public}@: %{public}@", log: log, type: .error, m, String(describing: e))
        } else {
            os_log("%{public}@", log: log, type: .error, m)
        }
    }

    static func w(_ message: @autoclosure () -> String) {
        guard logLevel.rawValue >= DyplinkLogLevel.warn.rawValue else { return }
        os_log("%{public}@", log: log, type: .default, message())
    }

    static func i(_ message: @autoclosure () -> String) {
        guard logLevel.rawValue >= DyplinkLogLevel.info.rawValue else { return }
        os_log("%{public}@", log: log, type: .info, message())
    }

    static func d(_ message: @autoclosure () -> String) {
        guard logLevel.rawValue >= DyplinkLogLevel.debug.rawValue else { return }
        os_log("%{public}@", log: log, type: .debug, message())
    }

    static func v(_ message: @autoclosure () -> String) {
        guard logLevel.rawValue >= DyplinkLogLevel.verbose.rawValue else { return }
        os_log("%{public}@", log: log, type: .debug, message())
    }
}
