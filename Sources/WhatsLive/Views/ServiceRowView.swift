import SwiftUI

struct ServiceRowView: View {
    let service: RunningService
    @ObservedObject var store: ServiceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: service.kind.symbolName)
                .frame(width: 18)
                .foregroundStyle(service.isStale ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(short(service.title, limit: 26))
                        .font(.subheadline.weight(.semibold))
                    StatusBadge(service: service)
                    Spacer(minLength: 4)
                }

                HStack(spacing: 8) {
                    Text(":\(service.portSummary)")
                    Text(TimeFormatters.shortDate(service.startDate))
                    Text(short(service.projectHint, limit: 18))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let reason = service.staleReasons.first {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                Button {
                    store.selectedServiceID = service.id
                    openWindow(id: WindowID.details)
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Details")

                Button {
                    store.requestStop(service)
                } label: {
                    Image(systemName: service.safety == .protected ? "lock" : "stop.fill")
                }
                .disabled(service.safety == .protected)
                .buttonStyle(.borderless)
                .help(service.safety == .protected ? "Protected" : "Stop")
            }
        }
        .padding(10)
        .background(service.isStale ? Color.primary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(service.isStale ? Color.primary.opacity(0.18) : Color.secondary.opacity(0.12))
        )
    }
}

private struct StatusBadge: View {
    let service: RunningService

    var body: some View {
        Text(service.status.rawValue)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(service.isStale ? 0.12 : 0.07))
            .clipShape(Capsule())
    }
}
