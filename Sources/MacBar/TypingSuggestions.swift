import AppKit
import ApplicationServices
import Carbon.HIToolbox

extension Notification.Name {
    static let typingSuggestionsChanged = Notification.Name("dev.macbar.typingSuggestionsChanged")
}

final class TypingSuggestions {
    static let shared = TypingSuggestions()
    static let enabledKey = "typingSuggestionsEnabled"

    struct Suggestion: Equatable {
        let display: String
        let text: String
        let deleteCount: Int
    }

    private enum Target {
        case accessibility(AXUIElement, caret: Int)
        case keystrokes
    }

    private(set) var suggestions: [Suggestion] = []
    private var observer: AXObserver?
    private var target: Target?
    private var frontmost: NSRunningApplication?
    private var keyMonitor: Any?
    private var typed = ""
    private var ignoreKeysUntil = Date.distantPast
    private var justAccepted = false
    private var pending: DispatchWorkItem?
    private var generation = 0
    private var running = false
    private let spellTag = NSSpellChecker.uniqueSpellDocumentTag()
    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXWebArea"]

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func start(prompt: Bool) {
        guard Self.isEnabled, !running else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        DistributedNotificationCenter.default().removeObserver(self)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(trustChanged),
                                                            name: NSNotification.Name("com.apple.accessibility.api"), object: nil)
        guard AXIsProcessTrustedWithOptions(options) else { return }
        running = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            self?.handle(event)
        }
        if let app = NSWorkspace.shared.frontmostApplication { attach(to: app) }
    }

    func stop() {
        running = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        detach()
        publish([])
    }

    @objc private func trustChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start(prompt: false) }
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(to: app)
    }

    private func handle(_ event: NSEvent) {
        guard Date() >= ignoreKeysUntil else { return }
        if justAccepted {
            justAccepted = false
            if event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               let key = event.characters, key == " " || [".", ",", "!", "?", ";", ":"].contains(key) {
                mergeAfterAccept(key)
                return
            }
        }
        if event.type == .leftMouseDown {
            typed = ""
        } else if !event.modifierFlags.intersection([.command, .control]).isEmpty {
            typed = ""
        } else {
            switch Int(event.keyCode) {
            case kVK_Delete: if !typed.isEmpty { typed.removeLast() }
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape,
                 kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_ForwardDelete:
                typed = ""
            default:
                typed += event.characters ?? ""
                if typed.count > 120 { typed = String(typed.suffix(80)) }
            }
        }
        scheduleEvaluate()
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        target = nil
    }

    private func attach(to app: NSRunningApplication) {
        detach()
        typed = ""
        frontmost = app
        publish([])
        let pid = app.processIdentifier
        guard pid != getpid() else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if Self.isChromiumBrowser(app) {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<TypingSuggestions>.fromOpaque(refcon).takeUnretainedValue().scheduleEvaluate()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXValueChangedNotification, kAXSelectedTextChangedNotification, kAXFocusedUIElementChangedNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    private func scheduleEvaluate() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private func accessibilityContext(_ focused: AXUIElement) -> (text: String, caret: Int)? {
        guard let rangeRef = copy(focused, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection), selection.length == 0 else { return nil }
        let caret = selection.location
        let lookback = min(caret, 80)
        var range = CFRange(location: caret - lookback, length: lookback)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString,
                                                          rangeValue, &result) == .success, let text = result as? String {
                return (text, caret)
            }
        }
        guard let value = copy(focused, kAXValueAttribute) as? String else { return nil }
        let text = value as NSString
        guard caret <= text.length else { return nil }
        return (text.substring(with: NSRange(location: caret - lookback, length: lookback)), caret)
    }

    private func evaluate() {
        guard running, !IsSecureEventInputEnabled(),
              let focusedRef = copy(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return publish([]) }
        let focused = focusedRef as! AXUIElement
        let role = copy(focused, kAXRoleAttribute) as? String ?? ""
        let subrole = copy(focused, kAXSubroleAttribute) as? String
        guard role != "AXSecureTextField", subrole != "AXSecureTextField" else { return publish([]) }

        let context: String
        if let ax = accessibilityContext(focused), !ax.text.isEmpty {
            context = ax.text
            target = Self.prefersKeystrokes(frontmost) ? .keystrokes : .accessibility(focused, caret: ax.caret)
        } else if Self.textRoles.contains(role), !typed.isEmpty {
            context = typed
            target = .keystrokes
        } else {
            return publish([])
        }

        generation += 1
        let request = generation
        let length = (context as NSString).length
        let word = Self.trailingWord(context)
        let correction = word.isEmpty ? nil : NSSpellChecker.shared.correction(
            forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word,
            language: NSSpellChecker.shared.language(), inSpellDocumentWithTag: spellTag)
        NSSpellChecker.shared.requestCandidates(forSelectedRange: NSRange(location: length, length: 0), in: context,
                                                types: NSTextCheckingAllSystemTypes, options: nil,
                                                inSpellDocumentWithTag: spellTag) { [weak self] _, results in
            let candidates = results.compactMap { result -> (String, Int)? in
                guard let text = result.replacementString, NSMaxRange(result.range) == length else { return nil }
                return (text, result.range.length)
            }
            DispatchQueue.main.async {
                guard let self, request == self.generation else { return }
                self.publish(Self.build(word: word, correction: correction, candidates: candidates))
            }
        }
    }

    static func build(word: String, correction: String?, candidates: [(String, Int)]) -> [Suggestion] {
        let wordLength = (word as NSString).length
        var seen: Set<String> = [word.lowercased()]
        var list: [Suggestion] = []
        if !word.isEmpty {
            list.append(Suggestion(display: "“\(word)”", text: word + " ", deleteCount: wordLength))
            if let correction, seen.insert(correction.lowercased()).inserted {
                list.append(Suggestion(display: correction, text: correction + " ", deleteCount: wordLength))
            }
        }
        for (text, deleteCount) in candidates where list.count < 3 && seen.insert(text.lowercased()).inserted {
            list.append(Suggestion(display: text, text: text + " ", deleteCount: deleteCount))
        }
        return list
    }

    static func trailingWord(_ text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars.reversed() {
            guard CharacterSet.letters.contains(scalar) || scalar == "'" || scalar == "’" else { break }
            scalars.append(scalar)
        }
        let word = String(String.UnicodeScalarView(scalars.reversed()))
        return word.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
    }

    private static func isChromiumBrowser(_ app: NSRunningApplication) -> Bool {
        let chromium = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser"]
        return app.bundleIdentifier.map { id in chromium.contains(where: id.hasPrefix) } ?? false
    }

    private static func prefersKeystrokes(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if isChromiumBrowser(app) { return true }
        guard let bundle = app.bundleURL else { return false }
        let electron = bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: electron.path)
    }

    private func publish(_ new: [Suggestion]) {
        guard new != suggestions else { return }
        suggestions = new
        NotificationCenter.default.post(name: .typingSuggestionsChanged, object: nil)
    }

    func apply(_ suggestion: Suggestion) {
        guard let target else { return }
        var replaced = false
        if case let .accessibility(element, caret) = target {
            var range = CFRange(location: caret - suggestion.deleteCount, length: suggestion.deleteCount)
            replaced = AXValueCreate(.cfRange, &range).map {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, $0) == .success
                    && AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, suggestion.text as CFString) == .success
            } ?? false
        }
        if !replaced {
            ignoreKeysUntil = Date().addingTimeInterval(0.3)
            Self.postBackspaces(suggestion.deleteCount)
            Self.postText(suggestion.text)
        }
        typed = String(typed.dropLast(suggestion.deleteCount)) + suggestion.text
        justAccepted = suggestion.text.hasSuffix(" ")
        publish([])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.scheduleEvaluate() }
    }

    private func mergeAfterAccept(_ key: String) {
        ignoreKeysUntil = Date().addingTimeInterval(0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            if key == " " {
                Self.postBackspaces(1)
            } else {
                Self.postBackspaces(2)
                Self.postText(key + " ")
            }
        }
        if key != " " { typed = String(typed.dropLast()) + key + " " }
        scheduleEvaluate()
    }

    private static func postBackspaces(_ count: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    private static func postText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        for start in stride(from: 0, to: units.count, by: 16) {
            var chunk = Array(units[start..<min(start + 16, units.count)])
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
