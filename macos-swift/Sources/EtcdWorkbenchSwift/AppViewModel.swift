import Foundation

/// 顶层工作区模型：管理已打开的连接会话（每个会话对应一个 Tab）。
/// 负责打开 / 关闭 / 切换会话；具体的键值操作下沉到 ConnectionSession。
@MainActor
final class AppViewModel: ObservableObject {
    @Published var sessions: [ConnectionSession] = []
    @Published var activeSessionID: UUID?
    /// 是否显示首页（连接列表）视图。与 sessions 生命周期解耦，
    /// 回到首页不会关闭已打开的连接。
    @Published var showHome: Bool = true

    /// 当前激活的会话（对应当前选中的 Tab）。
    var activeSession: ConnectionSession? {
        guard let activeSessionID else { return sessions.first }
        return sessions.first { $0.id == activeSessionID }
    }

    var hasOpenSession: Bool {
        !sessions.isEmpty
    }

    /// 打开一个连接：
    /// - 若该连接（按 config.id 去重）已打开，则直接激活其 Tab；
    /// - 否则新建会话、加入列表、设为激活，并发起连接。
    /// 打开连接后自动离开首页，显示工作区。
    func openSession(_ config: ConnectionConfig, prefix: String = "") {
        if let existing = sessions.first(where: { $0.id == config.id }) {
            activeSessionID = existing.id
            showHome = false
            return
        }
        let session = ConnectionSession(config: config)
        sessions.append(session)
        activeSessionID = session.id
        showHome = false
        Task { await session.connect(prefix: prefix) }
    }

    /// 关闭会话（关闭 Tab 即断开连接）。关闭后若仍有其他会话，自动激活相邻的一个；
    /// 若所有会话均已关闭，自动回到首页。
    func closeSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: index)
        if activeSessionID == id {
            let fallbackIndex = min(index, sessions.count - 1)
            activeSessionID = sessions.indices.contains(fallbackIndex) ? sessions[fallbackIndex].id : nil
        }
        if sessions.isEmpty {
            showHome = true
        }
    }

    func activate(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
    }

    /// 关闭所有会话，回到首页连接列表。
    func closeAllSessions() {
        sessions.removeAll()
        activeSessionID = nil
    }
}
