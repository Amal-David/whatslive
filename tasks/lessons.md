# Lessons

- If the user accepts the existing product name after a naming exploration, keep the chosen name and apply polish around it instead of continuing to rename the app.
- For a menu-bar-only AppKit app, verify the status item is explicitly created by a retained `NSApplicationDelegate` entry point and uses a stable square `NSStatusItem` so the app can be running without disappearing from the menu bar.
- Do not model What's Live only as a port listener. It should always include a protected self/observer row because the app is valuable even when it opens no TCP port.
