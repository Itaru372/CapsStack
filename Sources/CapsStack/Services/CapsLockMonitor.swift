@preconcurrency import ApplicationServices
@preconcurrency import CoreFoundation
@preconcurrency import CoreGraphics
import CapsStackLocalization
import Foundation

/// Polls the system Caps Lock flag without installing a global key event tap. This avoids
/// keystroke capture and does not require Accessibility/Input Monitoring permission.
/// When `suppressOriginalCapsLock` is enabled, an event tap is installed to swallow the
/// Caps Lock key so the original uppercase-toggling behaviour is disabled while CapsStack
/// still receives the trigger.
final class CapsLockMonitor: @unchecked Sendable {
    typealias ChangeHandler = @Sendable (Bool) -> Void

    private let lock = NSLock()
    private let pollingInterval: TimeInterval
    private let pollingQueue: DispatchQueue
    private let systemStateReader: @Sendable () -> Bool
    private let systemStateSetter: @Sendable (Bool) -> Void
    private var timer: DispatchSourceTimer?
    private var state: Bool
    private var handler: ChangeHandler?
    private var suppressOriginal: Bool = false
    private var syntheticState: Bool = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapRunLoop: CFRunLoop?

    private var running = false
    private var storedSuppressionError: String?
    private var suppressionActive = false

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    var suppressionError: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedSuppressionError
    }

    var isSuppressionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suppressionActive
    }

    var isCapsLockOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        if suppressOriginal && suppressionActive {
            return syntheticState
        }
        return state
    }

    /// Whether the monitor is currently swallowing the original Caps Lock behaviour.
    var isSuppressingOriginal: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suppressOriginal && suppressionActive
    }

    var onChange: ChangeHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return handler
        }
        set {
            lock.lock()
            handler = newValue
            lock.unlock()
        }
    }

    init(
        pollingInterval: TimeInterval = 0.25,
        queue: DispatchQueue? = nil,
        systemStateReader: @escaping @Sendable () -> Bool = { CapsLockMonitor.readSystemState() },
        systemStateSetter: @escaping @Sendable (Bool) -> Void = { CapsLockMonitor.setSystemCapsLock(on: $0) }
    ) {
        self.pollingInterval = max(0.05, pollingInterval)
        self.pollingQueue = queue ?? DispatchQueue(
            label: "com.capsstack.caps-lock-monitor",
            qos: .utility
        )
        self.systemStateReader = systemStateReader
        self.systemStateSetter = systemStateSetter
        self.state = systemStateReader()
    }

    /// Enable or disable swallowing the original Caps Lock typing behaviour.
    /// Returns true if the requested state was applied, false if permission is missing.
    @discardableResult
    func setSuppressionEnabled(_ enabled: Bool) -> Bool {
        lock.lock()
        let wasSuppressing = suppressOriginal
        suppressOriginal = enabled
        if !enabled {
            syntheticState = false
        }
        lock.unlock()

        // Restore a deterministic OFF state only when leaving active suppression. A normal app
        // launch with suppression already disabled must never alter the user's Caps Lock state.
        if !enabled, wasSuppressing, systemStateReader() {
            systemStateSetter(false)
        }

        if enabled == wasSuppressing {
            // Already in desired state; ensure tap matches
            if enabled {
                return installEventTap()
            } else {
                uninstallEventTap()
                return true
            }
        }

        if enabled {
            let ok = installEventTap()
            if !ok {
                // Roll back flag so UI can show error
                lock.lock()
                suppressOriginal = false
                lock.unlock()
            }
            return ok
        } else {
            uninstallEventTap()
            return true
        }
    }

    /// Starts polling. The initial value is available through `isCapsLockOn`; the callback is
    /// emitted only on a real ON/OFF transition.
    @discardableResult
    func start() -> Bool {
        lock.lock()
        guard timer == nil else {
            let shouldInstallTap = suppressOriginal
            lock.unlock()
            // Ensure event tap is consistent with suppression flag
            if shouldInstallTap {
                _ = installEventTap()
            }
            return true
        }
        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(
            deadline: .now() + pollingInterval,
            repeating: pollingInterval,
            leeway: .milliseconds(30)
        )
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        self.timer = timer
        running = true
        let shouldInstallTap = suppressOriginal
        lock.unlock()
        timer.resume()
        if shouldInstallTap {
            _ = installEventTap()
        }
        return true
    }

    func stop() {
        uninstallEventTap()
        lock.lock()
        guard let timer else {
            running = false
            lock.unlock()
            return
        }
        self.timer = nil
        running = false
        lock.unlock()
        timer.setEventHandler {}
        timer.cancel()
    }

    deinit {
        stop()
    }

    // MARK: - Polling (non-suppressed path)

    private func poll() {
        // When suppression is active we don't rely on system flag; syntheticState is driven by event tap.
        lock.lock()
        let suppressing = suppressOriginal && suppressionActive
        lock.unlock()
        if suppressing { return }

        let current = systemStateReader()
        lock.lock()
        guard current != state else {
            lock.unlock()
            return
        }
        state = current
        let callback = handler
        lock.unlock()

        guard let callback else { return }
        DispatchQueue.main.async {
            callback(current)
        }
    }

    private static func readSystemState() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    private static func setSystemCapsLock(on: Bool) {
        let current = readSystemState()
        guard current != on else { return }
        // Toggle by injecting a Caps Lock key event; this is the only public way to flip the flag.
        let loc = CGEventTapLocation.cghidEventTap
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: 57, keyDown: true),
           let up = CGEvent(keyboardEventSource: nil, virtualKey: 57, keyDown: false) {
            down.post(tap: loc)
            up.post(tap: loc)
        }
    }

    // MARK: - Event Tap (suppressed path)

    private func installEventTap() -> Bool {
        // Already installed
        lock.lock()
        let alreadyInstalled = eventTap != nil
        lock.unlock()
        if alreadyInstalled { return true }

        // Check accessibility trust
        let trusted = AXIsProcessTrusted()
        if !trusted {
            lock.lock()
            storedSuppressionError = CapsStackText.resolve(.accessibilityPermissionMessage)
            suppressionActive = false
            lock.unlock()
            // Prompt system dialog (will show if we try to create tap, but also explicit)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return false
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<CapsLockMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleTap(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lock.lock()
            storedSuppressionError = CapsStackText.resolve(.capsLockMonitoringFailed)
            suppressionActive = false
            lock.unlock()
            return false
        }

        let queue = DispatchQueue(label: "com.capsstack.caps-lock-tap", qos: .userInteractive)
        if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            lock.lock()
            eventTap = tap
            runLoopSource = source
            suppressionActive = true
            storedSuppressionError = nil
            // Sync synthetic state to current system state on entry.
            syntheticState = state
            lock.unlock()
            queue.async { [weak self] in
                guard let runLoop = CFRunLoopGetCurrent() else { return }
                self?.storeEventTapRunLoop(runLoop)
                CFRunLoopAddSource(runLoop, source, .commonModes)
                CFRunLoopRun()
                self?.clearEventTapRunLoop(ifMatching: runLoop)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            // Make sure system CapsLock LED is off while suppressed
            if systemStateReader() {
                systemStateSetter(false)
            }
            return true
        } else {
            CFMachPortInvalidate(tap)
            lock.lock()
            eventTap = nil
            storedSuppressionError = CapsStackText.resolve(.eventTapRegistrationFailed)
            suppressionActive = false
            lock.unlock()
            return false
        }
    }

    private func uninstallEventTap() {
        lock.lock()
        guard let tap = eventTap else {
            lock.unlock()
            return
        }
        let source = runLoopSource
        let runLoop = eventTapRunLoop
        suppressionActive = false
        eventTap = nil
        runLoopSource = nil
        eventTapRunLoop = nil
        lock.unlock()
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let source {
            CFRunLoopSourceInvalidate(source)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    private func storeEventTapRunLoop(_ runLoop: CFRunLoop) {
        lock.lock()
        eventTapRunLoop = runLoop
        lock.unlock()
    }

    private func clearEventTapRunLoop(ifMatching runLoop: CFRunLoop) {
        lock.lock()
        if eventTapRunLoop === runLoop {
            eventTapRunLoop = nil
        }
        lock.unlock()
    }

    private func handleTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = eventTap
            lock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        // Caps Lock is keycode 57 (kVK_CapsLock). Only swallow that key.
        guard keycode == 57 else {
            return Unmanaged.passUnretained(event)
        }

        // For flagsChanged, we toggle syntheticState and swallow the event so system doesn't toggle uppercase.
        // Also swallow keyDown/keyUp for Caps Lock if they appear.
        if type == .flagsChanged || type == .keyDown || type == .keyUp {
            lock.lock()
            // Only handle on flagsChanged's down-like transition to avoid double toggle (keyDown+flagsChanged)
            // Caps Lock generates flagsChanged both for on and off; swallow both and toggle synthetic.
            // To avoid double handling, only toggle on flagsChanged.
            let shouldToggle = (type == .flagsChanged)
            var newState: Bool = syntheticState
            var callback: ChangeHandler?
            if shouldToggle {
                syntheticState.toggle()
                newState = syntheticState
                state = newState // keep state in sync for isCapsLockOn
                callback = handler
            }
            lock.unlock()

            if shouldToggle, let callback {
                let callbackState = newState
                DispatchQueue.main.async {
                    callback(callbackState)
                }
            }
            // Swallow so original Caps Lock typing is not triggered
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
