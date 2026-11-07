import AppKit
import DictatorCore

// Mutable event state is confined to eventQueue; UI callbacks are confined to MainActor.
struct ShortcutActivity: Sendable {
    let timestamp: TimeInterval
    let description: String
}
final class ShortcutMonitor: @unchecked Sendable {
    private final class TapContext {
        weak var owner: ShortcutMonitor?
        let id = UUID()
        init(_ owner: ShortcutMonitor) { self.owner = owner }
    }
    private let queueKey = DispatchSpecificKey<Bool>()
    private var tapID: UUID?
    init() { eventQueue.setSpecific(key: queueKey, value: true) }
    // Serialise key edges and the double-tap deadline independently of microphone/UI work.
    private let eventQueue = DispatchQueue(label: "local.dictator.shortcuts", qos: .userInteractive)
    private var selectedShortcut: Shortcut = .fn
    var shortcut: Shortcut {
        get { eventQueue.sync { selectedShortcut } }
        set { eventQueue.sync { selectedShortcut = newValue } }
    }
    @MainActor var onPress: (() -> Void)?
    @MainActor var onRelease: (() -> Void)?
    @MainActor var onHandsFree: (() -> Void)?
    @MainActor var onCancel: (() -> Void)?
    @MainActor var onActivity: ((ShortcutActivity) -> Void)?
    @MainActor var onDiagnostic: ((String) -> Void)?
    @MainActor var onFnSeen: (() -> Void)?
    private var tap: CFMachPort?
    private var eventRunLoop: CFRunLoop?
    private var gesture = FnRecordingGesture()
    private var deadlineTimer: DispatchSourceTimer?
    private var state = HoldState()
    private var spaceClaimed = false
    private var fnBlocked = false
    static let syntheticTag: Int64 = 0x4449435441544F52
    var running: Bool { eventQueue.sync { tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false } }

