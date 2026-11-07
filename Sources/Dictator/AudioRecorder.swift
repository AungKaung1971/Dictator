import AVFoundation
import CoreAudio
import AudioToolbox
import DictatorCore

struct Microphone: Identifiable {
    let id: String
    let deviceID: AudioDeviceID
    let name: String
}

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var pcm = Data()
    private var peak: Float = 0
    private var recordingPeak: Float = 0
    private var accepting = false
    private var captureFailed = false
    static let maximumSeconds = 120
    var isRunning: Bool { engine?.isRunning == true }
    var level: Float { lock.lock(); defer { lock.unlock() }; return peak }

    static func microphones() -> [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            func property(_ selector: AudioObjectPropertySelector) -> String? {
                var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: Unmanaged<CFString>?
                var count = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                guard AudioObjectGetPropertyData(device, &a, 0, nil, &count, &value) == noErr else { return nil }
                return value?.takeRetainedValue() as String?
            }
            guard let uid = property(kAudioDevicePropertyDeviceUID), let name = property(kAudioObjectPropertyName) else { return nil }
            return Microphone(id: uid, deviceID: device, name: name)
        }
    }

    func start(microphone: String) throws {
        cancel()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if !microphone.isEmpty {
            guard let device = Self.microphones().first(where: { $0.id == microphone }), let unit = input.audioUnit else {
                throw DictationError.message("The selected microphone is disconnected. Choose another in Settings.")
            }
            var deviceID = device.deviceID
            guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout.size(ofValue: deviceID))) == noErr else {
                throw DictationError.message("Could not select this microphone. Try System Default in Settings.")
            }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else {
            throw DictationError.message("Microphone format is unavailable. Check the audio device in System Settings.")
        }
        lock.lock(); pcm = Data(); peak = 0; recordingPeak = 0; accepting = true; captureFailed = false; lock.unlock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / format.sampleRate)) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return buffer
            }
            guard status != .error, error == nil, let samples = output.floatChannelData?[0] else {
                self.lock.lock(); self.captureFailed = true; self.lock.unlock(); return
            }
            var data = Data(capacity: Int(output.frameLength) * 2)
            var maximum: Float = 0
            for index in 0..<Int(output.frameLength) {
                let sample = max(-1, min(1, samples[index]))
                maximum = max(maximum, abs(sample))
                var integer = Int16(sample * 32767).littleEndian
                withUnsafeBytes(of: &integer) { data.append(contentsOf: $0) }
            }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.accepting else { return }
            let available = Self.maximumSeconds * 32000 - self.pcm.count
            if available > 0 { self.pcm.append(data.prefix(available)) }
            self.peak = maximum
            self.recordingPeak = max(self.recordingPeak, maximum)
        }
        self.engine = engine
        do { try engine.start() } catch { cancel(); throw DictationError.message("Could not start the microphone. Check permission and your audio device.") }
    }

    func finish() throws -> Data {
        stopEngine()
        lock.lock(); defer { lock.unlock() }
        defer { pcm = Data(); peak = 0 }
        guard !captureFailed else { throw DictationError.message("Microphone audio conversion failed. Choose another microphone and retry.") }
        guard recordingPeak > 0.001 else { throw DictationError.message("No microphone signal detected. Check the selected input and try again.") }
        guard pcm.count >= 6400 else { throw DictationError.message("Recording was too short. Hold the shortcut while speaking.") }
        return AudioPayload.wav(pcm: pcm)
    }
    private func stopEngine() {
        lock.lock(); accepting = false; lock.unlock()
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
    }
    func cancel() {
        stopEngine()
        lock.lock(); pcm = Data(); peak = 0; lock.unlock()
    }
}
