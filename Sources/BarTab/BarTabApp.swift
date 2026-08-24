// BarTabApp.swift
//
// Entry point. MenuBarExtra in window style is the entire UI surface —
// no Dock icon, no main window (LSUIElement true, set via project.yml).

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
    }
}
