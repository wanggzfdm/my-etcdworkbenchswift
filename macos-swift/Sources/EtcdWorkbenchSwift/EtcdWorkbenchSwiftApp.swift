import SwiftUI

// NSView 包装器，用于监听窗口大小变化
struct WindowSizeTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            
            // 监听窗口大小调整结束事件，保存用户调整后的尺寸
            NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                guard let window = window else { return }
                let size = window.frame.size
                UserDefaults.standard.set(size.width, forKey: "windowWidth")
                UserDefaults.standard.set(size.height, forKey: "windowHeight")
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@main
struct EtcdWorkbenchSwiftApp: App {
    @StateObject private var store = ConnectionStore()
    @StateObject private var viewModel = AppViewModel()
    
    // 默认窗口大小 1200x800
    private let defaultWidth: Double = 1200
    private let defaultHeight: Double = 800

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(viewModel)
                .preferredColorScheme(store.settings.theme.colorScheme)
                .frame(minWidth: 1060, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: defaultWidth, height: defaultHeight)
        .commands {
            CommandMenu("Etcd") {
                Button("连接") {
                    if let connection = store.selectedConnection {
                        viewModel.openSession(connection, prefix: store.settings.keyPrefix)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

private extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