    func start() -> Bool {
        stop()
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = TapContext(self)
        let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
            guard let monitor = context.owner else { return Unmanaged.passUnretained(event) }
            return monitor.handle(type, event, session: context.id) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(context).toOpaque())
        guard let created else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)!
        let ready = DispatchSemaphore(value: 0)
        let worker = Thread { [weak self] in
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, source, .commonModes)
            self?.eventQueue.sync { self?.tap = created; self?.eventRunLoop = loop; self?.tapID = context.id }
            CGEvent.tapEnable(tap: created, enable: true)
            ready.signal()
            withExtendedLifetime(context) { CFRunLoopRun() }
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        worker.name = "Dictator keyboard events"
        worker.qualityOfService = .userInteractive
        worker.start()
        ready.wait()
        return true
    }
    deinit {
        if DispatchQueue.getSpecific(key: queueKey) == true { stopOnQueue() }
        else { stop() }
    }
    func stop() { eventQueue.sync { stopOnQueue() } }
    private func stopOnQueue() {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
            if let eventRunLoop { CFRunLoopStop(eventRunLoop); CFRunLoopWakeUp(eventRunLoop) }
            tap = nil; eventRunLoop = nil; tapID = nil
            state = HoldState(); spaceClaimed = false; fnBlocked = false
            clearGesture()
    }
    func resetRecordingGesture() { eventQueue.sync { clearGesture() } }
    private func clearGesture() {
        deadlineTimer?.cancel(); deadlineTimer = nil; gesture.reset()
    }
    private func deliver(_ action: FnRecordingGesture.Action?) {
        guard let action else { return }
        trace("Action: \(action)")
        DispatchQueue.main.async { [weak self] in
            switch action {
            case .start: self?.onPress?()
            case .stop: self?.onRelease?()
            case .handsFree: self?.onHandsFree?()
            }
        }
    }
    private func trace(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onDiagnostic?(message) }
    }
    private func edge(_ down: Bool, timestamp: CGEventTimestamp) {
        guard let changed = state.update(down: down) else { return }
        guard selectedShortcut == .fn else { deliver(changed ? .start : .stop); return }
        let time = Double(timestamp) / 1_000_000_000
        deadlineTimer?.cancel(); deadlineTimer = nil
        deliver(changed ? gesture.press(at: time) : gesture.release(at: time))
        if let deadline = gesture.pendingDeadline {
            let timer = DispatchSource.makeTimerSource(queue: eventQueue)
            // CGEvent timestamps and DispatchTime use the monotonic uptime clock.
            timer.schedule(deadline: DispatchTime(uptimeNanoseconds: UInt64(deadline * 1_000_000_000)))
            timer.setEventHandler { [weak self] in
                guard let self, self.gesture.pendingDeadline == deadline else { return }
                self.deliver(self.gesture.expire(at: deadline))
                self.deadlineTimer?.cancel(); self.deadlineTimer = nil
            }
            deadlineTimer = timer
            timer.resume()
        }
    }
    private func cancelHold() {
        clearGesture()
        _ = state.update(down: false)
        DispatchQueue.main.async { [weak self] in self?.onCancel?() }
    }
    func handle(_ type: CGEventType, _ event: CGEvent, session: UUID? = nil) -> Bool {
        eventQueue.sync {
            if let session, session != tapID { return false }
            return handleEvent(type, event)
        }
    }
    private func handleEvent(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelHold(); spaceClaimed = false; fnBlocked = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        // macOS 26 emits Globe key events (179) alongside Fn flagsChanged (63),
        // sometimes at RELEASE and in either order. Only the physical modifier
        // stream owns the gesture. The companion must neither cancel typing nor
        // generate another press/release. Pass it through to macOS unchanged.
        if selectedShortcut == .fn && code == 179 {
            trace("Fn companion 179 ignored, type=\(type.rawValue)")
            return false
        }
        let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift])
        let fnEvent = code == 63 && (type == .flagsChanged || type == .keyDown || type == .keyUp)
        if fnEvent {
            trace("Fn \(type.rawValue), down=\(event.flags.contains(.maskSecondaryFn)), t=\(event.timestamp)")
            DispatchQueue.main.async { [weak self] in self?.onFnSeen?() }
        }
        if selectedShortcut == .fn {
            // Keycode 63 distinguishes real Fn changes from arrows/function keys carrying the Fn flag.
            if fnEvent {
                let down = type == .keyDown || (type == .flagsChanged && event.flags.contains(.maskSecondaryFn))
                if !down { fnBlocked = false; edge(false, timestamp: event.timestamp) }
                else if modifiers.isEmpty && !fnBlocked { edge(true, timestamp: event.timestamp) }
            } else if state.held && (type == .keyDown || (type == .flagsChanged && !modifiers.isEmpty)) {
                fnBlocked = true; cancelHold() // Fn+arrows and function keys retain normal behaviour.
            }
        } else {
            let required: CGEventFlags = selectedShortcut == .controlOptionSpace ? [.maskControl, .maskAlternate] : [.maskControl, .maskShift]
            if type == .keyDown && code == 49 && (spaceClaimed || modifiers == required) {
                if !spaceClaimed { spaceClaimed = true; edge(true, timestamp: event.timestamp) }; return true
            }
            if type == .keyUp && code == 49 && spaceClaimed {
                spaceClaimed = false; edge(false, timestamp: event.timestamp); return true
            }
            if type == .flagsChanged && state.held && modifiers != required { edge(false, timestamp: event.timestamp) }
            if type == .keyDown && state.held { cancelHold() }
        }
        if (type == .keyDown && !fnEvent) || type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            let description = type == .keyDown ? (code >= 128 ? "special key \(code)" : "ordinary key") : "mouse click"
            let activity = ShortcutActivity(timestamp: Double(event.timestamp) / 1_000_000_000, description: description)
            DispatchQueue.main.async { [weak self] in self?.onActivity?(activity) }
        }
        return false
    }
}
