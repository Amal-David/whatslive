import Foundation

@MainActor
final class AppPreferences {
    var staleThresholdHours: Double {
        didSet { defaults.set(staleThresholdHours, forKey: Keys.staleThresholdHours) }
    }

    var scanIntervalSeconds: Double {
        didSet { defaults.set(scanIntervalSeconds, forKey: Keys.scanIntervalSeconds) }
    }

    var includeAllListeners: Bool {
        didSet { defaults.set(includeAllListeners, forKey: Keys.includeAllListeners) }
    }

    var enableDockerProbe: Bool {
        didSet { defaults.set(enableDockerProbe, forKey: Keys.enableDockerProbe) }
    }

    var enableOllamaProbe: Bool {
        didSet { defaults.set(enableOllamaProbe, forKey: Keys.enableOllamaProbe) }
    }

    var ignoredPortsText: String {
        didSet { defaults.set(ignoredPortsText, forKey: Keys.ignoredPortsText) }
    }

    var protectedNamesText: String {
        didSet { defaults.set(protectedNamesText, forKey: Keys.protectedNamesText) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        staleThresholdHours = defaults.object(forKey: Keys.staleThresholdHours) as? Double ?? 6
        scanIntervalSeconds = defaults.object(forKey: Keys.scanIntervalSeconds) as? Double ?? 5
        includeAllListeners = defaults.object(forKey: Keys.includeAllListeners) as? Bool ?? false
        enableDockerProbe = defaults.object(forKey: Keys.enableDockerProbe) as? Bool ?? true
        enableOllamaProbe = defaults.object(forKey: Keys.enableOllamaProbe) as? Bool ?? true
        ignoredPortsText = defaults.string(forKey: Keys.ignoredPortsText) ?? ""
        protectedNamesText = defaults.string(forKey: Keys.protectedNamesText) ?? "postgres,mongod,redis-server,rapportd,ControlCenter,Cursor"
    }

    var staleThreshold: TimeInterval {
        max(0.25, staleThresholdHours) * 3600
    }

    var scanInterval: TimeInterval {
        max(2, scanIntervalSeconds)
    }

    var ignoredPorts: Set<Int> {
        Set(
            ignoredPortsText
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    var protectedNames: Set<String> {
        Set(
            protectedNamesText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private enum Keys {
        static let staleThresholdHours = "staleThresholdHours"
        static let scanIntervalSeconds = "scanIntervalSeconds"
        static let includeAllListeners = "includeAllListeners"
        static let enableDockerProbe = "enableDockerProbe"
        static let enableOllamaProbe = "enableOllamaProbe"
        static let ignoredPortsText = "ignoredPortsText"
        static let protectedNamesText = "protectedNamesText"
    }
}
