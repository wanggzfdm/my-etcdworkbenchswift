import SwiftUI

/// 启动后的连接列表页（首页）。简单纵向列表，支持新建 / 编辑 / 删除 / 打开连接。
/// 选择某个连接后，由 onOpen 回调进入主界面。
struct ConnectionListView: View {
    @EnvironmentObject private var store: ConnectionStore

    var onOpen: (ConnectionConfig) -> Void
    var onNew: () -> Void
    var onEdit: (ConnectionConfig) -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if store.connections.isEmpty {
                ContentUnavailableView {
                    Label("还没有连接", systemImage: "server.rack")
                } description: {
                    Text("点击「新建连接」添加一个 etcd 连接。")
                } actions: {
                    Button {
                        onNew()
                    } label: {
                        Label("新建连接", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.connections) { connection in
                            connectionCard(connection)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Etcd Workbench")
                    .font(.title2.weight(.semibold))
                Text("选择一个连接以开始")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置")

            Button {
                onNew()
            } label: {
                Label("新建连接", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private func connectionCard(_ connection: ConnectionConfig) -> some View {
        Button {
            onOpen(connection)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(connection.host):\(connection.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if connection.useTLS {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("已启用 TLS")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击打开连接")
        .contextMenu {
            Button("打开") { onOpen(connection) }
            Button("编辑") { onEdit(connection) }
            Button("删除", role: .destructive) { store.delete(connection) }
        }
    }
}

/// 多 Tab 场景下，点击 Tab 栏「+」时弹出的连接选择器。
/// 选中某连接后以新 Tab 打开（同连接已打开则直接激活）。
struct ConnectionPickerSheet: View {
    @EnvironmentObject private var store: ConnectionStore

    var onOpen: (ConnectionConfig) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("打开连接")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding()

            Divider()

            if store.connections.isEmpty {
                ContentUnavailableView(
                    "还没有连接",
                    systemImage: "server.rack",
                    description: Text("请先在连接选择界面新建一个 etcd 连接。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.connections) { connection in
                            Button {
                                onOpen(connection)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(connection.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text("\(connection.host):\(connection.port)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("关闭") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 380)
    }
}
