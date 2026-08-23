//  SettingsRootView.swift
//  Settings should look like macOS, not like the popover. The popover is the
//  instrument; this is the manual.

import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Services", systemImage: "square.grid.2x2") {
                ServicesSettingsView()
            }
            Tab("Notifications", systemImage: "bell") {
                NotificationSettingsView()
            }
            Tab("Appearance", systemImage: "paintbrush") {
                AppearanceSettingsView()
            }
        }
        .frame(width: 520)
        .scenePadding()
    }
}
