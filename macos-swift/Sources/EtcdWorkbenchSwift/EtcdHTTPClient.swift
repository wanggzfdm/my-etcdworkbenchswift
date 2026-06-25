import Foundation

@MainActor
final class EtcdHTTPClient {
    private let connection: ConnectionConfig
    private let session: URLSession
    private let delegate: TLSBypassDelegate
    private var authToken: String?
    private var isAuthenticating = false

    init(connection: ConnectionConfig) {
        self.connection = connection
        self.delegate = TLSBypassDelegate(skipTLSVerify: connection.useTLS && connection.skipTLSVerify)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func version() async throws -> String {
        if !connection.username.isEmpty {
            _ = try await authenticateIfNeeded()
        }
        let data = try await requestData(path: "/version", body: nil)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "unknown"
        }
        // 灵活获取etcdserver字段
        if let version = json["etcdserver"] as? String {
            return version
        } else if let version = json["etcdserver"] as? Double {
            return String(version)
        } else if let version = json["etcdserver"] as? Int {
            return String(version)
        }
        return "unknown"
    }

    func list(prefix: String) async throws -> [KeyValueItem] {
        try await listPage(prefix: prefix, cursor: nil, limit: 500).items
    }

    func listPage(prefix: String, cursor: String?, limit: Int) async throws -> KeyListPage {
        let normalizedPrefix = normalizePrefix(prefix)
        let initialStart = normalizedPrefix.isEmpty ? "\0" : namespaced(normalizedPrefix)
        let rangeStart = cursor.map { $0 + "\0" } ?? initialStart
        let rangeEnd = normalizedPrefix.isEmpty ? "\0" : prefixEnd(namespaced(normalizedPrefix))
        let payload: [String: Any] = [
            "key": encodeKey(rangeStart),
            "range_end": encodeKey(rangeEnd),
            "limit": limit,
            "sort_order": "ASCEND",
            "sort_target": "KEY"
        ]
        let data = try await requestJSON(path: "/v3/kv/range", body: payload)
        let items = parseKVs(from: data)
        let hasMore = data["more"] as? Bool ?? false
        return KeyListPage(
            items: items,
            nextCursor: items.last?.rawKey,
            hasMore: hasMore
        )
    }

    func search(prefix: String, cursor: String?, limit: Int) async throws -> SearchResult {
        let normalizedPrefix = normalizePrefix(prefix)
        guard !normalizedPrefix.isEmpty else {
            return SearchResult(items: [], totalCount: 0, hasMore: false, nextCursor: nil)
        }

        let rangeStart = cursor.map { $0 + "\0" } ?? namespaced(normalizedPrefix)
        let rangeEnd = prefixEnd(namespaced(normalizedPrefix))

        let payload: [String: Any] = [
            "key": encodeKey(rangeStart),
            "range_end": encodeKey(rangeEnd),
            "limit": limit,
            "sort_order": "ASCEND",
            "sort_target": "KEY"
        ]

        let data = try await requestJSON(path: "/v3/kv/range", body: payload)
        let items = parseKVs(from: data)
        let hasMore = data["more"] as? Bool ?? false
        let count = parseInt(data["count"])

        return SearchResult(
            items: items,
            totalCount: count,
            hasMore: hasMore,
            nextCursor: items.last?.rawKey
        )
    }

    func get(key: String) async throws -> KeyValueItem? {
        let payload: [String: Any] = ["key": encodeKey(namespaced(key))]
        let data = try await requestJSON(path: "/v3/kv/range", body: payload)
        let items = parseKVs(from: data)
        return items.first
    }

    func put(key: String, value: String) async throws {
        let payload: [String: Any] = [
            "key": encodeKey(namespaced(key)),
            "value": Data(value.utf8).base64EncodedString()
        ]
        _ = try await requestJSON(path: "/v3/kv/put", body: payload)
    }

    func delete(key: String) async throws {
        let payload: [String: Any] = ["key": encodeKey(namespaced(key))]
        _ = try await requestJSON(path: "/v3/kv/deleterange", body: payload)
    }

    func rawJSON(path: String, body: [String: Any] = [:]) async throws -> String {
        let data = try await requestData(path: path, body: body.isEmpty ? nil : body)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return text
    }

    // MARK: - JSON解析辅助方法

    private func parseKVs(from json: [String: Any]) -> [KeyValueItem] {
        guard let kvs = json["kvs"] as? [[String: Any]] else {
            return []
        }
        return kvs.compactMap { parseKV(from: $0) }
    }

