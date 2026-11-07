import AppKit
import AVFoundation
import SwiftUI
import Combine
import ServiceManagement
import DictatorCore

@MainActor final class AppModel: ObservableObject {
    enum Phase { case idle, recording, processing }
    @Published var phase: Phase = .idle
    @Published var status = "Ready" {
        didSet { appendDiagnostic("Status: \(status)") }
    }
    @Published var level: Float = 0
    @Published var seconds = 0
    @Published var handsFree = false
    @Published var accessibility = false
    @Published var microphoneAllowed = false
    @Published var shortcutReady = false
    @Published var fnSeen = false
    @Published var keySaved = false
    @Published var lastResult = ""
    @Published var shortcutDiagnostics = ""
    @Published var loginEnabled = false
    @Published var loginMessage = ""
    @Published var keyMessage = ""
    @Published var microphones: [Microphone] = []
    let settings = Settings()
    let monitor = ShortcutMonitor()
    let recorder = AudioRecorder()
    let insertion = TextInsertion()
    let api = OpenAIClient()
    var openSettings: (() -> Void)?
    private var task: Task<Void, Never>?
    private var resultExpiry: Task<Void, Never>?
    private var recordingTimer: Timer?
    private var permissionTimer: Timer?
    private var inputCaptureTime: TimeInterval = 0
    private var started = Date()
    private var target: InsertionTarget?
    private var generation = UUID()
    private var cancellables = Set<AnyCancellable>()
    private var workspaceObserver: NSObjectProtocol?
    private var wakeObservers = [NSObjectProtocol]()
    private var sleepObserver: NSObjectProtocol?

