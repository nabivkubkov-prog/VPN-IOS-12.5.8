import Foundation

enum SubscriptionResponse {
    static let maximumBytes = 1_048_576

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProfileError.invalid("Не удалось получить HTTP-ответ сервера подписки.")
        }
        switch http.statusCode {
        case 200: break
        case 401, 403:
            throw ProfileError.invalid("Нет доступа к подписке (HTTP \(http.statusCode)). Проверьте адрес и срок действия подписки.")
        case 404:
            throw ProfileError.invalid("Подписка не найдена (HTTP 404). Проверьте адрес подписки.")
        default:
            throw ProfileError.invalid("Ошибка загрузки подписки (HTTP \(http.statusCode)). Повторите попытку позже.")
        }
        if http.value(forHTTPHeaderField: "x-hwid-not-supported")?.lowercased() == "true" {
            throw ProfileError.invalid(serviceNotice("App not supported"))
        }
        if http.value(forHTTPHeaderField: "x-hwid-max-devices-reached")?.lowercased() == "true" {
            throw ProfileError.invalid(serviceNotice("Limit of devices reached"))
        }
        if response.expectedContentLength > Int64(maximumBytes) {
            throw ProfileError.invalid("Полученный список серверов превышает 1 МБ.")
        }
    }

    static func append(_ data: Data, to bytes: inout Data) throws {
        guard bytes.count <= maximumBytes && data.count <= maximumBytes - bytes.count else {
            throw ProfileError.invalid("Полученный список серверов превышает 1 МБ.")
        }
        bytes.append(data)
    }

    static func serviceNotice(_ name: String) -> String {
        let notice = name.lowercased()
        if notice.contains("app not supported") {
            return "Сервис подписки не принял идентификатор устройства (App not supported). Обновите INCY и повторите импорт личной ссылки подписки."
        }
        if notice.contains("limit of devices reached") {
            return "Достигнут лимит устройств подписки. Проверьте список устройств в боте или личном кабинете VPN-сервиса."
        }
        if notice.contains("subscription expired") { return "Срок действия подписки истёк. Продлите её в VPN-сервисе." }
        if notice.contains("subscription disabled") { return "Подписка отключена. Проверьте её состояние в VPN-сервисе." }
        if notice.contains("subscription limited") { return "Подписка ограничена. Проверьте её состояние в VPN-сервисе." }
        return "Подписка вернула служебное сообщение вместо сервера. Проверьте её состояние в VPN-сервисе."
    }
}
