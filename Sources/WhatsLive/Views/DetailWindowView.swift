import SwiftUI

struct DetailWindowView: View {
    @ObservedObject var store: ServiceStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedServiceID) {
                ForEach(store.snapshot.services) { service in
                    Label(short(service.title, limit: 30), systemImage: service.kind.symbolName)
                        .tag(service.id)
                }
            }
            .navigationTitle("Services")
        } detail: {
            if let service = store.selectedService {
                ServiceDetailView(service: service, store: store)
            } else {
                ContentUnavailableView("No Service", systemImage: "bolt.slash", description: Text("Refresh to discover local services."))
            }
        }
        .task {
            if store.snapshot.services.isEmpty {
                await store.refresh()
            }
        }
    }
}

private struct ServiceDetailView: View {
    let service: RunningService
    @ObservedObject var store: ServiceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.title)
                            .font(.title2.weight(.semibold))
                        Text("\(service.kind.rawValue) - \(service.status.rawValue)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.requestStop(service)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(service.safety == .protected)
                }

                DetailGrid(rows: detailRows)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Classification")
                        .font(.headline)
                    Text(service.classificationReason)
                    if !service.staleReasons.isEmpty {
                        Text("Stale signals: \(service.staleReasons.joined(separator: ", "))")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Kill History")
                        .font(.headline)
                    if service.killHistory.isEmpty {
                        Text("No stop attempts yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(service.killHistory, id: \.self) { event in
                            Text("\(TimeFormatters.shortDate(event.date)): \(event.message)")
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailRows: [(String, String)] {
        [
            ("PID", service.pid.map(String.init) ?? "none"),
            ("Parent PID", service.parentPID.map(String.init) ?? "none"),
            ("User", service.user),
            ("Ports", service.ports.map { "\($0.displayAddress):\($0.port)" }.joined(separator: ", ")),
            ("HTTP", service.httpProbe ?? "not detected"),
            ("Age", TimeFormatters.shortDate(service.startDate)),
            ("CWD", pathDisplay(service.cwd)),
            ("Command", service.command),
            ("Safety", service.safety.rawValue),
            ("Docker", service.dockerStatus ?? "none")
        ]
    }
}

private struct DetailGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { key, value in
                GridRow {
                    Text(key)
                        .foregroundStyle(.secondary)
                    Text(value.isEmpty ? "none" : value)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
    }
}