    func start() {
        keySaved = (try? Keychain.read()) != nil
        monitor.onDiagnostic = { [weak self] entry in
            guard let self else { return }
            self.appendDiagnostic(entry)
        }
        configureLogin()
        refreshPermissions()
        monitor.onPress = { [weak self] in self?.shortcutPressed() }
        monitor.onRelease = { [weak self] in self?.finish() }
        monitor.onHandsFree = { [weak self] in
            guard let self, self.phase == .recording else { return }
            self.handsFree = true; self.status = "Hands-free — press Fn to finish"
        }
        monitor.onCancel = { [weak self] in self?.cancel() }
        monitor.onFnSeen = { [weak self] in if self?.fnSeen == false { self?.fnSeen = true } }
        monitor.onActivity = { [weak self] activity in
            guard let self, self.phase != .idle else { return }
            self.appendDiagnostic("Input: \(activity.description), event=\(activity.timestamp), target=\(self.inputCaptureTime)")
            guard activity.timestamp >= self.inputCaptureTime else { return }
            self.cancel(message: "Typing or clicking cancelled dictation.")
        }
        settings.$shortcut.removeDuplicates().sink { [weak self] shortcut in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancel(); self.monitor.shortcut = shortcut
                self.shortcutReady = self.accessibility && self.monitor.start()
            }
        }.store(in: &cancellables)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.phase != .idle,
                      let target = self.target,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid else { return }
                // Activation notifications can arrive after microphone startup.
                // Only a current change away from the captured target cancels.
                self.cancel(message: "App changed; dictation cancelled.")
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.cancel() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.cancel(); self.monitor.stop(); self.refreshPermissions()
                }
            })
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPermissions() }
        }
    }
    private func appendDiagnostic(_ entry: String) {
        let time = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        shortcutDiagnostics = (shortcutDiagnostics.components(separatedBy: "\n") + ["\(time) \(entry)"]).suffix(32).joined(separator: "\n")
    }
    func configureLogin() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "launchAtLogin") == nil { defaults.set(true, forKey: "launchAtLogin") }
        setLoginEnabled(defaults.bool(forKey: "launchAtLogin"))
    }
    func setLoginEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        do {
            if enabled && SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval { try SMAppService.mainApp.register() }
            else if !enabled && SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow Dictator in System Settings → General → Login Items." : (loginEnabled ? "Dictator opens automatically when you log in." : "Automatic startup is off.")
        } catch { loginEnabled = false; loginMessage = "Could not set automatic startup: \(error.localizedDescription)" }
    }
    func refreshPermissions() {
        accessibility = AXIsProcessTrusted()
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if accessibility && !monitor.running { shortcutReady = monitor.start() }
        if !accessibility { monitor.stop(); shortcutReady = false }
        if phase == .recording && (!accessibility || !microphoneAllowed) { cancel(message: "A required permission was revoked.") }
    }
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.refreshPermissions(); self?.refreshDevices() } }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
    }
    func openPrivacy(_ name: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(name)") { NSWorkspace.shared.open(url) }
    }
    func refreshDevices() { microphones = AudioRecorder.microphones() }
    func saveKey(_ key: String) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains(where: { $0.isWhitespace }) else { keyMessage = "Enter a valid API key."; return }
        do { try Keychain.save(clean); keySaved = true; keyMessage = "Saved securely in Keychain." }
        catch { keyMessage = error.localizedDescription }
    }
    func deleteKey() {
        do { try Keychain.delete(); keySaved = false; keyMessage = "API key removed." }
        catch { keyMessage = error.localizedDescription }
    }
    func verifyKey() {
        keyMessage = "Checking model access…"
        Task {
            do {
                guard let key = try Keychain.read() else { throw DictationError.message("Save an API key first.") }
                try await api.verify(key: key, options: settings.ai)
                keyMessage = "Key accepted; both selected models are available."
            } catch { keyMessage = error.localizedDescription }
        }
    }
    private func shortcutPressed() {
        guard phase == .idle else { monitor.resetRecordingGesture(); return }
        begin()
        if phase != .recording { resetGesture() }
    }
    private func resetGesture() {
        appendDiagnostic("Reset gesture; phase=\(phase)")
        monitor.resetRecordingGesture(); handsFree = false
    }
    func begin() {
        guard phase == .idle else { return }
        guard microphoneAllowed && accessibility && keySaved else {
            status = "Open Settings to add your API key and grant permissions."
            openSettings?(); return
        }
        clearResult()
        do {
            target = try insertion.capture()
            inputCaptureTime = ProcessInfo.processInfo.systemUptime
            try recorder.start(microphone: settings.microphone)
            generation = UUID(); started = Date(); seconds = 0; level = 0
            phase = .recording; status = "Listening…"
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.phase == .recording else { return }
                    self.level = self.recorder.level; self.seconds = Int(Date().timeIntervalSince(self.started))
                    if self.seconds >= AudioRecorder.maximumSeconds { self.finish() }
                    else if self.seconds > 2 && !self.recorderIsRunning { self.cancel(message: "Microphone disconnected. Check Settings.") }
                }
            }
        } catch { target = nil; status = error.localizedDescription }
    }
    private var recorderIsRunning: Bool { recorder.isRunning }
    func finish() {
        resetGesture()
        guard phase == .recording, let target else { return }
        recordingTimer?.invalidate(); recordingTimer = nil
        let wav: Data
        do { wav = try recorder.finish() }
        catch { phase = .idle; status = error.localizedDescription; return }
        phase = .processing; status = "Transcribing…"
        let id = generation
        let options = settings.ai
        task = Task {
            do {
                guard let key = try Keychain.read() else { throw DictationError.message("Save your API key in Settings.") }
                let raw = try await api.transcribe(wav: wav, key: key, options: options)
                try Task.checkCancellation()
                guard !raw.isEmpty else { throw DictationError.message("No speech detected. Check the microphone and try again.") }
                remember(raw)
                status = options.cleanup ? "Cleaning up…" : "Inserting…"
                // If cleanup fails, keep raw text for explicit copying rather than silently inserting it.
                let cleaned = try await api.correct(raw, key: key, options: options)
                try Task.checkCancellation()
                guard generation == id else { return }
                remember(cleaned); status = "Inserting…"
                let confirmed = try await insertion.insert(cleaned, into: target)
                guard generation == id else { return }
                if confirmed { clearResult(); status = "Inserted" }
                else { status = "Paste sent; check the field. A copy is available in the menu." }
                phase = .idle; self.target = nil
            } catch is CancellationError {
                // cancel() owns the UI and memory cleanup.
            } catch {
                guard generation == id else { return }
                status = error.localizedDescription; phase = .idle; self.target = nil
            }
        }
    }
    func cancel(message: String = "Ready") {
        if phase != .idle { appendDiagnostic("Cancel: \(message)") }
        resetGesture()
        generation = UUID(); task?.cancel(); task = nil
        recordingTimer?.invalidate(); recordingTimer = nil
        recorder.cancel(); insertion.restoreClipboard(); target = nil
        clearResult(); phase = .idle; level = 0; status = message
    }
    private func remember(_ text: String) {
        resultExpiry?.cancel(); lastResult = text
        resultExpiry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
            self?.lastResult = ""
        }
    }
    func clearResult() { resultExpiry?.cancel(); resultExpiry = nil; lastResult = "" }
    func copyResult() {
        guard !lastResult.isEmpty else { return }
        insertion.restoreClipboard()
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lastResult, forType: .string)
        clearResult(); status = "Copied to clipboard"
    }
}
