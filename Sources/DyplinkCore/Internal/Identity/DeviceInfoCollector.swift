import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Collects device-level information from UIKit and Foundation.
///
/// Mirrors the Android `DeviceInfoCollector`. Payload keys match the
/// Android version so server-side code can merge identify/event
/// payloads from both platforms without special-casing.
internal final class DeviceInfoCollector {

    func collect() -> [String: Any] {
        let locale = Locale.current
        let timezone = TimeZone.current

        var info: [String: Any] = [
            "os": "iOS",
            "osVersion": osVersion(),
            "manufacturer": "Apple",
            "brand": "Apple",
            "model": deviceModel(),
            "screenWidth": screenSize().width,
            "screenHeight": screenSize().height,
            "carrier": "",
            "locale": locale.identifier,
            "language": languageCode(from: locale),
            "timezone": timezone.identifier,
        ]

        if let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            info["appVersion"] = appVersion
        }
        if let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            info["appBuild"] = appBuild
        }

        return info
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private func osVersion() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { ident, element in
            guard let value = element.value as? Int8, value != 0 else { return ident }
            return ident + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    private func screenSize() -> (width: Int, height: Int) {
        #if canImport(UIKit)
        let scale = UIScreen.main.scale
        let bounds = UIScreen.main.bounds
        return (Int(bounds.width * scale), Int(bounds.height * scale))
        #else
        return (0, 0)
        #endif
    }

    private func languageCode(from locale: Locale) -> String {
        if #available(iOS 16, *) {
            return locale.language.languageCode?.identifier ?? ""
        } else {
            return locale.languageCode ?? ""
        }
    }
}
