import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: ServiceStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            serviceList
            Divider()
            footer
        }
        .background(.regularMaterial)
        .confirmationDialog(
            "Stop service?",
            isPresented: Binding(
                get: { store.pendingKillService != nil },
                set: { if !$0 { store.pendingKillService = nil } }
            ),
            presenting: store.pendingKillService
        ) { service in
            Button("Stop \(service.title)", role: .destructive) {
                Task { await store.stop(service, force: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { service in
            Text("This will stop \(service.kind.rawValue.lowercased()) service on \(service.portSummary). \(KillPlanner.plan(for: service).reason)")
        }
        .confirmationDialog(
            "Still running",
            isPresented: Binding(
                get: { store.pendingForceService != nil },
                set: { if !$0 { store.pendingForceService = nil } }
            ),
            presenting: store.pendingForceService
        ) { service in
            Button("Force Stop", role: .destructive) {
                Task { await store.stop(service, force: true) }
            }
            Button("Leave Running", role: .cancel) {}
        } message: { service in
            Text("\(service.title) still appears to be running. Force stop sends SIGKILL.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What's Live")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: store.snapshot.isScanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(14)
    }

    private var serviceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let error = store.snapshot.errorMessage {
                    NoticeView(title: "Scan issue", message: error)
                }
                SectionBlock(title: "Stale", services: filteredServices(status: .stale), store: store)
                SectionBlock(title: "Running", services: runningServices, store: store)
                SectionBlock(title: "Protected", services: filteredServices(status: .protected), store: store)

                if store.snapshot.services.isEmpty, !store.snapshot.isScanning {
                    NoticeView(title: "Quiet right now", message: "No developer services matched the current filters.")
                }
            }
            .padding(14)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: WindowID.details)
            } label: {
                Label("Details", systemImage: "sidebar.right")
            }
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    private var runningServices: [RunningService] {
        store.snapshot.services.filter { $0.status == .running }
    }

    private func filteredServices(status: ServiceStatus) -> [RunningService] {
        store.snapshot.services.filter { $0.status == status }
    }

    private var statusText: String {
        if store.snapshot.isScanning {
            return "Scanning..."
        }
        let updated = store.snapshot.lastUpdated.map { TimeFormatters.shortDate($0) } ?? "never"
        return "\(store.snapshot.visibleDevServices.count) dev services, \(store.snapshot.staleCount) stale - updated \(updated)"
    }
}

private struct SectionBlock: View {
    let title: String
    let services: [RunningService]
    @ObservedObject var store: ServiceStore

    var body: some View {
        if !services.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                ForEach(services) { service in
                    ServiceRowView(service: service, store: store)
                }
            }
        }
    }
}

private struct NoticeView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
    }
}
