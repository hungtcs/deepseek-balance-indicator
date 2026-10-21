import Foundation

enum DeepSeekError: LocalizedError {
    case missingAPIKey
    case unauthorized
    case http(status: Int, message: String?)
    case decoding
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未设置 API Key，请在“设置”中填写"
        case .unauthorized:
            return "API Key 无效或已过期（401）"
        case let .http(status, message):
            if let message, !message.isEmpty { return "请求失败（HTTP \(status)）：\(message)" }
            return "请求失败（HTTP \(status)）"
        case .decoding:
            return "接口返回内容无法解析"
        case let .network(message):
            return "网络错误：\(message)"
        }
    }
}

struct DeepSeekClient {
    static let defaultEndpoint = URL(string: "https://api.deepseek.com/user/balance")!

    var apiKey: String
    var session: URLSession = .shared
    /// Overridable so `--self-test` can run against a local stub.
    var endpoint: URL = DeepSeekClient.defaultEndpoint

    func fetchBalance() async throws -> BalanceResponse {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepSeekError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DeepSeekError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.network("无效的响应")
        }
        if http.statusCode == 401 { throw DeepSeekError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }

        do {
            return try JSONDecoder().decode(BalanceResponse.self, from: data)
        } catch {
            throw DeepSeekError.decoding
        }
    }

    /// Pulls `{"error": {"message": "..."}}` out of an error body when present.
    private static func errorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
    }
}
