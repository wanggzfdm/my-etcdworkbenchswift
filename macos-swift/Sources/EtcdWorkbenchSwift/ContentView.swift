import SwiftUI
import AppKit

private struct TestResult {
    var message: String
    var icon: String
    var color: Color
}

private enum WorkbenchPage: String, CaseIterable, Identifiable {
    case keys
    case cluster
    case leases
    case users
    case roles
    case keyMonitor
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keys: return "键"
        case .cluster: return "集群"
        case .leases: return "租约"
        case .users: return "用户"
        case .roles: return "角色"
        case .keyMonitor: return "键监听"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .keys: return "key"
        case .cluster: return "server.rack"
        case .leases: return "timer"
        case .users: return "person.2"
        case .roles: return "lock.shield"
        case .keyMonitor: return "dot.radiowaves.left.and.right"
        case .settings: return "gearshape"
        }
    }

    var summary: String {
        switch self {
        case .keys:
            return "浏览和编辑 etcd 键值数据。"
        case .cluster:
            return "查看集群成员和端点状态。"
        case .leases:
            return "查看租约 ID 和租约元数据。"
        case .users:
            return "查看认证用户。"
        case .roles:
            return "查看认证角色。"
        case .keyMonitor:
            return "键监听配置后续会迁移到这里。"
        case .settings:
            return "应用偏好设置和本地存储。"
        }
    }
}

private struct ModuleOverview: View {
    var page: WorkbenchPage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(page.title, systemImage: page.icon)
                .font(.title3.weight(.semibold))
            Text(page.summary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(24)
    }
}

private struct RawEtcdAction: Identifiable {
    var id: String { endpoint }
    var title: String
    var endpoint: String
}

private struct RawEtcdPage: View {
    var title: String
    var subtitle: String
    var connection: ConnectionConfig?
    var actions: [RawEtcdAction]

    @State private var selectedAction: RawEtcdAction?
    @State private var output = "请选择一个操作来加载数据。"
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ForEach(actions) { action in
                    Button {
                        Task { await load(action) }
                    } label: {
                        Label(action.title, systemImage: "arrow.down.doc")
                    }
                    .disabled(connection == nil || isLoading)
                }
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
            Divider()
            TextEditor(text: $output)
                .font(.system(.body, design: .monospaced))
                .padding(8)
        }
    }

    private func load(_ action: RawEtcdAction) async {
        guard let connection else {
            output = "请先选择一个连接。"
            return
        }

        isLoading = true
        selectedAction = action
        defer { isLoading = false }

        do {
            output = try await EtcdHTTPClient(connection: connection).rawJSON(path: action.endpoint)
        } catch {
            output = error.localizedDescription
        }
    }
}

private struct KeyMonitorPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("键监听", systemImage: "dot.radiowaves.left.and.right")
                .font(.title3.weight(.semibold))
            Text("Vue 版的键监听页面后续会迁移到这里。这里需要长连接 watch 流、本地监听配置和通知界面。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ContentUnavailableView("尚未实现", systemImage: "dot.radiowaves.left.and.right")
            Spacer()
        }
        .padding(24)
    }
}

