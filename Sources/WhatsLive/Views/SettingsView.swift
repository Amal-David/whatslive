import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        TabView {
            Form {
                SliderRow(
                    title: "Stale threshold",
                    value: $preferences.staleThresholdHours,
                    range: 0.5...48,
                    suffix: "hours"
                )
                SliderRow(
                    title: "Scan interval",
                    value: $preferences.scanIntervalSeconds,
                    range: 2...30,
                    suffix: "seconds"
                )
                Toggle("Show all listeners", isOn: $preferences.includeAllListeners)
            }
            .padding()
            .tabItem { Label("Scan", systemImage: "dot.radiowaves.left.and.right") }

            Form {
                Toggle("Docker containers", isOn: $preferences.enableDockerProbe)
                Toggle("Ollama models", isOn: $preferences.enableOllamaProbe)
                LabeledContent("Ignored ports") {
                    TextField("3001, 5432", text: $preferences.ignoredPortsText)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Protected names") {
                    TextField("postgres, redis-server", text: $preferences.protectedNamesText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
            .tabItem { Label("Safety", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 260)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                    .frame(width: 220)
                Text("\(value, specifier: "%.1f") \(suffix)")
                    .monospacedDigit()
                    .frame(width: 96, alignment: .trailing)
            }
        }
    }
}
