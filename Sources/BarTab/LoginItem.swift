// LoginItem.swift
//
// PRD §6.5 (locked): BarTab registers itself via `SMAppService.mainApp` on
// first run so it launches automatically at every login. There is no
// setting to disable this -- always on, by decision.
//
// Registration must be idempotent (safe to call every launch, not just
// "first run" -- there is no reliable, cheap way to know this is truly the
// very first launch without adding a UserDefaults flag that would itself
// need to survive a Settings reset, so "idempotent every launch" is the
// simpler and equally-correct reading of "on first run") and must never
// crash or block the app's own startup if it throws -- a failed login-item
// registration is not something the disk/Claude tiles should ever reflect,
// per the "degrade, don't crash" product principle.
//
// Known caveat, reported honestly rather than assumed away (see
// _review/phase5/ACCEPTANCE.md for what was actually observed on this
// machine): `SMAppService` keys registration off the running app's bundle
// identity and path. A Debug build launched from a `/tmp` DerivedData
// output (this project's standing build rule) is not the same installed,
// stable-path app System Settings > Login Items expects, so `register()`
// may throw, or may succeed while `.status` reports something other than
// `.enabled` (e.g. `.notRegistered` or `.requiresApproval`). This is a
// build-location artifact of local development, not a defect in this code.

import ServiceManagement
import os.log

enum LoginItem {
    private static let log = Logger(subsystem: "com.levelup.bartab", category: "LoginItem")

    /// Registers BarTab as a login item, best-effort, idempotent, never
    /// throwing out. Call once at app startup (`AppModel.init`).
    static func registerIfNeeded() {
        let service = SMAppService.mainApp

        if service.status == .enabled {
            log.info("Login item already enabled (status=.enabled); register() skipped.")
            return
        }

        do {
            try service.register()
            log.info("Login item register() returned normally; status is now \(String(describing: service.status), privacy: .public).")
        } catch {
            // Non-fatal: log and move on. Never surfaced to the user --
            // no notification, no UI -- and never blocks the disk/Claude
            // tiles from starting.
            log.warning("Login item register() threw (non-fatal, app continues): \(error.localizedDescription, privacy: .public); status remains \(String(describing: service.status), privacy: .public).")
        }
    }

    /// Current status, exposed for diagnostics/evidence capture only (PRD
    /// §11's "registered as a login item" acceptance line). Not read by any
    /// product-facing UI -- PRD §6.4 is explicit that login-at-login has no
    /// control in Settings.
    static var currentStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }
}
