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
}
