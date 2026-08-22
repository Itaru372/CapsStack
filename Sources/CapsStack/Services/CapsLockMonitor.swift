import ApplicationServices
import CoreGraphics
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
    private var timer: DispatchSourceTimer?
    private var state: Bool
    private var handler: ChangeHandler?
    private var suppressOriginal: Bool = false
    private var syntheticState: Bool = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapQueue: DispatchQueue?

    private(set) var isRunning = false
    private(set) var suppressionError: String?
    private(set) var isSuppressionActive: Bool = false

    var isCapsLockOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        if suppressOriginal && isSuppressionActive {
            return syntheticState
        }
        return state
    }

    /// Whether the monitor is currently swallowing the original Caps Lock behaviour.
    var isSuppressingOriginal: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suppressOriginal && isSuppressionActive
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

    init(pollingInterval: TimeInterval = 0.25, queue: DispatchQueue? = nil) {
        self.pollingInterval = max(0.05, pollingInterval)
        self.pollingQueue = queue ?? DispatchQueue(
            label: "com.capsstack.caps-lock-monitor",
            qos: .utility
        )
        self.state = Self.readSystemState()
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
            // Ensure system Caps Lock is off when leaving suppression mode
            if Self.readSystemState() {
                Self.setSystemCapsLock(on: false)
            }
        }
        lock.unlock()

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
            lock.unlock()
            // Ensure event tap is consistent with suppression flag
            if suppressOriginal {
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
        isRunning = true
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
            isRunning = false
            lock.unlock()
            return
        }
        self.timer = nil
        isRunning = false
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
        let suppressing = suppressOriginal && isSuppressionActive
        lock.unlock()
        if suppressing { return }

        let current = Self.readSystemState()
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
        if eventTap != nil { return true }

        // Check accessibility trust
        let trusted = AXIsProcessTrusted()
        if !trusted {
            lock.lock()
            suppressionError = "アクセシビリティの許可が必要です。システム設定 > プライバシーとセキュリティ > アクセシビリティ で CapsStack を許可してください。"
            isSuppressionActive = false
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
            suppressionError = "Caps Lock の監視を開始できませんでした。アクセシビリティ権限を確認してください。"
            isSuppressionActive = false
            lock.unlock()
            return false
        }

        let queue = DispatchQueue(label: "com.capsstack.caps-lock-tap", qos: .userInteractive)
        eventTapQueue = queue
        eventTap = tap
        if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            runLoopSource = source
            queue.async {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CFRunLoopRun()
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            lock.lock()
            isSuppressionActive = true
            suppressionError = nil
            // Sync synthetic state to current system state on entry, then ensure system Caps stays off
            syntheticState = state
            lock.unlock()
            // Make sure system CapsLock LED is off while suppressed
            if Self.readSystemState() {
                Self.setSystemCapsLock(on: false)
            }
            return true
        } else {
            CFMachPortInvalidate(tap)
            eventTap = nil
            lock.lock()
            suppressionError = "イベントタップの登録に失敗しました。"
            isSuppressionActive = false
            lock.unlock()
            return false
        }
    }

    private func uninstallEventTap() {
        guard let tap = eventTap else { return }
        lock.lock()
        isSuppressionActive = false
        lock.unlock()
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let source = runLoopSource {
            // RunLoop source removal must happen on the tap queue's run loop; stopping the loop will clean it up.
            // For simplicity, just invalidate and let queue's run loop exit on next iteration.
            CFRunLoopSourceInvalidate(source)
        }
        eventTap = nil
        runLoopSource = nil
        // Stop the dedicated run loop if running
        eventTapQueue?.async {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        eventTapQueue = nil
    }

    private func handleTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
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
                DispatchQueue.main.async {
                    callback(newState)
                }
            }
            // Swallow so original Caps Lock typing is not triggered
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
