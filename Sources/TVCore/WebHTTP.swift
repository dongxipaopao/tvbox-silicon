import Foundation

/// Small HTTP helpers for account checks.
enum WebHTTP {
    static let desktopAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    static let mobileAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private final class Redirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    /// Answers redirects instead of following them.
    static let unredirected = URLSession(configuration: .ephemeral, delegate: Redirects(), delegateQueue: nil)

    static func data(_ url: URL, headers: [String: String] = [:], form: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(desktopAgent, forHTTPHeaderField: "User-Agent")
        if let form {
            request.httpMethod = "POST"
            request.httpBody = Data(form.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TVError.invalidURL }
        guard (200..<300).contains(http.statusCode) else { throw TVError.http(http.statusCode) }
        return (data, http)
    }
    static func text(_ url: URL, headers: [String: String] = [:], form: String? = nil) async throws -> String {
        String(decoding: try await data(url, headers: headers, form: form).0, as: UTF8.self)
    }
    static func json(_ url: URL, headers: [String: String] = [:], form: String? = nil) async throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: try await data(url, headers: headers, form: form).0)
    }
    static func url(_ base: String, _ query: [(String, String)]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        // `+` is a space to these servers; URLComponents leaves it as is.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}
