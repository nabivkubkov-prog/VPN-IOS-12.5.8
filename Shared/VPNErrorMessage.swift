import Foundation

enum VPNErrorMessage {
    static func describe(_ error: Error) -> String {
        var current: NSError? = error as NSError
        for _ in 0..<8 {
            guard let failure = current else { break }
            let denied = (failure.domain == "NEConfigurationErrorDomain" && failure.code == 10)
                || (failure.domain == NSPOSIXErrorDomain && [1, 13].contains(failure.code))
                || (failure.domain.hasPrefix("NE") && failure.localizedDescription.lowercased().contains("permission denied"))
            if denied {
                return "iOS запретила настройку VPN. Приложение и VPN-расширение должны быть подписаны с разрешением Network Extensions. Бесплатная подпись Apple ID его не предоставляет."
            }
            current = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return error.localizedDescription
    }
}
