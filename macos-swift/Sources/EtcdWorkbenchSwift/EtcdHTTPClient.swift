import Foundation

@MainActor
final class EtcdHTTPClient {
    private let connection: ConnectionConfig
    private let session: URLSession
    private let delegate: TLSBypassDelegate
    private var authToken: String?

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
        let data = try await request(path: "/version", body: nil, authenticate: true)
        let response = try JSONDecoder().decode(VersionResponse.self, from: data)
        return response.etcdserver
    }

    func list(prefix: String) async throws -> [KeyValueItem] {
        try await listPage(prefix: prefix, cursor: nil, limit: 500).items
    }

    func listPage(prefix: String, cursor: String?, limit: Int) async throws -> KeyListPage {
        let normalizedPrefix = normalizePrefix(prefix)
        let initialStart = normalizedPrefix.isEmpty ? "\0" : namespaced(normalizedPrefix)
        let rangeStart = cursor.map { $0 + "\0" } ?? initialStart
        let rangeEnd = normalizedPrefix.isEmpty ? "\0" : prefixEnd(namespaced(normalizedPrefix))
        let payload = RangeRequest(
            key: encodeKey(rangeStart),
            rangeEnd: encodeKey(rangeEnd),
            limit: limit,
            sortOrder: "ASCEND",
            sortTarget: "KEY"
        )
        let data = try await request(path: "/v3/kv/range", body: payload)
        let response = try JSONDecoder().decode(RangeResponse.self, from: data)
        let items: [KeyValueItem] = response.kvs?.compactMap { kv in
            guard let keyData = Data(base64Encoded: kv.key),
                  let key = String(data: keyData, encoding: .utf8),
                  let value = Data(base64Encoded: kv.value ?? "") else {
                return nil
            }
            return KeyValueItem(
                key: stripNamespace(key),
                rawKey: key,
                value: value,
                createRevision: kv.createRevision ?? "",
                modRevision: kv.modRevision ?? "",
                version: kv.version ?? "",
                lease: kv.lease ?? ""
            )
        } ?? []
        return KeyListPage(
            items: items,
            nextCursor: items.last?.rawKey,
            hasMore: response.more ?? false
        )
    }

    func get(key: String) async throws -> KeyValueItem? {
        let payload = RangeRequest(key: encodeKey(namespaced(key)))
        let data = try await request(path: "/v3/kv/range", body: payload)
        let response = try JSONDecoder().decode(RangeResponse.self, from: data)
        guard let kv = response.kvs?.first,
              let keyData = Data(base64Encoded: kv.key),
              let fullKey = String(data: keyData, encoding: .utf8),
              let value = Data(base64Encoded: kv.value ?? "") else {
            return nil
        }
        return KeyValueItem(
            key: stripNamespace(fullKey),
            rawKey: fullKey,
            value: value,
            createRevision: kv.createRevision ?? "",
            modRevision: kv.modRevision ?? "",
            version: kv.version ?? "",
            lease: kv.lease ?? ""
        )
    }

    func put(key: String, value: String) async throws {
        let request = PutRequest(
            key: encodeKey(namespaced(key)),
            value: Data(value.utf8).base64EncodedString()
        )
        _ = try await self.request(path: "/v3/kv/put", body: request)
    }

    func delete(key: String) async throws {
        let request = DeleteRangeRequest(key: encodeKey(namespaced(key)))
        _ = try await self.request(path: "/v3/kv/deleterange", body: request)
    }

    func rawJSON(path: String, body: EmptyRequest = EmptyRequest()) async throws -> String {
        let data = try await request(path: path, body: body)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return text
    }

    private func request<T: Encodable>(path: String, body: T?) async throws -> Data {
        let payload = try body.map { try JSONEncoder().encode($0) }
        return try await request(path: path, body: payload, authenticate: true)
    }

    private func request(path: String, body: Data?, authenticate: Bool) async throws -> Data {
        guard let baseURL = connection.baseURL,
              let url = URL(string: path, relativeTo: baseURL) else {
            throw AppError.invalidURL
        }

        var request = URLRequest(url: url)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            request.httpMethod = "GET"
        }
        if authenticate, !connection.username.isEmpty {
            let token = try await authenticateIfNeeded()
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let error = try? JSONDecoder().decode(EtcdErrorResponse.self, from: data),
           !error.error.isEmpty {
            throw AppError.etcd(error.error)
        }
        return data
    }

    private func authenticateIfNeeded() async throws -> String {
        if let authToken {
            return authToken
        }

        let payload = try JSONEncoder().encode(AuthRequest(
            name: connection.username,
            password: connection.password
        ))
        let data = try await request(
            path: "/v3/auth/authenticate",
            body: payload,
            authenticate: false
        )
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        authToken = response.token
        return response.token
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

private struct VersionResponse: Decodable {
    let etcdserver: String
}

private struct EtcdErrorResponse: Decodable {
    let error: String
}

struct EmptyRequest: Encodable {}

private struct AuthRequest: Encodable {
    var name: String
    var password: String
}

private struct AuthResponse: Decodable {
    var token: String
}

private struct RangeRequest: Encodable {
    var key: String
    var rangeEnd: String?
    var limit: Int?
    var sortOrder: String?
    var sortTarget: String?

    enum CodingKeys: String, CodingKey {
        case key
        case rangeEnd = "range_end"
        case limit
        case sortOrder = "sort_order"
        case sortTarget = "sort_target"
    }
}

private struct PutRequest: Encodable {
    var key: String
    var value: String
}

private struct DeleteRangeRequest: Encodable {
    var key: String
}

private struct RangeResponse: Decodable {
    var kvs: [KV]?
    var more: Bool?
}

private struct KV: Decodable {
    var key: String
    var value: String?
    var createRevision: String?
    var modRevision: String?
    var version: String?
    var lease: String?

    enum CodingKeys: String, CodingKey {
        case key
        case value
        case createRevision = "create_revision"
        case modRevision = "mod_revision"
        case version
        case lease
    }
}
