import AppKit
import SwiftUI
import Combine

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var item: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var indicator: NSPanel!
    private var subscriptions = Set<AnyCancellable>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Dictator", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu; mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Dictator")
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        indicator = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 52),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        indicator.isOpaque = false; indicator.backgroundColor = .clear; indicator.hasShadow = true
        indicator.level = .floating; indicator.ignoresMouseEvents = true
        indicator.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        indicator.contentView = NSHostingView(rootView: IndicatorView(model: model))
        model.openSettings = { [weak self] in self?.showSettings() }
        model.$phase.sink { [weak self] phase in
            DispatchQueue.main.async { self?.updateIndicator(phase) }
        }.store(in: &subscriptions)
        model.start()
        if !model.keySaved || !model.accessibility || !model.microphoneAllowed { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.cancel(); model.monitor.stop() }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: String(model.status.prefix(100)), action: nil, keyEquivalent: "")
        status.isEnabled = false; menu.addItem(status)
        menu.addItem(.separator())
        if model.phase != .idle { add(menu, "Cancel dictation", #selector(cancel)) }
        if !model.lastResult.isEmpty {
            add(menu, "Copy last result (expires in 5 minutes)", #selector(copyResult))
            add(menu, "Discard result", #selector(discard))
        }
        add(menu, "Settings…", #selector(showSettings), key: ",")
        menu.addItem(.separator())
        add(menu, "Quit Dictator", #selector(quit), key: "q")
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
    }
    private func updateIndicator(_ phase: AppModel.Phase) {
        item.button?.image = NSImage(systemSymbolName: phase == .recording ? "mic.fill" : phase == .processing ? "ellipsis.circle" : "waveform", accessibilityDescription: "Dictator")
        if phase == .idle { indicator.orderOut(nil); return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame { indicator.setFrameOrigin(NSPoint(x: frame.midX - 155, y: frame.minY + 32)) }
        indicator.orderFrontRegardless()
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Dictator Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, settings: model.settings))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func cancel() { model.cancel() }
    @objc func copyResult() { model.copyResult() }
    @objc func discard() { model.clearResult() }
    @objc func quit() { NSApp.terminate(nil) }
}

@main enum DictatorApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--benchmark-cleanup") {
            application.setActivationPolicy(.prohibited)
            Task {
                do {
                    let report = try await CleanupBenchmark.run()
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(report)
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                    exit(0)
                } catch {
                    fputs("Cleanup benchmark failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            application.run()
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
