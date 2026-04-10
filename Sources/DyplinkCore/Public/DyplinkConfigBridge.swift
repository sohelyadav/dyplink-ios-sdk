import Foundation

/// Shared config registry for optional modules (Push, Banners, Messages).
///
/// Mirrors `com.dyplink.sdk.DyplinkConfigBridge` on Android. The main
/// `Dyplink` singleton populates these statics on `initialize(config:)`
/// so optional modules don't need a reference to the singleton itself.
public enum DyplinkConfigBridge {
    nonisolated(unsafe) public static var baseUrl: String = ""
    nonisolated(unsafe) public static var apiKey: String = ""
    nonisolated(unsafe) public static var projectId: String = ""
    nonisolated(unsafe) public static var deviceFingerprint: String = ""
    nonisolated(unsafe) public static var distinctId: String = ""
}
