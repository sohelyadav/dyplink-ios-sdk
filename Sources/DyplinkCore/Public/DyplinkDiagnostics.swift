import Foundation

/// The SDK's diagnostic channel, for the optional modules.
///
/// Push, Banners and Messages all swallow their failures by design — a
/// dropped analytics request must never disturb notification handling or a
/// host app's UI. But `DyplinkLogger` is internal to `DyplinkCore`, so none
/// of them had anywhere to say so: `_ = try? await …` and silence, which is
/// why a banner module that answered 401 to every request it ever made, and
/// a conversion endpoint that rejected every event, both looked exactly like
/// working code.
///
/// Off unless the host app asks for it. Everything here is gated on the
/// `logLevel` given to `DyplinkConfig`, which defaults to `.none`, and goes
/// to `os.log` under the `com.dyplink.sdk` subsystem like the rest of the
/// SDK's logging.
///
/// Not part of the SDK's supported surface — `public` only because Swift has
/// no narrower way to share one module's internals with another.
public enum DyplinkDiagnostics {

    /// Something the SDK could not do, and carried on without.
    public static func warn(_ message: @autoclosure () -> String) {
        DyplinkLogger.w(message())
    }

    /// Something the SDK could not do that the host app would want to know.
    public static func error(_ message: @autoclosure () -> String, _ error: Error? = nil) {
        DyplinkLogger.e(message(), error)
    }

    /// Detail only wanted while diagnosing.
    public static func debug(_ message: @autoclosure () -> String) {
        DyplinkLogger.d(message())
    }

    /// Reports a non-2xx answer to one of the fire-and-forget requests.
    ///
    /// The status goes out at warn level and the body only at debug: the
    /// status alone says the request failed, while the body is the server's
    /// own text and may quote back whatever the app put in the request.
    /// Truncated, because a stack trace or an HTML error page is pages long
    /// and the first line of it is the part that identifies the failure.
    public static func httpFailure(_ what: String, statusCode: Int, body: Data?) {
        warn("\(what) failed: HTTP \(statusCode)")
        guard let body = body, !body.isEmpty,
              let text = String(data: body.prefix(maxLoggedBodyBytes), encoding: .utf8)
        else { return }
        debug("\(what) HTTP \(statusCode) body: \(text)")
    }

    /// Reports a request that never reached the server.
    public static func transportFailure(_ what: String, _ error: Error) {
        warn("\(what) failed: \(error.localizedDescription)")
    }

    private static let maxLoggedBodyBytes = 512
}
