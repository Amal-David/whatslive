import AppKit

final class WhatsLiveApp: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusController = StatusBarController(store: ServiceStore())
    }
}

@MainActor
@main
enum WhatsLiveMain {
    private static var delegate: WhatsLiveApp?

    static func main() {
        let app = NSApplication.shared
        let appDelegate = WhatsLiveApp()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
