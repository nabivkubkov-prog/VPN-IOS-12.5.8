import Foundation

enum SubscriptionRequest {
    private static let identityKey = "INCY.SubscriptionDeviceID.v1"

    static func deviceID(in defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: identityKey), UUID(uuidString: existing) != nil {
            return existing
        }
        let identifier = UUID().uuidString.lowercased()
        defaults.set(identifier, forKey: identityKey)
        return identifier
    }

    static func headers(deviceID: String, osVersion: String, model: String) -> [String: String] {
        return [
            // Remnawave treats ^INCY/ as supporting full Xray JSON configs.
            // This legacy client imports URI subscriptions, so advertise it separately.
            "User-Agent": "INCY-iOS12/1.0",
            "Accept": "text/plain, application/octet-stream;q=0.9",
            "x-hwid": deviceID,
            "x-device-os": "iOS",
            "x-ver-os": osVersion,
            "x-device-model": model,
        ]
    }
}
