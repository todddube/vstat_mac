//  Preferences.swift
//  Every user-facing setting, backed by UserDefaults. Phase 6 builds the UI;
//  the model lives here so the coordinator can read it from day one.

import Foundation
import Observation

enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable, Codable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var id: Int { rawValue }
    var duration: Duration { .seconds(rawValue) }

    /// 10% leeway lets the system coalesce our wake-ups with others. On a
    /// laptop that is the difference between a timer and a battery complaint.
    var tolerance: Duration { .seconds(max(5, rawValue / 10)) }

    var title: String {
        Duration.seconds(rawValue).formatted(
            .units(allowed: [.minutes], width: .wide)
        )
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case hub, pulse, minimal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hub:     return String(localized: "Hub")
        case .pulse:   return String(localized: "Pulse")
        case .minimal: return String(localized: "Minimal")
        }
    }
}

enum IconRenderMode: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Template glyph tinted by the system, with a coloured status pip. The
    /// native-looking default, and the only rendering guaranteed legible
    /// against a transparent menu bar over an arbitrary wallpaper.
    case monochromeWithPip
    /// Fully coloured glyph: louder, more informative, less native.
    case colour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monochromeWithPip: return String(localized: "Monochrome with status dot")
        case .colour:            return String(localized: "Full colour")
        }
    }
}

enum MotionLevel: String, CaseIterable, Identifiable, Sendable, Codable {
    case full, subtle, off
    var id: String { rawValue }

    var title: String {
        switch self {
        case .full:   return String(localized: "Full")
        case .subtle: return String(localized: "Subtle")
        case .off:    return String(localized: "Off")
        }
    }
}

enum MenuBarTextMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case none, shortLabel, affectedCount
    var id: String { rawValue }
}

enum NotificationSeverity: String, CaseIterable, Identifiable, Sendable, Codable {
    case minor, major, critical
    var id: String { rawValue }

    var threshold: StatusIndicator {
        switch self {
        case .minor:    return .minor
        case .major:    return .major
        case .critical: return .critical
        }
    }
}

@MainActor @Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.registrationDefaults)
    }

    private static let registrationDefaults: [String: Any] = [
        Key.refreshInterval: RefreshInterval.fiveMinutes.rawValue,
        Key.checkOnWake: true,
        Key.showInDock: false,
        Key.disabledServices: [String](),
        Key.iconStyle: MenuBarIconStyle.hub.rawValue,
        Key.iconRenderMode: IconRenderMode.monochromeWithPip.rawValue,
        Key.showBadgeCount: true,
        Key.menuBarTextMode: MenuBarTextMode.none.rawValue,
        Key.motionLevel: MotionLevel.full.rawValue,
        Key.notifyOnDegradation: true,
        Key.notifyOnRecovery: true,
        Key.notifyMinimumSeverity: NotificationSeverity.minor.rawValue,
        Key.notifyPrimaryOnly: true,
        Key.notifySound: false,
        Key.notifyCooldownMinutes: 15
    ]

    enum Key {
        static let refreshInterval = "refreshInterval"
        static let checkOnWake = "checkOnWake"
        static let showInDock = "showInDock"
        static let disabledServices = "disabledServices"
        static let iconStyle = "iconStyle"
        static let iconRenderMode = "iconRenderMode"
        static let showBadgeCount = "showBadgeCount"
        static let menuBarTextMode = "menuBarTextMode"
        static let motionLevel = "motionLevel"
        static let notifyOnDegradation = "notifyOnDegradation"
        static let notifyOnRecovery = "notifyOnRecovery"
        static let notifyMinimumSeverity = "notifyMinimumSeverity"
        static let notifyPrimaryOnly = "notifyPrimaryOnly"
        static let notifySound = "notifySound"
        static let notifyCooldownMinutes = "notifyCooldownMinutes"
    }

    // MARK: - General

    var refreshInterval: RefreshInterval {
        get { RefreshInterval(rawValue: defaults.integer(forKey: Key.refreshInterval)) ?? .fiveMinutes }
        set { defaults.set(newValue.rawValue, forKey: Key.refreshInterval) }
    }

    var checkOnWake: Bool {
        get { defaults.bool(forKey: Key.checkOnWake) }
        set { defaults.set(newValue, forKey: Key.checkOnWake) }
    }

    var showInDock: Bool {
        get { defaults.bool(forKey: Key.showInDock) }
        set { defaults.set(newValue, forKey: Key.showInDock) }
    }

    // MARK: - Services

    private var disabledServices: Set<ServiceID> {
        get {
            let raw = defaults.stringArray(forKey: Key.disabledServices) ?? []
            return Set(raw.compactMap(ServiceID.init(rawValue:)))
        }
        set {
            defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.disabledServices)
        }
    }

    func isEnabled(_ service: ServiceID) -> Bool {
        !disabledServices.contains(service)
    }

    func setEnabled(_ enabled: Bool, for service: ServiceID) {
        var disabled = disabledServices
        if enabled { disabled.remove(service) } else { disabled.insert(service) }
        disabledServices = disabled
    }

    /// A disabled service is not fetched and does not feed the roll-up.
    var enabledServices: [ServiceDefinition] {
        ServiceRegistry.all.filter { isEnabled($0.id) }
    }

    // MARK: - Appearance

    var iconStyle: MenuBarIconStyle {
        get { enumValue(Key.iconStyle) ?? .hub }
        set { defaults.set(newValue.rawValue, forKey: Key.iconStyle) }
    }

    var iconRenderMode: IconRenderMode {
        get { enumValue(Key.iconRenderMode) ?? .monochromeWithPip }
        set { defaults.set(newValue.rawValue, forKey: Key.iconRenderMode) }
    }

    var showBadgeCount: Bool {
        get { defaults.bool(forKey: Key.showBadgeCount) }
        set { defaults.set(newValue, forKey: Key.showBadgeCount) }
    }

    var menuBarTextMode: MenuBarTextMode {
        get { enumValue(Key.menuBarTextMode) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarTextMode) }
    }

    var motionLevel: MotionLevel {
        get { enumValue(Key.motionLevel) ?? .full }
        set { defaults.set(newValue.rawValue, forKey: Key.motionLevel) }
    }

    // MARK: - Notifications

    var notifyOnDegradation: Bool {
        get { defaults.bool(forKey: Key.notifyOnDegradation) }
        set { defaults.set(newValue, forKey: Key.notifyOnDegradation) }
    }

    var notifyOnRecovery: Bool {
        get { defaults.bool(forKey: Key.notifyOnRecovery) }
        set { defaults.set(newValue, forKey: Key.notifyOnRecovery) }
    }

    var notifyMinimumSeverity: NotificationSeverity {
        get { enumValue(Key.notifyMinimumSeverity) ?? .minor }
        set { defaults.set(newValue.rawValue, forKey: Key.notifyMinimumSeverity) }
    }

    var notifyPrimaryOnly: Bool {
        get { defaults.bool(forKey: Key.notifyPrimaryOnly) }
        set { defaults.set(newValue, forKey: Key.notifyPrimaryOnly) }
    }

    var notifySound: Bool {
        get { defaults.bool(forKey: Key.notifySound) }
        set { defaults.set(newValue, forKey: Key.notifySound) }
    }

    var notifyCooldown: Duration {
        get { .seconds(defaults.integer(forKey: Key.notifyCooldownMinutes) * 60) }
        set { defaults.set(Int(newValue.components.seconds / 60), forKey: Key.notifyCooldownMinutes) }
    }

    // MARK: -

    private func enumValue<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:))
    }
}
