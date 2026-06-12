import SwiftUI

/// 主界面顶部的自绘横向 Tab 栏。每个 Tab 对应一个已打开的连接会话。
/// 点击 Tab 切换激活会话；点击 × 关闭会话（即断开连接）；末尾 + 打开新连接。
struct WorkspaceTabBar: View {
    @ObservedObject var workspace: AppViewModel
    var onNewTab: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(workspace.sessions) { session in
                    tab(session)
                }
                newTabButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 40)
        .background(Color.secondary.opacity(0.06))
    }

    private var newTabButton: some View {
        Button {
            onNewTab()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("新连接")
                    .font(.callout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Color.accentColor)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开新连接")
    }

    private func tab(_ session: ConnectionSession) -> some View {
        let isActive = workspace.activeSession?.id == session.id
        return HStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            Text(session.config.name)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            Button {
                workspace.closeSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭并断开")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.activate(session.id)
        }
    }
}
