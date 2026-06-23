import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let preferences: AppPreferences
    private let onChange: () -> Void

    private let staleField = NSTextField()
    private let intervalField = NSTextField()
    private let allListenersButton = NSButton(checkboxWithTitle: "Show all listeners", target: nil, action: nil)
    private let dockerButton = NSButton(checkboxWithTitle: "Docker containers", target: nil, action: nil)
    private let ollamaButton = NSButton(checkboxWithTitle: "Ollama models", target: nil, action: nil)
    private let ignoredPortsField = NSTextField()
    private let protectedNamesField = NSTextField()

    init(preferences: AppPreferences, onChange: @escaping () -> Void) {
        self.preferences = preferences
        self.onChange = onChange

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        stack.addArrangedSubview(Self.row(label: "Stale threshold hours", field: staleField))
        stack.addArrangedSubview(Self.row(label: "Scan interval seconds", field: intervalField))
        stack.addArrangedSubview(allListenersButton)
        stack.addArrangedSubview(dockerButton)
        stack.addArrangedSubview(ollamaButton)
        stack.addArrangedSubview(Self.row(label: "Ignored ports", field: ignoredPortsField))
        stack.addArrangedSubview(Self.row(label: "Protected names", field: protectedNamesField))

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        stack.addArrangedSubview(saveButton)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's Live Settings"
        window.contentView = stack

        super.init(window: window)

        saveButton.target = self
        saveButton.action = #selector(save)
        load()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func row(label: String, field: NSTextField) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(field)
        return stack
    }

    private func load() {
        staleField.doubleValue = preferences.staleThresholdHours
        intervalField.doubleValue = preferences.scanIntervalSeconds
        allListenersButton.state = preferences.includeAllListeners ? .on : .off
        dockerButton.state = preferences.enableDockerProbe ? .on : .off
        ollamaButton.state = preferences.enableOllamaProbe ? .on : .off
        ignoredPortsField.stringValue = preferences.ignoredPortsText
        protectedNamesField.stringValue = preferences.protectedNamesText
    }

    @objc private func save() {
        preferences.staleThresholdHours = staleField.doubleValue
        preferences.scanIntervalSeconds = intervalField.doubleValue
        preferences.includeAllListeners = allListenersButton.state == .on
        preferences.enableDockerProbe = dockerButton.state == .on
        preferences.enableOllamaProbe = ollamaButton.state == .on
        preferences.ignoredPortsText = ignoredPortsField.stringValue
        preferences.protectedNamesText = protectedNamesField.stringValue
        onChange()
        window?.close()
    }
}
