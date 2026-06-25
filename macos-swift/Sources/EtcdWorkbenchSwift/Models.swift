import Foundation

struct ConnectionConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var namespace: String
    var username: String
    var password: String
    var useTLS: Bool
    var skipTLSVerify: Bool
    var keyPrefix: String

    var baseURL: URL? {
        var components = URLComponents()
        components.scheme = useTLS ? "https" : "http"
        components.host = host
        components.port = port
        return components.url
    }

    static let empty = ConnectionConfig(
        id: UUID(),
        name: "本地 etcd",
        host: "127.0.0.1",
        port: 2379,
        namespace: "",
        username: "",
        password: "",
        useTLS: false,
        skipTLSVerify: false,
        keyPrefix: ""
    )
}

struct KeyValueItem: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var rawKey: String
    var value: Data
    var createRevision: String
    var modRevision: String
    var version: String
    var lease: String

    var textValue: String {
        String(data: value, encoding: .utf8) ?? "<binary \(value.count) bytes>"
    }
}

struct KeyListPage {
    var items: [KeyValueItem]
    var nextCursor: String?
    var hasMore: Bool
}

/// 服务端搜索结果
struct SearchResult {
    var items: [KeyValueItem]
    var totalCount: Int
    var hasMore: Bool
    var nextCursor: String?
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var selectedConnectionID: UUID?
    var keyPrefix: String
    var theme: AppTheme

    static let `default` = AppSettings(selectedConnectionID: nil, keyPrefix: "", theme: .system)

    enum CodingKeys: String, CodingKey {
        case selectedConnectionID
        case keyPrefix
        case theme
    }

    init(selectedConnectionID: UUID?, keyPrefix: String, theme: AppTheme = .system) {
        self.selectedConnectionID = selectedConnectionID
        self.keyPrefix = keyPrefix
        self.theme = theme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedConnectionID = try container.decodeIfPresent(UUID.self, forKey: .selectedConnectionID)
        keyPrefix = try container.decodeIfPresent(String.self, forKey: .keyPrefix) ?? ""
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
    }
}

enum AppError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case etcd(String)
    case missingConnection

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "连接地址无效。"
        case .invalidResponse:
            return "etcd 返回了非 JSON 格式的数据，请确认端口和协议设置是否正确。"
        case .httpStatus(let code, let body):
            return "HTTP \(code): \(body)"
        case .etcd(let message):
            return message
        case .missingConnection:
            return "请先选择或创建一个连接。"
        }
    }
}
