import SwiftUI
import DictatorCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @State private var apiKey = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 38)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dictator").font(.title2.bold())
                    Text("Speak naturally. Keep your train of thought.").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            TabView {
                setup.tabItem { Label("Setup", systemImage: "checkmark.shield") }
                dictation.tabItem { Label("Dictation", systemImage: "mic") }
                privacy.tabItem { Label("Privacy", systemImage: "lock") }
            }.padding(.horizontal, 20).padding(.bottom, 20)
            Divider()
            Text(model.status).font(.callout).foregroundStyle(.secondary)
                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }.frame(width: 600, height: 600)
            .onAppear { model.refreshPermissions(); model.refreshDevices() }
    }
    private var setup: some View {
        Form {
            Section("Permissions") {
                permissionRow("Microphone", granted: model.microphoneAllowed) {
                    if model.microphoneAllowed { model.openPrivacy("Microphone") } else { model.requestMicrophone() }
                }
                permissionRow("Accessibility", granted: model.accessibility, action: model.requestAccessibility)
                if model.accessibility && !model.shortcutReady {
                    Text("Shortcut monitoring is unavailable. Enable Input Monitoring below, then quit and reopen Dictator.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Open Input Monitoring") { model.openPrivacy("ListenEvent") }
                }
            }
            Section("Startup") {
                Toggle("Open Dictator when I log in", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                Text(model.loginMessage).font(.caption).foregroundStyle(.secondary)
            }
            Section("OpenAI API key") {
                SecureField(model.keySaved ? "Enter a replacement API key" : "Paste your API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("OpenAI API key")
                HStack {
                    Button("Save in Keychain") { model.saveKey(apiKey); apiKey = "" }.disabled(apiKey.isEmpty)
                    Button("Check model access", action: model.verifyKey).disabled(!model.keySaved)
                    Spacer()
                    if model.keySaved { Button("Remove", action: model.deleteKey) }
                }
                Text(model.keyMessage.isEmpty ? (model.keySaved ? "A key is saved in macOS Keychain." : "Your key stays on this Mac and is sent only to api.openai.com.") : model.keyMessage)
                    .font(.caption).foregroundStyle(.secondary)
                Link("Open API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                Text("Check available credits and billing in your OpenAI API project. Dictator cannot infer your API balance from a ChatGPT subscription.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? .green : .secondary)
            Text(title); Spacer()
            Button(granted ? "Open Settings" : "Allow…", action: action)
        }
    }
    private var dictation: some View {
        Form {
            Section("Recording shortcut") {
                Picker("Shortcut", selection: $settings.shortcut) {
                    ForEach(Shortcut.allCases) { Text($0.label).tag($0) }
                }
                if settings.shortcut == .fn {
                    Text("In System Settings → Keyboard, set ‘Press Fn / 🌐 key to’ to ‘Do Nothing’. Disable macOS Dictation’s Fn shortcut if it conflicts.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(model.fnSeen ? "✓ Fn key events detected on this keyboard" : "Press Fn to check detection. If it is not detected, choose a fallback above.")
                        .font(.caption).foregroundStyle(model.fnSeen ? .green : .secondary)
                }
                Text(settings.shortcut == .fn
                     ? "Hold Fn to speak; release to finish. Double-tap Fn quickly for hands-free recording, then press Fn once to finish. Keep the cursor in place until insertion completes. Typing, clicking or changing apps cancels."
                     : "Hold the shortcut, speak, then release. Keep the cursor in place until insertion finishes. Typing, clicking or switching apps cancels dictation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcut diagnostics") {
                Text(model.shortcutReady ? "Keyboard listener is running." : "Keyboard listener is unavailable.")
                DisclosureGroup("Recent Fn events (no audio or typed text)") {
                    Text(model.shortcutDiagnostics.isEmpty ? "Press Fn to see its key events." : model.shortcutDiagnostics)
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                }
            }
            Section("Microphone") {
                Picker("Input", selection: $settings.microphone) {
                    Text("System Default").tag("")
                    ForEach(model.microphones) { Text($0.name).tag($0.id) }
                    if !settings.microphone.isEmpty && !model.microphones.contains(where: { $0.id == settings.microphone }) {
                        Text("Disconnected microphone").tag(settings.microphone)
                    }
                }
                Button("Refresh microphones", action: model.refreshDevices)
            }
            Section("AI preferences") {
                Toggle("Clean up grammar, fillers and false starts", isOn: $settings.cleanup)
                Toggle("Use British English spelling", isOn: $settings.britishEnglish)
                Picker("Cleanup model", selection: $settings.correctionModel) {
                    Text("GPT-4.1 mini · balanced").tag("gpt-4.1-mini")
                    Text("GPT-4.1 nano").tag("gpt-4.1-nano")
                    Text("GPT-5.4 nano · no reasoning").tag("gpt-5.4-nano")
                    Text("GPT-6 Luna · no reasoning").tag("gpt-6-luna")
                }
                Text("Speech recognition: GPT Transcribe").font(.caption).foregroundStyle(.secondary)
                TextField("Names and technical terms, separated by commas", text: $settings.vocabulary, axis: .vertical)
                    .lineLimit(2...3)
            }
        }.formStyle(.grouped).disabled(model.phase != .idle)
    }
    private var privacy: some View {
        Form {
            Section("Only what you dictate") {
                Text("Audio is captured while you hold the shortcut, during the brief double-tap detection window, or in hands-free mode, for up to two minutes. Recordings stay in memory and are released after processing or cancellation.")
                Text("Your recording and vocabulary hints go to OpenAI for transcription. Cleanup sends the transcript to OpenAI with response storage disabled. OpenAI’s API retention policies still apply.")
                Text("Dictator does not upload surrounding text, screenshots, clipboard contents or window titles. It checks local Accessibility information to avoid unsafe insertion.")
                Text("No transcript history, analytics or accounts. A failed result is kept in memory for up to five minutes so you can copy it. Starting a new dictation discards it.")
            }
            Section("Insertion") {
                Text("Dictator uses direct Accessibility insertion in TextEdit. In other apps it pastes and restores the previous clipboard after a short delay, unless you have copied something new.")
                Text("Protected fields and fields that cannot be identified are blocked. Sensitive-field detection depends on the information the target app exposes; avoid dictating secrets.")
            }
        }.formStyle(.grouped).font(.callout)
    }
}

struct IndicatorView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            if model.phase == .recording {
                Image(systemName: model.handsFree ? "lock.fill" : "mic.fill").foregroundStyle(.red)
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<7) { index in
                        Capsule().fill(Color.accentColor).frame(width: 3, height: CGFloat(5 + min(1, model.level * 4) * Float([14, 24, 18, 30, 18, 24, 14][index])))
                    }
                }.frame(width: 42, height: 34)
                Text("\(model.seconds)s").monospacedDigit().foregroundStyle(.secondary)
                if model.handsFree { Text("Fn to finish").font(.caption) }
            } else {
                ProgressView().controlSize(.small)
                Text(model.status).lineLimit(1)
            }
        }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 18)
            .frame(width: 310, height: 52)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
    }
}