private struct SettingsPage: View {
    @ObservedObject var store: ConnectionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("设置", systemImage: "gearshape")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("外观")
                    .font(.headline)
                Picker("主题", selection: Binding(
                    get: { store.settings.theme },
                    set: { theme in
                        store.settings.theme = theme
                        store.saveSettings()
                    }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                Text("跟随系统会使用当前 macOS 外观；浅色和深色会覆盖本应用外观。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.quaternary.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("搜索")
                    .font(.headline)
                HStack {
                    Text("自动展开阈值")
                    TextField("", value: Binding(
                        get: { store.settings.searchExpandThreshold },
                        set: { store.settings.searchExpandThreshold = $0 }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("个键")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("搜索结果数量 ≤ 此值时自动展开目录树，设为 0 则始终折叠。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.quaternary.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("本地存储")
                    .font(.headline)
                Text("~/Library/Application Support/Etcd Workbench Swift/")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("连接数：\(store.connections.count)")
                Text("主题：\(store.settings.theme.title)")
            }
            .padding()
            .background(.quaternary.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
        }
        .padding(24)
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var editingConnection: ConnectionConfig?
    @State private var showingNewKey = false
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var noticeMessage: String?
    @State private var showingSettings = false
    @State private var showingConnectionPicker = false

    var body: some View {
        mainWorkspace
    }

    private var mainWorkspace: some View {
        VStack(spacing: 0) {
            WorkspaceTabBar(workspace: viewModel, onNewTab: {
                showingConnectionPicker = true
            }, onGoHome: {
                viewModel.showHome = true
            })
            Divider()
            if !viewModel.showHome, viewModel.activeSession != nil {
                // 用 HSplitView 而非 NavigationSplitView：纯左右分栏，没有折叠按钮和折叠动画，
                // 从源头规避 NSOutlineView 在分栏折叠时逐帧重排导致的卡顿。保留拖拽调宽。
                HSplitView {
                    middlePane
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 460)
                    detailPane
                        .frame(minWidth: 400, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 首页或无打开会话时，内容区铺满显示连接选择界面。
                ConnectionListView(
                    onOpen: { openConnection($0) },
                    onNew: { showConnectionEditor(ConnectionConfig.empty.withNewID()) },
                    onEdit: { showConnectionEditor($0) },
                    onOpenSettings: { showingSettings = true }
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let noticeMessage {
                Text(noticeMessage)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.quaternary)
                    }
                    .shadow(radius: 12)
                    .padding(24)
            }
        }
        .sheet(isPresented: $showingNewKey) {
            NewKeySheet(key: $newKey, value: $newValue) {
                let key = newKey
                let value = newValue
                newKey = ""
                newValue = ""
                showingNewKey = false
                if let session = viewModel.activeSession {
                    Task { await session.create(key: key, value: value) }
                }
            }
        }
        .sheet(item: $editingConnection) { connection in
            ConnectionEditor(
                connection: connection,
                onCancel: closeConnectionEditor
            ) { updated in
                saveConnection(updated)
            }
            .frame(minWidth: 520, minHeight: 480)
            .padding(24)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(store: store) { showingSettings = false }
        }
        .sheet(isPresented: $showingConnectionPicker) {
            ConnectionPickerSheet(
                onOpen: { connection in
                    showingConnectionPicker = false
                    openConnection(connection)
                },
                onNew: {
                    showingConnectionPicker = false
                    showConnectionEditor(ConnectionConfig.empty.withNewID())
                },
                onEdit: { connection in
                    showingConnectionPicker = false
                    showConnectionEditor(connection)
                },
                onClose: { showingConnectionPicker = false }
            )
            .environmentObject(store)
        }
    }

    // 两栏布局下，detail 栏固定显示当前会话键的值预览/编辑。
    @ViewBuilder
    private var detailPane: some View {
        if let session = viewModel.activeSession {
            EditorPane(session: session, onNotice: showNotice)
        } else {
            ContentUnavailableView(
                "请打开一个连接",
                systemImage: "bolt.horizontal",
                description: Text("从左侧连接列表选择一个连接以开始查询键值。")
            )
        }
    }

    // 两栏布局：左栏为键目录树，右栏为值预览/编辑。
    // 连接管理已移至独立的连接列表页（启动页），不再常驻左栏。
    private var middlePane: some View {
        keyTreeSection
    }

    @ViewBuilder
    private var keyTreeSection: some View {
        if let session = viewModel.activeSession {
            KeyTreePane(
                session: session,
                keyPrefix: Binding(
                    get: { session.activePrefix ?? "" },
                    set: { _ in }
                ),
                expandAll: session.isSearchMode && session.searchResults.count <= store.settings.searchExpandThreshold,
                onNewKey: { showingNewKey = true },
                onRefresh: {
                    Task { await session.loadPrefix(session.activePrefix ?? "") }
                }
            )
        } else {
            List {
                ContentUnavailableView(
                    "请打开一个连接",
                    systemImage: "bolt.horizontal"
                )
            }
            .listStyle(.sidebar)
        }
    }

    private func showConnectionEditor(_ connection: ConnectionConfig) {
        // 若当前有 picker sheet 正在关闭，稍作延迟再弹出编辑器，避免两个 sheet 的
        // present/dismiss 动画冲突导致编辑器 sheet 不弹出。
        if editingConnection != nil {
            editingConnection = connection
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            editingConnection = connection
        }
    }

    private func closeConnectionEditor() {
        editingConnection = nil
    }

    private func saveConnection(_ connection: ConnectionConfig) {
        store.upsert(connection)
        closeConnectionEditor()
        showNotice("已保存连接「\(connection.name)」")
    }

    private func openConnection(_ connection: ConnectionConfig) {
        store.selectedConnection = connection
        closeConnectionEditor()
        viewModel.openSession(connection, prefix: connection.keyPrefix)
    }

    private func showNotice(_ message: String) {
        noticeMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if noticeMessage == message {
                noticeMessage = nil
            }
        }
    }
}

// MARK: - 键目录树面板（观察单个会话）

private struct KeyTreePane: View {
    @ObservedObject var session: ConnectionSession
    @Binding var keyPrefix: String
    var expandAll: Bool
    var onNewKey: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        let visibleItems = filteredKeyItems
        let outlineNodes = KeyOutlineBuilder.build(items: visibleItems)

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("前缀")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("/", text: $keyPrefix)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                    .help("在连接设置中配置前缀")

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!session.isConnected || session.isLoading)
                .help("按前缀加载/刷新")

                Button {
                    onNewKey()
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!session.isConnected)
                .help("新增键")

                if session.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索键（前缀匹配）", text: $session.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        // 回车触发搜索
                        performServerSearch()
                    }

                if !session.searchQuery.isEmpty {
                    Button {
                        session.searchQuery = ""
                        session.exitSearchMode()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Button {
                    performServerSearch()
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(session.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isSearching)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            HStack {
                if session.isSearchMode {
                    Text("搜索结果: \(session.searchResults.count) / \(session.searchTotalCount) 个键")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(visibleItems.count) / \(session.items.count) loaded keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if session.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if session.isSearchMode && session.searchHasMore {
                    Button("加载更多") {
                        Task {
                            await session.loadMoreSearchResults()
                        }
                    }
                    .font(.caption)
                } else if !session.isSearchMode && session.canLoadMore {
                    Text("还有更多")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if outlineNodes.isEmpty {
                List {
                    ContentUnavailableView(
                        session.isSearchMode ? "没有匹配的键" : (session.isConnected ? "没有已加载的键" : "请打开一个连接"),
                        systemImage: session.isSearchMode ? "magnifyingglass" : (session.isConnected ? "folder" : "bolt.horizontal")
                    )
                }
                .listStyle(.sidebar)
            } else {
                // 方案B：用 AppKit 的 NSOutlineView 获得原生 Finder 式展开动画。
                KeyOutlineView(
                    nodes: outlineNodes,
                    selectedKey: session.selectedKey,
                    expandAll: expandAll,
                    onSelect: { selectKey($0) },
                    onCopy: { key in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(key, forType: .string)
                    },
                    onCopyValue: { item in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.textValue, forType: .string)
                    },
                    onRefreshKey: { key in
                        Task { await session.refreshKey(key) }
                    }
                )
            }

            if !session.isSearchMode && session.canLoadMore {
                Divider()
                Button {
                    Task { await session.loadMore() }
                } label: {
                    Label("加载更多", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(10)
                .disabled(session.isLoading)
            }
        }
    }

    private var filteredKeyItems: [KeyValueItem] {
        if session.isSearchMode {
            return session.searchResults
        }
        let query = session.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return session.items }
        return session.items.filter { item in
            item.key.localizedCaseInsensitiveContains(query) ||
            item.textValue.localizedCaseInsensitiveContains(query)
        }
    }

    private func selectKey(_ key: String) {
        let items = session.isSearchMode ? session.searchResults : session.items
        guard let item = items.first(where: { $0.key == key }) else { return }
        session.select(item)
    }

    private func performServerSearch() {
        let query = session.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        session.searchQuery = query
        Task {
            await session.search(prefix: query)
        }
    }
}

// MARK: - 值预览/编辑面板（观察单个会话）

private struct EditorPane: View {
    @ObservedObject var session: ConnectionSession
    var onNotice: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(session.selectedKey ?? "未选择键")
                        .font(.headline)
                    Text(session.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyKey()
                } label: {
                    Label("复制键", systemImage: "doc.on.clipboard")
                }
                .disabled(session.selectedKey == nil)
                Button {
                    copyRawValue()
                } label: {
                    Label("复制原始值", systemImage: "doc.on.doc")
                }
                .disabled(session.selectedKey == nil || session.rawEditorText.isEmpty)
                Button(role: .destructive) {
                    Task { await session.deleteSelected() }
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(session.selectedKey == nil || session.isLoading)
                Button {
                    Task { await session.saveSelected() }
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.selectedKey == nil || session.isLoading)
            }
            .padding()
            Divider()
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.quaternary)
                    }

                TextEditor(text: $session.editorText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(12)
            }
            .padding(12)
        }
        .alert("Etcd Workbench", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private func copyRawValue() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.rawEditorText, forType: .string)
        onNotice("已复制原始值")
    }

    private func copyKey() {
        guard let key = session.selectedKey else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        onNotice("已复制键：\(key)")
    }
}

private extension ConnectionConfig {
    func withNewID() -> ConnectionConfig {
        var copy = self
        copy.id = UUID()
        copy.name = "新建连接"
        return copy
    }
}

// MARK: - 设置弹窗

struct SettingsSheet: View {
    @ObservedObject var store: ConnectionStore
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsPage(store: store)
            Divider()
            HStack {
                Spacer()
                Button("关闭") {
                    store.saveSettings()
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

struct ConnectionEditor: View {
    private let connectionID: UUID
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var namespace: String
    @State private var username: String
    @State private var password: String
    @State private var useTLS: Bool
    @State private var skipTLSVerify: Bool
    @State private var keyPrefix: String
    @State private var isTesting = false
    @State private var testResult: TestResult?
    var onCancel: () -> Void
    var onSave: (ConnectionConfig) -> Void

    init(
        connection: ConnectionConfig,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ConnectionConfig) -> Void
    ) {
        self.connectionID = connection.id
        _name = State(initialValue: connection.name)
        _host = State(initialValue: connection.host)
        _port = State(initialValue: String(connection.port))
        _namespace = State(initialValue: connection.namespace)
        _username = State(initialValue: connection.username)
        _password = State(initialValue: connection.password)
        _useTLS = State(initialValue: connection.useTLS)
        _skipTLSVerify = State(initialValue: connection.skipTLSVerify)
        _keyPrefix = State(initialValue: connection.keyPrefix)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("连接")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                labeledField("名称") {
                    AppKitTextField(text: $name, placeholder: "本地 etcd")
                }
                labeledField("主机") {
                    AppKitTextField(text: $host, placeholder: "127.0.0.1")
                }
                labeledField("端口") {
                    AppKitTextField(text: $port, placeholder: "2379")
                        .frame(width: 130)
                }
                labeledField("命名空间") {
                    AppKitTextField(text: $namespace, placeholder: "可选")
                }
                labeledField("键前缀") {
                    AppKitTextField(text: $keyPrefix, placeholder: "可选，例如 /myapp/")
                }
                labeledField("用户名") {
                    AppKitTextField(text: $username, placeholder: "可选")
                }
                labeledField("密码") {
                    AppKitTextField(text: $password, placeholder: "可选", isSecure: true)
                }
            }

            Toggle("启用 TLS", isOn: $useTLS)
            Toggle("跳过 TLS 校验", isOn: $skipTLSVerify)

            HStack(spacing: 10) {
                Button {
                    Task { await testConnection() }
                } label: {
                    Label("测试连接", systemImage: "checkmark.circle")
                }
                .disabled(!canSave || isTesting)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                if let testResult {
                    Label(testResult.message, systemImage: testResult.icon)
                        .font(.callout)
                        .foregroundStyle(testResult.color)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { onSave(currentConnection) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(maxWidth: 560)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Int(port) ?? 0) > 0
    }

    private var currentConnection: ConnectionConfig {
        ConnectionConfig(
            id: connectionID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? 2379,
            namespace: namespace.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            useTLS: useTLS,
            skipTLSVerify: skipTLSVerify,
            keyPrefix: keyPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        do {
            let version = try await EtcdHTTPClient(connection: currentConnection).version()
            testResult = TestResult(
                message: "连接成功：etcd \(version)",
                icon: "checkmark.circle.fill",
                color: .green
            )
        } catch {
            testResult = TestResult(
                message: error.localizedDescription,
                icon: "xmark.octagon.fill",
                color: .red
            )
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity)
        }
    }
}

struct AppKitTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isSecure = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = isSecure ? NSSecureTextField() : NSTextField()
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 14)
        field.controlSize = .large
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

struct NewKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var key: String
    @Binding var value: String
    var onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新增键")
                .font(.headline)
            TextField("键", text: $key)
            TextEditor(text: $value)
                .font(.system(.body, design: .monospaced))
                .frame(height: 180)
                .border(Color.secondary.opacity(0.25))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建") { onCreate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(key.isEmpty)
            }
        }
        .padding()
        .frame(width: 520)
    }
}
