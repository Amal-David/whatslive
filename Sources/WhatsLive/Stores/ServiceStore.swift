import Foundation

@MainActor
final class ServiceStore {
    private(set) var snapshot = ServiceSnapshot.empty {
        didSet { notifyObservers() }
    }
    var selectedServiceID: RunningService.ID?

    let preferences: AppPreferences

    private let scanner: ServiceScanner
    private let stopper: ServiceStopper
    private var scanTask: Task<Void, Never>?
    private var historyByID: [RunningService.ID: [KillEvent]] = [:]
    private var observers: [UUID: (ServiceSnapshot) -> Void] = [:]

    init(
        preferences: AppPreferences = AppPreferences(),
        scanner: ServiceScanner = ServiceScanner(),
        stopper: ServiceStopper = ServiceStopper()
    ) {
        self.preferences = preferences
        self.scanner = scanner
        self.stopper = stopper
        startPolling()
    }

    deinit {
        scanTask?.cancel()
    }

    var selectedService: RunningService? {
        guard let selectedServiceID else { return snapshot.services.first }
        return snapshot.services.first { $0.id == selectedServiceID }
    }

    @discardableResult
    func observe(_ observer: @escaping (ServiceSnapshot) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(snapshot)
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    func startPolling() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                let interval = await MainActor.run { self.preferences.scanInterval }
                try? await Task.sleep(for: .seconds(interval))
                await self.refresh()
            }
        }
    }

    func refresh() async {
        snapshot = ServiceSnapshot(
            services: snapshot.services,
            lastUpdated: snapshot.lastUpdated,
            isScanning: true,
            errorMessage: nil
        )

        do {
            let options = ScannerOptions(
                staleThreshold: preferences.staleThreshold,
                includeAllListeners: preferences.includeAllListeners,
                ignoredPorts: preferences.ignoredPorts,
                protectedNames: preferences.protectedNames,
                enableDockerProbe: preferences.enableDockerProbe,
                enableOllamaProbe: preferences.enableOllamaProbe
            )
            var services = try await scanner.scan(options: options)
            for index in services.indices {
                services[index].killHistory = historyByID[services[index].id, default: []]
            }
            snapshot = ServiceSnapshot(
                services: services,
                lastUpdated: Date(),
                isScanning: false,
                errorMessage: nil
            )
            if selectedServiceID == nil {
                selectedServiceID = services.first?.id
            }
        } catch {
            snapshot = ServiceSnapshot(
                services: snapshot.services,
                lastUpdated: snapshot.lastUpdated,
                isScanning: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    @discardableResult
    func stop(_ service: RunningService, force: Bool) async -> Result<Void, Error> {
        let plan = KillPlanner.plan(for: service, force: force)
        do {
            try await stopper.stop(using: plan)
            appendHistory("Sent \(force ? "SIGKILL" : "SIGTERM")", for: service.id)
            try? await Task.sleep(for: .milliseconds(700))
            await refresh()
            return .success(())
        } catch {
            appendHistory("Stop failed: \(error.localizedDescription)", for: service.id)
            snapshot = ServiceSnapshot(
                services: snapshot.services,
                lastUpdated: snapshot.lastUpdated,
                isScanning: false,
                errorMessage: error.localizedDescription
            )
            return .failure(error)
        }
    }

    private func appendHistory(_ message: String, for id: RunningService.ID) {
        historyByID[id, default: []].insert(KillEvent(date: Date(), message: message), at: 0)
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer(snapshot)
        }
    }
}