    private func parseKV(from dict: [String: Any]) -> KeyValueItem? {
        guard let keyBase64 = dict["key"] as? String,
              let keyData = Data(base64Encoded: keyBase64),
              let key = String(data: keyData, encoding: .utf8) else {
            return nil
        }

        let valueBase64 = dict["value"] as? String ?? ""
        let value = Data(base64Encoded: valueBase64) ?? Data()

        return KeyValueItem(
            key: stripNamespace(key),
            rawKey: key,
            value: value,
            createRevision: "\(parseInt(dict["create_revision"]))",
            modRevision: "\(parseInt(dict["mod_revision"]))",
            version: "\(parseInt(dict["version"]))",
            lease: "\(parseInt(dict["lease"]))"
        )
    }

    private func parseInt(_ value: Any?) -> Int {
        if let i = value as? Int {
            return i
        }
        if let d = value as? Double {
            return Int(d)
        }
        if let s = value as? String, let i = Int(s) {
            return i
        }
        return 0
    }

    // MARK: - 网络请求

    private func requestJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        let data = try await requestData(path: path, body: body)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AppError.invalidResponse
        }
        // 检查etcd错误
        if let error = json["error"] as? String, !error.isEmpty {
            throw AppError.etcd(error)
        }
        return json
    }

    private func requestData(path: String, body: [String: Any]?) async throws -> Data {
        guard let baseURL = connection.baseURL,
              let url = URL(string: path, relativeTo: baseURL) else {
            throw AppError.invalidURL
        }

        // 带有自动重试的请求（处理 token 过期）
        return try await performRequest(url: url, body: body, shouldRetryOnAuthError: true)
    }

    /// 执行 HTTP 请求，当遇到 auth token 过期时自动重试一次
    private func performRequest(url: URL, body: [String: Any]?, shouldRetryOnAuthError: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            request.httpMethod = "GET"
        }
        if !connection.username.isEmpty && !isAuthenticating {
            let token = try await authenticateIfNeeded()
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        // 检查是否为 auth token 过期错误（HTTP 401）
        if http.statusCode == 401 && shouldRetryOnAuthError {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if bodyText.contains("invalid auth token") {
                NSLog("[EtcdHTTPClient] Auth token expired, clearing cache and retrying...")
                // 清除过期的 token
                authToken = nil
                // 重新认证并重试请求（只重试一次）
                if !connection.username.isEmpty {
                    _ = try await authenticateIfNeeded()
                    return try await performRequest(url: url, body: body, shouldRetryOnAuthError: false)
                }
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AppError.httpStatus(http.statusCode, bodyText)
        }
        // 调试日志：打印非 JSON 响应信息
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        if !contentType.contains("json") {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            NSLog("[EtcdHTTPClient] Non-JSON response — Content-Type: %@, body preview: %@", contentType, preview)
        }

        return data
    }

    /// 认证请求（不经过重试逻辑，避免无限递归）
    private func authenticateIfNeeded() async throws -> String {
        if let authToken {
            return authToken
        }

        guard let baseURL = connection.baseURL,
              let url = URL(string: "/v3/auth/authenticate", relativeTo: baseURL) else {
            throw AppError.invalidURL
        }

        let payload: [String: Any] = [
            "name": connection.username,
            "password": connection.password
        ]
        isAuthenticating = true
        defer { isAuthenticating = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AppError.etcd("认证失败")
        }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = json["token"] as? String else {
            throw AppError.etcd("认证失败")
        }
        authToken = token
        return token
    }

    private func namespaced(_ key: String) -> String {
        guard !connection.namespace.isEmpty else { return key }
        let namespace = connection.namespace.hasSuffix("/") ? connection.namespace : connection.namespace + "/"
        return namespace + key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func normalizePrefix(_ prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "/" ? "" : trimmed
    }

    private func stripNamespace(_ key: String) -> String {
        guard !connection.namespace.isEmpty else { return key }
        let namespace = connection.namespace.hasSuffix("/") ? connection.namespace : connection.namespace + "/"
        if key.hasPrefix(namespace) {
            return String(key.dropFirst(namespace.count))
        }
        return key
    }

    private func encodeKey(_ key: String) -> String {
        Data(key.utf8).base64EncodedString()
    }

    private func prefixEnd(_ prefix: String) -> String {
        guard !prefix.isEmpty else { return "\0" }
        var bytes = Array(prefix.utf8)
        for index in stride(from: bytes.count - 1, through: 0, by: -1) {
            if bytes[index] < 0xff {
                bytes[index] += 1
                return String(decoding: bytes.prefix(index + 1), as: UTF8.self)
            }
        }
        return "\0"
    }
}

// MARK: - 网络相关

private final class TLSBypassDelegate: NSObject, URLSessionDelegate {
    private let skipTLSVerify: Bool

    init(skipTLSVerify: Bool) {
        self.skipTLSVerify = skipTLSVerify
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard skipTLSVerify,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
