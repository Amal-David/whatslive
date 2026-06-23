import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct WhatsLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ServiceStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(store: store)
                .frame(width: 420, height: 560)
        } label: {
            MenuBarLabelView(snapshot: store.snapshot)
        }
        .menuBarExtraStyle(.window)

        Window("What's Live Details", id: WindowID.details) {
            DetailWindowView(store: store)
                .frame(minWidth: 620, minHeight: 480)
        }

        Settings {
            SettingsView(preferences: store.preferences)
        }
    }
}
