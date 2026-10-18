import Foundation

/// A failed SDK API call.
public struct BrudcastApiError: Error, CustomStringConvertible {
    public let statusCode: Int?
    public let code: String?
    public let message: String

    public init(statusCode: Int?, code: String?, message: String) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
    }

    /// True when the request never got a response, so retrying later may succeed.
    public var isNetwork: Bool { statusCode == nil }

    /// True for a failure worth retrying: no response, 408, 429 or any 5xx. A body that could not
    /// be encoded never is, since it would fail the same way again.
    public var isRetryable: Bool {
        guard let status = statusCode else { return code != "encoding" }
        return status == 408 || status == 429 || status >= 500
    }

    public var description: String {
        if let status = statusCode {
            return "HTTP \(status)\(code.map { " \($0)" } ?? ""): \(message)"
        }
        return message
    }
}

/// An HTTP method the SDK API uses.
public enum BrudcastHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Calls the SDK API and unwraps its `{ status, message, data }` envelope.
public final class BrudcastApiClient {
    public let baseURL: URL
    let publishableKey: String
    let session: URLSession

    init(baseURL: URL, publishableKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.publishableKey = publishableKey
        self.session = session
    }

    /// Builds the URL of a path under the SDK API.
    ///
    /// - Parameters:
    ///   - path: The path after `/sdk/v1`, such as `/messages`.
    ///   - query: Query parameters to append.
    /// - Returns: The URL.
    public func url(_ path: String, query: [String: String] = [:]) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(url: baseURL.appendingPathComponent(trimmed), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    /// Sends a request and returns the envelope's `data`.
    ///
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - path: The path after `/sdk/v1`.
    ///   - query: Query parameters.
    ///   - body: A JSON object to send, or nil.
    ///   - token: The session token, or nil for the session-opening call.
    ///   - completion: Called with the decoded `data` object, or the error.
    public func send(
        _ method: BrudcastHTTPMethod,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        token: String? = nil,
        completion: @escaping (Result<[String: Any], BrudcastApiError>) -> Void
    ) {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method.rawValue
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(BrudcastSDK.userAgent, forHTTPHeaderField: "User-Agent")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(publishableKey, forHTTPHeaderField: "X-Brudcast-Key")
        }
        if let body = body {
            guard JSONSerialization.isValidJSONObject(body) else {
                completion(.failure(BrudcastApiError(statusCode: nil, code: "encoding", message: "The request body is not valid JSON")))
                return
            }
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                completion(.failure(BrudcastApiError(statusCode: nil, code: "encoding", message: "The request body could not be encoded")))
                return
            }
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(BrudcastApiError(statusCode: nil, code: nil, message: error.localizedDescription)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(Self.decode(status: status, data: data))
        }.resume()
    }

    static func decode(status: Int, data: Data?) -> Result<[String: Any], BrudcastApiError> {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0, options: []) } as? [String: Any]
        if (200..<300).contains(status) {
            if let payload = object?["data"] as? [String: Any] {
                return .success(payload)
            }
            return .success([:])
        }
        let message = object?["message"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: status)
        return .failure(BrudcastApiError(statusCode: status, code: object?["code"] as? String, message: message))
    }
}
