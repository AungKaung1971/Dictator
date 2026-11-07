import AppKit
import ApplicationServices
import Carbon
import DictatorCore

struct InsertionTarget {
    let pid: pid_t
    let bundleID: String?
    let element: AXUIElement
    let selection: CFRange?
    let valueHash: Int?
}

@MainActor final class TextInsertion {
    private var pendingRestore: (() -> Void)?
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func selection(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }
    private static func safe(_ element: AXUIElement) -> Bool {
        guard !IsSecureEventInputEnabled() else { return false }
        guard let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return false }
        if let enabled = attribute(element, kAXEnabledAttribute) as? Bool, !enabled { return false }
        if let editable = attribute(element, "AXEditable") as? Bool, !editable { return false }
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let node = current else { break }
            if attribute(node, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return false }
            if attribute(node, "AXProtectedContent") as? Bool == true { return false }
            let labels = [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", "AXDOMIdentifier"]
                .compactMap { attribute(node, $0) as? String }.joined(separator: " ").lowercased()
            if ["password", "passcode", "credit card", "card number", "security code", "cvv", "secret key", "api key", "one-time code", "verification code"].contains(where: labels.contains) { return false }
            if let parent = attribute(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
                current = unsafeBitCast(parent, to: AXUIElement.self)
            } else { current = nil }
        }
        return true
    }
    func capture() throws -> InsertionTarget {
        guard AXIsProcessTrusted() else { throw DictationError.message("Enable Dictator in System Settings → Privacy & Security → Accessibility.") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else {
            throw DictationError.message("Click a text field in another app, then hold your shortcut.")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        var focused = Self.attribute(application, kAXFocusedUIElementAttribute)
        if focused == nil {
            // Chromium/Electron lazily expose their text fields to assistive clients.
            // Ask for the accessibility tree before giving up; never paste blindly.
            _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if app.bundleIdentifier?.contains("Chrome") == true {
                _ = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
            for _ in 0..<4 {
                Thread.sleep(forTimeInterval: 0.06)
                focused = Self.attribute(application, kAXFocusedUIElementAttribute)
                if focused != nil { break }
            }
        }
        guard let raw = focused, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            throw DictationError.message("Cannot identify the focused text field. Enable accessibility support in the target app or try another field.")
        }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.3)
        guard Self.safe(element) else { throw DictationError.message("Dictation is disabled in protected, sensitive, or unrecognised fields.") }
        return InsertionTarget(pid: app.processIdentifier, bundleID: app.bundleIdentifier, element: element, selection: Self.selection(element),
                               valueHash: (Self.attribute(element, kAXValueAttribute) as? String)?.hashValue)
    }
    func validate(_ target: InsertionTarget) throws {
        let current = try capture()
        guard current.pid == target.pid, CFEqual(current.element, target.element),
              current.selection?.location == target.selection?.location,
              current.selection?.length == target.selection?.length,
              current.valueHash == target.valueHash else {
            throw DictationError.message("Focus or text changed. Your result is available in the menu; nothing was inserted.")
        }
    }
    func insert(_ text: String, into target: InsertionTarget) async throws -> Bool {
        // The shortcut's modifiers may still be physically held when the API finishes.
        for _ in 0..<40 {
            try Task.checkCancellation()
            if CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty else {
            throw DictationError.message("Release all modifier keys. Your result is available in the menu.")
        }
        try Task.checkCancellation()
        try validate(target)
        var settable = DarwinBoolean(false)
        // Chromium/Electron can report a successful AXSelectedText write without
        // updating the web editor. Use the normal paste path for those applications.
        if target.bundleID == "com.apple.TextEdit", AXUIElementIsAttributeSettable(target.element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue {
            let result = AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFString)
            if result == .success { return true }
            // A timeout may have partially applied the change. Never risk a duplicate paste.
            guard result == .attributeUnsupported || result == .notImplemented else {
                throw DictationError.message("The app could not confirm insertion. Check the field before copying the result from the menu.")
            }
        }
        try validate(target)
        restoreClipboard()
        let pasteboard = NSPasteboard.general
        var saved: [NSPasteboardItem] = []
        for old in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in old.types {
                guard let data = old.data(forType: type) else {
                    throw DictationError.message("The clipboard contains data that cannot be restored. Copy the result manually from the menu.")
                }
                copy.setData(data, forType: type)
            }
            saved.append(copy)
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw DictationError.message("Could not create the paste shortcut.")
        }
        try Task.checkCancellation()
        try validate(target)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            pasteboard.clearContents(); pasteboard.writeObjects(saved)
            throw DictationError.message("Could not put the result on the clipboard.")
        }
        let ownedChange = pasteboard.changeCount
        pendingRestore = {
            guard pasteboard.changeCount == ownedChange else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: ShortcutMonitor.syntheticTag)
        up.setIntegerValueField(.eventSourceUserData, value: ShortcutMonitor.syntheticTag)
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        // Apps read the pasteboard asynchronously. Never overwrite a subsequent user copy.
        try? await Task.sleep(nanoseconds: 900_000_000)
        restoreClipboard()
        try Task.checkCancellation()
        // A successful key event is not proof the editor accepted it. Do not retry
        // automatically: delayed editors could otherwise receive a duplicate.
        if let value = Self.attribute(target.element, kAXValueAttribute) as? String,
           value.contains(text), value.hashValue != target.valueHash { return true }
        if let original = target.selection, let current = Self.selection(target.element),
           current.length == 0, current.location == original.location + text.utf16.count,
           original.length > 0 || current.location != original.location { return true }
        return false
    }
    func restoreClipboard() { pendingRestore?(); pendingRestore = nil }
}
