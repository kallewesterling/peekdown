import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentRect = NSRect(x: 0, y: 0, width: 460, height: 280)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.window = window
        window.title = "Markdown Quick Look"
        window.center()

        let container = NSView(frame: contentRect)

        let titleLabel = NSTextField(labelWithString: "Markdown Quick Look is installed.")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.frame = NSRect(x: 20, y: 220, width: 420, height: 24)
        container.addSubview(titleLabel)

        let bodyLabel = NSTextField(wrappingLabelWithString:
            "Press the Space bar on a Markdown file (.md, .markdown, .mdown, .mkd…) in Finder to preview it.\n\n" +
            "If previews don't appear, open System Settings → General → Login Items & Extensions → Quick Look, " +
            "and make sure \"Markdown Quick Look\" is enabled."
        )
        bodyLabel.frame = NSRect(x: 20, y: 110, width: 420, height: 100)
        container.addSubview(bodyLabel)

        let settingsButton = NSButton(title: "Open Extension Settings", target: self, action: #selector(openExtensionSettings))
        settingsButton.frame = NSRect(x: 20, y: 60, width: 200, height: 32)
        settingsButton.bezelStyle = .rounded
        container.addSubview(settingsButton)

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quit))
        quitButton.frame = NSRect(x: 340, y: 60, width: 100, height: 32)
        quitButton.bezelStyle = .rounded
        container.addSubview(quitButton)

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
