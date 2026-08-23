//  AppServices.swift
//  The process-wide objects, reachable from both the AppDelegate and the
//  SwiftUI Settings scene — which are constructed independently and have no
//  other way to meet.

import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let preferences = Preferences.shared
    lazy var coordinator = MonitorCoordinator(preferences: preferences)

    private init() {}
}
