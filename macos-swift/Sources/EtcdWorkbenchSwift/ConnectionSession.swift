import Foundation

/// 代表一个已打开的连接会话。每个 Tab 对应一个 ConnectionSession，
/// 持有自己独立的 client、键列表、选中键和编辑器状态，互不干扰。
@MainActor
final class ConnectionSession: ObservableObject, Identifiable {
    let config: ConnectionConfig
    nonisolated var id: UUID { config.id }

    @Published var items: [KeyValueItem] = []
    @Published var selectedKey: String?
    @Published var editorText: String = ""
    @Published var rawEditorText: String = ""
    @Published var status: String = "未连接"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var activeConnectionName: String?
    @Published var canLoadMore = false

    private var client: EtcdHTTPClient?
    private var nextCursor: String?
    private var activePrefix = ""
    private let pageSize = 500

    init(config: ConnectionConfig) {
        self.config = config
    }

    var isConnected: Bool {
        client != nil
    }

    var selectedItem: KeyValueItem? {
        guard let selectedKey else { return nil }
        return items.first { $0.key == selectedKey }
    }

    func connect(prefix: String = "") async {
        await run {
            let client = EtcdHTTPClient(connection: self.config)
            let version = try await client.version()
            self.client = client
            self.activeConnectionName = self.config.name
            self.status = "已连接到 \(self.config.name) · etcd \(version)"
            try await self.reload(prefix: prefix)
        }
    }

    func reload(prefix: String) async throws {
        guard let client else { throw AppError.missingConnection }
        activePrefix = prefix
        let page = try await client.listPage(prefix: prefix, cursor: nil, limit: pageSize)
        items = page.items
        nextCursor = page.nextCursor
        canLoadMore = page.hasMore
        if let selectedKey, let item = items.first(where: { $0.key == selectedKey }) {
            applyEditorValue(item)
        } else {
            selectedKey = items.first?.key
            if let item = items.first {
                applyEditorValue(item)
            } else {
                rawEditorText = ""
                editorText = ""
            }
        }
    }

    func select(_ item: KeyValueItem?) {
        selectedKey = item?.key
        if let item {
            applyEditorValue(item)
        } else {
            rawEditorText = ""
            editorText = ""
        }
    }

    func saveSelected() async {
        await run {
            guard let key = self.selectedKey else { throw AppError.missingConnection }
            try await self.client?.put(key: key, value: self.editorText)
            try await self.reload(prefix: "")
            self.status = "已保存 \(key)"
        }
    }

    func create(key: String, value: String) async {
        await run {
            guard let client = self.client else { throw AppError.missingConnection }
            try await client.put(key: key, value: value)
            try await self.reload(prefix: "")
            self.selectedKey = key
            self.rawEditorText = value
            self.editorText = Self.formattedPreview(value)
            self.status = "已创建 \(key)"
        }
    }

    func deleteSelected() async {
        await run {
            guard let key = self.selectedKey,
                  let client = self.client else { throw AppError.missingConnection }
            try await client.delete(key: key)
            try await self.reload(prefix: "")
            self.status = "已删除 \(key)"
        }
    }

    func loadPrefix(_ prefix: String) async {
        await run {
            try await self.reload(prefix: prefix)
            self.status = self.canLoadMore
                ? "已加载前 \(self.items.count) 个键"
                : "已加载 \(self.items.count) 个键"
        }
    }

    func loadMore() async {
        await run {
            guard let client = self.client else { throw AppError.missingConnection }
            guard let nextCursor = self.nextCursor, self.canLoadMore else { return }
            let page = try await client.listPage(
                prefix: self.activePrefix,
                cursor: nextCursor,
                limit: self.pageSize
            )
            self.items.append(contentsOf: page.items)
            self.nextCursor = page.nextCursor
            self.canLoadMore = page.hasMore
            self.status = self.canLoadMore
                ? "已加载 \(self.items.count) 个键，还有更多"
                : "已加载全部 \(self.items.count) 个键"
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            if client == nil {
                activeConnectionName = nil
            }
            status = "错误"
        }
    }

    private func applyEditorValue(_ item: KeyValueItem) {
        rawEditorText = item.textValue
        editorText = Self.formattedPreview(item.textValue)
    }

    private static func formattedPreview(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return text
        }
        return pretty
    }
}
