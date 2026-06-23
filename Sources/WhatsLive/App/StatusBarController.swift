import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let store: ServiceStore
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var detailsWindowController: DetailsWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var observerID: UUID?

    init(store: ServiceStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "What's Live")
        statusItem.button?.title = "Live"
        statusItem.button?.imagePosition = .imageLeading

        observerID = store.observe { [weak self] snapshot in
            self?.updateStatusLabel(snapshot)
        }
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        Task { await store.refresh() }
    }

    private func updateStatusLabel(_ snapshot: ServiceSnapshot) {
        let count = snapshot.visibleDevServices.count
        if snapshot.staleCount > 0 {
            statusItem.button?.title = "Live \(count) !\(snapshot.staleCount)"
            statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Stale services")
        } else {
            statusItem.button?.title = "Live \(count)"
            statusItem.button?.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "What's Live")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(disabledTitle: headerText)
        menu.addItem(.separator())

        addSection("Stale", services: store.snapshot.services.filter { $0.status == .stale })
        addSection("Running", services: store.snapshot.services.filter { $0.status == .running })
        addSection("Protected", services: store.snapshot.services.filter { $0.status == .protected })

        if store.snapshot.services.isEmpty {
            menu.addItem(disabledTitle: store.snapshot.isScanning ? "Scanning..." : "No developer services matched")
        }
        if let error = store.snapshot.errorMessage {
            menu.addItem(disabledTitle: "Scan issue: \(short(error, limit: 42))")
        }

        menu.addItem(.separator())
        menu.addItem(actionTitle: "Refresh", target: self, action: #selector(refresh))
        menu.addItem(actionTitle: "Details", target: self, action: #selector(showDetails))
        menu.addItem(actionTitle: "Settings", target: self, action: #selector(showSettings))
        menu.addItem(.separator())
        menu.addItem(actionTitle: "Quit What's Live", target: NSApp, action: #selector(NSApplication.terminate(_:)))
    }

    private var headerText: String {
        if store.snapshot.isScanning {
            return "What's Live - scanning"
        }
        let updated = store.snapshot.lastUpdated.map { TimeFormatters.shortDate($0) } ?? "never"
        return "\(store.snapshot.visibleDevServices.count) services, \(store.snapshot.staleCount) stale - \(updated)"
    }

    private func addSection(_ title: String, services: [RunningService]) {
        guard !services.isEmpty else { return }
        menu.addItem(disabledTitle: title.uppercased())
        for service in services.prefix(8) {
            addService(service)
        }
        if services.count > 8 {
            menu.addItem(disabledTitle: "\(services.count - 8) more in Details")
        }
    }

    private func addService(_ service: RunningService) {
        let item = NSMenuItem(title: rowTitle(for: service), action: #selector(selectService(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = service.id
        item.image = NSImage(systemSymbolName: service.kind.symbolName, accessibilityDescription: service.kind.rawValue)
        menu.addItem(item)

        let stopTitle = service.safety == .protected ? "Protected" : "Stop \(short(service.title, limit: 22))"
        let stopItem = NSMenuItem(title: "  \(stopTitle)", action: #selector(stopService(_:)), keyEquivalent: "")
        stopItem.target = self
        stopItem.representedObject = service.id
        stopItem.isEnabled = service.safety != .protected
        menu.addItem(stopItem)
    }

    private func rowTitle(for service: RunningService) -> String {
        let status = service.status == .stale ? "stale" : service.status.rawValue.lowercased()
        return "\(short(service.title, limit: 24)) :\(service.portSummary) - \(status)"
    }

    @objc private func refresh() {
        Task { await store.refresh() }
    }

    @objc private func showDetails() {
        let controller = detailsWindowController ?? DetailsWindowController(store: store)
        detailsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(preferences: store.preferences) { [weak self] in
            self?.store.startPolling()
            Task {
                guard let self else { return }
                await self.store.refresh()
            }
        }
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func selectService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? RunningService.ID else { return }
        store.selectedServiceID = id
        showDetails()
    }

    @objc private func stopService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? RunningService.ID,
              let service = store.snapshot.services.first(where: { $0.id == id })
        else { return }

        let plan = KillPlanner.plan(for: service)
        if plan.requiresConfirmation, !confirmStop(service: service, force: false) {
            return
        }

        Task {
            let result = await store.stop(service, force: false)
            if case .failure(let error) = result {
                showError(error.localizedDescription)
            } else if store.snapshot.services.contains(where: { $0.id == service.id }),
                      KillPlanner.plan(for: service).allowsForceStop,
                      confirmStop(service: service, force: true) {
                _ = await store.stop(service, force: true)
            }
        }
    }

    private func confirmStop(service: RunningService, force: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = force ? "Force stop \(service.title)?" : "Stop \(service.title)?"
        alert.informativeText = force
            ? "This sends SIGKILL to \(service.command)."
            : "This will stop \(service.kind.rawValue.lowercased()) service on \(service.portSummary). \(KillPlanner.plan(for: service).reason)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: force ? "Force Stop" : "Stop")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Stop failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private extension NSMenu {
    func addItem(disabledTitle title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addItem(actionTitle title: String, target: AnyObject, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        addItem(item)
    }
}
