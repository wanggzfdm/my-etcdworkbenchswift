import Foundation

@MainActor
final class ConnectionStore: ObservableObject {
    @Published var connections: [ConnectionConfig] = []
    @Published var settings: AppSettings = .default

    private let folderURL: URL
    private var connectionsURL: URL { folderURL.appendingPathComponent("connections.json") }
    private var settingsURL: URL { folderURL.appendingPathComponent("settings.json") }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        folderURL = appSupport.appendingPathComponent("Etcd Workbench Swift", isDirectory: true)
        load()
    }

    var selectedConnection: ConnectionConfig? {
        get {
            if let id = settings.selectedConnectionID,
               let connection = connections.first(where: { $0.id == id }) {
                return connection
            }
            return connections.first
        }
        set {
            settings.selectedConnectionID = newValue?.id
            saveSettings()
        }
    }

    func load() {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            if let data = try? Data(contentsOf: connectionsURL) {
                connections = try JSONDecoder().decode([ConnectionConfig].self, from: data)
            }
            if connections.isEmpty {
                connections = [.empty]
            }

            if let data = try? Data(contentsOf: settingsURL) {
                settings = try JSONDecoder().decode(AppSettings.self, from: data)
            }
            if settings.selectedConnectionID == nil {
                settings.selectedConnectionID = connections.first?.id
            }
            saveAll()
        } catch {
            connections = [.empty]
            settings = AppSettings(selectedConnectionID: connections.first?.id, keyPrefix: "")
        }
    }

    func upsert(_ connection: ConnectionConfig) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        settings.selectedConnectionID = connection.id
        saveAll()
    }

    func delete(_ connection: ConnectionConfig) {
        connections.removeAll { $0.id == connection.id }
        if connections.isEmpty {
            connections = [.empty]
        }
        if settings.selectedConnectionID == connection.id {
            settings.selectedConnectionID = connections.first?.id
        }
        saveAll()
    }

    func saveSettings() {
        write(settings, to: settingsURL)
    }

    private func saveAll() {
        write(connections, to: connectionsURL)
        write(settings, to: settingsURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to save \(url.path): \(error.localizedDescription)")
        }
    }
}
