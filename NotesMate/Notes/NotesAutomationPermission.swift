import AppKit
import Carbon

enum NotesAutomationPermission {
    private static let needsAuthorizationKey = "NotesMate.notesAutomation.needsAuthorization"
    private static let isAuthorizedKey = "NotesMate.notesAutomation.isAuthorized"
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    static var needsAuthorization: Bool {
        needsAuthorization(in: .standard)
    }

    static var shouldShowAuthorizationMenu: Bool {
        shouldShowAuthorizationMenu(in: .standard)
    }

    static func shouldShowAuthorizationMenu(in defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: isAuthorizedKey) || needsAuthorization(in: defaults)
    }

    static func needsAuthorization(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: needsAuthorizationKey)
    }

    static func isAuthorizationError(_ number: Int) -> Bool {
        number == Int(errAEEventNotPermitted) || number == Int(errAEEventWouldRequireUserConsent)
    }

    static func recordScriptError(_ number: Int, defaults: UserDefaults = .standard) {
        if isAuthorizationError(number) {
            defaults.set(true, forKey: needsAuthorizationKey)
            defaults.removeObject(forKey: isAuthorizedKey)
        }
    }

    static func recordScriptSuccess(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: needsAuthorizationKey)
        defaults.set(true, forKey: isAuthorizedKey)
    }

    @discardableResult
    static func determine(for notes: NSRunningApplication, askUserIfNeeded: Bool) -> OSStatus {
        var pid = notes.processIdentifier
        var target = AEAddressDesc()
        let creationStatus = AECreateDesc(DescType(typeKernelProcessID), &pid, MemoryLayout<pid_t>.size, &target)
        guard creationStatus == noErr else { return OSStatus(creationStatus) }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUserIfNeeded)
        if status == noErr {
            recordScriptSuccess()
        } else {
            recordScriptError(Int(status))
        }
        return status
    }

    /// Reconcile the cached menu state without triggering a permission prompt.
    /// Apple requires the target application to be running for this check.
    static func refreshIfNotesIsRunning() {
        guard let notes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first else { return }
        determine(for: notes, askUserIfNeeded: false)
    }
}
