// BarTabApp.swift
//
// Entry point. MenuBarExtra in window style is the entire UI surface —
// no Dock icon, no main window (LSUIElement true, set via project.yml).
//
// The Settings scene (Phase 2) adds a second, ordinary window scene. It's
// reachable with no App menu/Cmd-, (LSUIElement has neither) because
// FlyoutView's gear menu calls the `openSettings` environment action
// directly, which SwiftUI provides app-wide once a `Settings` scene exists
// in the body, regardless of how it's triggered.

import SwiftUI

@main
struct BarTabApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            FlyoutView(model: model)
        } label: {
            MenuBarIconView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
