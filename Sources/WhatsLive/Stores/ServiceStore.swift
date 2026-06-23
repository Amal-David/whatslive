import Combine
import Foundation

@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var snapshot = ServiceSnapshot.empty
    @Published var selectedServiceID: RunningService.ID?
    @Published var pendingKillService: RunningService?
    @Published var pendingForceService: RunningService?

    let preferences: AppPreferences

    private let scanner: ServiceScanner
    private let stopper: ServiceStopper
    private var scanTask: Task<Void, Never>?
    private var historyByID: [RunningService.ID: [KillEvent]] = [:]

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

    func requestStop(_ service: RunningService) {
        let plan = KillPlanner.plan(for: service)
        if plan.requiresConfirmation {
            pendingKillService = service
        } else {
            Task { await stop(service, force: false) }
        }
    }

    func stop(_ service: RunningService, force: Bool) async {
        let plan = KillPlanner.plan(for: service, force: force)
        do {
            try await stopper.stop(using: plan)
            appendHistory("Sent \(force ? "SIGKILL" : "SIGTERM")", for: service.id)
            pendingKillService = nil
            pendingForceService = nil
            try? await Task.sleep(for: .milliseconds(700))
            await refresh()
            if !force, let updated = snapshot.services.first(where: { $0.id == service.id }) {
                pendingForceService = updated
            }
        } catch {
            appendHistory("Stop failed: \(error.localizedDescription)", for: service.id)
            pendingKillService = nil
            pendingForceService = nil
            snapshot = ServiceSnapshot(
                services: snapshot.services,
                lastUpdated: snapshot.lastUpdated,
                isScanning: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func appendHistory(_ message: String, for id: RunningService.ID) {
        historyByID[id, default: []].insert(KillEvent(date: Date(), message: message), at: 0)
    }
}
