import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Dictator safety test"
        let content = NSView(frame: window.contentView!.bounds)
        let title = NSTextField(labelWithString: "Protected field test — leave this empty")
        title.frame = NSRect(x: 24, y: 145, width: 450, height: 24)
        let detail = NSTextField(wrappingLabelWithString: "This disposable app has no network access or credential storage. Dictation must not insert into the password field below.")
        detail.frame = NSRect(x: 24, y: 85, width: 450, height: 50)
        let password = NSSecureTextField(frame: NSRect(x: 24, y: 40, width: 450, height: 28))
        password.placeholderString = "Password test — do not enter a real password"
        password.setAccessibilityLabel("Password test")
        content.addSubview(title); content.addSubview(detail); content.addSubview(password)
        window.contentView = content; window.center(); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(password); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let application = NSApplication.shared
let delegate = FixtureDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
